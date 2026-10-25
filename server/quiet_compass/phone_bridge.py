"""Agent-requested phone measurements; browser and agent hold separate short-lived capabilities.

The browser never receives the MCP key. It may only approve, poll, complete and revoke
its own session. Audio stays on the phone; only SharedContribution is accepted.
"""

from __future__ import annotations

import hashlib
import json
import math
import secrets
from datetime import datetime, timedelta
from typing import Any, Literal
from uuid import UUID, uuid4

from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError
from mcp_types import ToolAnnotations
from pydantic import Field
from starlette.concurrency import run_in_threadpool
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route

from .api import ApiError, parse_body
from .contracts import Contract, Goal, format_utc
from .db import parse_ts
from .phone_walk import NativeConsent, WalkResult, analyze_walk
from .shared_contracts import ContributionQuality, ContributionUpload, SharedContribution, SharedMeasurement
from .shared_layer import SharedLayer, cell_id

PHONE_TOOLS = {"connect_phone", "request_phone_measurement", "phone_measurement_status", "send_phone_recommendation"}
SESSION_SECONDS = 900


class PhoneError(ValueError):
    def __init__(self, message: str, status: int = 409):
        super().__init__(message)
        self.status = status


class Consent(Contract):
    microphone_consent: bool
    share_consent: bool


class PhoneResult(Contract):
    request_id: UUID
    upload: ContributionUpload | None = None
    error: str | None = Field(default=None, max_length=200)


class PhoneBridge:
    def __init__(self, layer: SharedLayer, page_url: str):
        self.layer, self.store, self.page_url = layer, layer.store, page_url
        with self.store._write() as conn:
            conn.execute("""CREATE TABLE IF NOT EXISTS phone_links (
                agent_hash TEXT PRIMARY KEY, browser_hash TEXT UNIQUE NOT NULL,
                expires_at TEXT NOT NULL, body TEXT NOT NULL)""")

    @staticmethod
    def _hash(token: str) -> str:
        if not 40 <= len(token) <= 80:
            raise PhoneError("Invalid phone session", 401)
        return hashlib.sha256(token.encode()).hexdigest()

    def connect(self) -> dict[str, Any]:
        agent, browser = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        expires = format_utc(self.store.clock() + timedelta(seconds=SESSION_SECONDS))
        with self.store._write() as conn:
            conn.execute("DELETE FROM phone_links WHERE expires_at <= ?", (self.store._now(),))
            if conn.execute("SELECT COUNT(*) FROM phone_links").fetchone()[0] >= 100:
                raise PhoneError("Too many pending phone connections; retry later", 429)
            conn.execute(
                "INSERT INTO phone_links VALUES (?, ?, ?, ?)",
                (
                    self._hash(agent),
                    self._hash(browser),
                    expires,
                    json.dumps(
                        {"consented": False, "revoked": False, "last_seen": None, "job": None, "recommendation": None}
                    ),
                ),
            )
        return {
            "phone_session_id": agent,
            "connect_url": self.page_url + "#pair=" + browser,
            "expires_at": expires,
            "status": "waiting_for_phone",
            "next": "Ask the user to open connect_url on their phone and approve microphone, location and sharing. "
            "Then call request_phone_measurement. Never use the link on your own computer.",
        }

    def _update(self, token: str, browser: bool, operation):
        column = "browser_hash" if browser else "agent_hash"
        with self.store._write() as conn:
            row = conn.execute(f"SELECT * FROM phone_links WHERE {column} = ?", (self._hash(token),)).fetchone()
            if row is None:
                raise PhoneError("Invalid phone session", 401)
            if row["expires_at"] <= self.store._now():
                raise PhoneError("Phone connection expired; connect again", 410)
            body = json.loads(row["body"])
            if body["revoked"]:
                raise PhoneError("Phone disconnected by the user", 410)
            job = body["job"]
            if job and job["state"] in {"pending", "measuring"}:
                age = (self.store.clock() - parse_ts(job["requested_at"])).total_seconds()
                if age >= job.get("duration_seconds", 30) + 60:
                    job.update(state="failed", error="Phone did not finish in time. Request a new measurement.")
            result = operation(body, row["expires_at"])
            conn.execute(f"UPDATE phone_links SET body = ? WHERE {column} = ?", (json.dumps(body), self._hash(token)))
            return result

    def _online(self, body) -> bool:
        return bool(
            body["consented"]
            and body["last_seen"]
            and (self.store.clock() - parse_ts(body["last_seen"])).total_seconds() < 60
        )

    def status(self, token: str, browser: bool = False):
        def read(body, expires):
            return {
                "status": "ready" if self._online(body) else "offline" if body["consented"] else "waiting_for_phone",
                "expires_at": expires,
                "client": body.get("client", "browser") if body["consented"] else None,
                "modes": ["walk"] if body.get("client") == "native" else ["sample"],
                "job": (
                    {k: v for k, v in body["job"].items() if k != "fingerprint"}
                    if not browser and body["job"]
                    else None
                ),
                "recommendation": body.get("recommendation") if not browser else None,
            }

        return self._update(token, browser, read)

    def consent(self, token: str, consent: Consent):
        if not consent.microphone_consent or not consent.share_consent:
            raise PhoneError("Microphone and summary sharing must be approved on the phone", 422)

        def approve(body, expires):
            if body["consented"] and body.get("client") == "native":
                raise PhoneError("This connection belongs to the iPhone app")
            body.update(consented=True, client="browser", last_seen=self.store._now())
            return {"status": "ready", "expires_at": expires}

        return self._update(token, True, approve)

    def native_consent(self, token: str, consent: NativeConsent):
        if not consent.microphone_consent or not consent.spatial_consent:
            raise PhoneError("Approve microphone and private room-map sharing on the phone", 422)

        def approve(body, expires):
            if body["consented"] and body.get("client") != "native":
                raise PhoneError("This connection belongs to the browser")
            body.update(consented=True, client="native", location_consented=consent.location_consent,
                        share_consent=consent.share_consent,
                        last_seen=self.store._now())
            return {"status": "ready", "expires_at": expires}

        return self._update(token, True, approve)

    def request(self, token: str, mode: str = "sample", duration_seconds: int = 60):
        def create(body, expires):
            if not self._online(body):
                raise PhoneError("Phone is not connected. Ask the user to open the link and approve access.")
            expected = "walk" if body.get("client") == "native" else "sample"
            if mode != expected:
                raise PhoneError(f"This phone supports mode={expected}; check phone_measurement_status")
            duration = duration_seconds if mode == "walk" else 10
            if mode == "walk" and not 30 <= duration <= 180:
                raise PhoneError("Walk analysis must last 30 to 180 seconds", 422)
            job = body["job"]
            if job and job["state"] in {"pending", "measuring"}:
                return {"status": job["state"], "request_id": job["request_id"], "expires_at": expires}
            if (parse_ts(expires) - self.store.clock()).total_seconds() < duration + 30:
                raise PhoneError("Not enough connection time left; reconnect the phone")
            body["recommendation"] = None
            body["job"] = {"request_id": str(uuid4()), "state": "pending", "requested_at": self.store._now(),
                           "mode": mode, "duration_seconds": duration}
            return {
                "status": "pending",
                "request_id": body["job"]["request_id"],
                "duration_seconds": duration,
                "mode": mode,
                "next": "Poll phone_measurement_status after 5 seconds. The phone submits automatically.",
            }

        return self._update(token, False, create)

    def poll(self, token: str, native: bool = False):
        def poll(body, expires):
            if not body["consented"]:
                raise PhoneError("Approve access on the phone before listening for agent requests", 403)
            if (body.get("client") == "native") != native:
                raise PhoneError("Use the connected phone client", 403)
            body["last_seen"] = self.store._now()
            job = body["job"]
            if job and job["state"] == "pending":
                job["state"] = "measuring"
                return {
                    "status": "measure",
                    "request_id": job["request_id"],
                    "duration_seconds": job.get("duration_seconds", 30),
                    "mode": job.get("mode", "sample"),
                    "expires_at": expires,
                    "recommendation": None,
                }
            return {"status": "waiting", "expires_at": expires, "recommendation": body.get("recommendation")}

        return self._update(token, True, poll)

    def disconnect(self, token: str):
        def revoke(body, _):
            body.update(revoked=True, consented=False, job=None, recommendation=None)
            return {"status": "disconnected"}

        return self._update(token, True, revoke)

    def complete(self, token: str, result: PhoneResult):
        if bool(result.error) == bool(result.upload):
            raise PhoneError("Send exactly one measurement or failure", 422)
        if result.upload:
            c = result.upload.contribution
            if (
                not result.upload.share_consent
                or c.source != "device"
                or str(c.id) != str(result.request_id)
                or c.duration_seconds not in (10, 30)
                or not c.quality.capture_profile.startswith("web-v1:")
                or c.lat is None
                or c.lon is None
                or c.area_name is not None
                or c.quality.clipping_detected
            ):
                raise PhoneError("Invalid phone measurement or sharing consent", 422)
        payload = result.model_dump(mode="json")
        fingerprint = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()

        def validate(body, _):
            job = body["job"]
            if (body.get("client") == "native" or not body["consented"]
                    or not job or job["request_id"] != str(result.request_id)):
                raise PhoneError("No matching consented measurement request")
            if job["state"] in {"complete", "failed"} and job.get("fingerprint") == fingerprint:
                return job
            if job["state"] != "measuring":
                raise PhoneError("Measurement is not active or was already completed")
            if job.get("fingerprint") and job["fingerprint"] != fingerprint:
                raise PhoneError("A retry must use the same measurement")
            job["fingerprint"] = fingerprint
            return None

        previous = self._update(token, True, validate)
        if previous:
            return {
                "status": previous["state"],
                "map_access": previous.get("contribution_result", {}).get("access_receipt"),
            }
        if result.error:
            # Never echo arbitrary client-supplied text into the agent's tool context.
            summary = {"state": "failed", "error": "The phone could not measure. Ask the user to check it."}
        elif result.upload:
            c = result.upload.contribution
            # SharedLayer re-rounds location, validates timestamp and issues the 15-minute receipt.
            accepted = self.layer.submit_shared(c, True)
            summary = {
                "state": "complete" if accepted.access_receipt else "failed",
                "contribution_result": accepted.model_dump(mode="json"),
                "measurement": c.measurement.model_dump(mode="json"),
                "lat": round(c.lat, 3),
                "lon": round(c.lon, 3),
                "time_bucket": format_utc(accepted.time_bucket),
                "capture_profile": c.quality.capture_profile,
                "source": "device",
                "verification": "phone_reported_summary",
                "note": "Relative uncalibrated browser measurement; no raw audio or hardware attestation.",
            }
        else:
            raise PhoneError("A measurement or failure is required", 422)

        def finish(body, _):
            job = body["job"]
            if not job or job["request_id"] != str(result.request_id):
                raise PhoneError("Measurement no longer active")
            job.update(summary)
            return {"status": job["state"], "map_access": job.get("contribution_result", {}).get("access_receipt")}

        return self._update(token, True, finish)

    def complete_walk(self, token: str, result: WalkResult):
        if bool(result.error) == bool(result.walk):
            raise PhoneError("Send one walk summary or a failure", 422)
        fingerprint = hashlib.sha256(result.model_dump_json().encode()).hexdigest()

        def finish(body, _):
            job = body["job"]
            if (not body["consented"] or body.get("client") != "native" or not job
                    or job.get("mode") != "walk" or job["request_id"] != str(result.request_id)):
                raise PhoneError("No matching native walk request")
            if job["state"] in {"complete", "failed"} and job.get("fingerprint") == fingerprint:
                return {"status": job["state"], "already_complete": True,
                        "duration_seconds": job.get("duration_seconds", 30),
                        "share_consent": bool(body.get("share_consent"))}
            if job["state"] != "measuring":
                raise PhoneError("Walk is not active or was already completed")
            if result.walk:
                if result.walk.location and not body.get("location_consented"):
                    raise PhoneError("Location was not approved on the phone", 422)
                try:
                    analysis = analyze_walk(result.walk, parse_ts(job["requested_at"]), self.store.clock(),
                                            job["duration_seconds"])
                except ValueError as exc:
                    raise PhoneError(str(exc), 422) from exc
                job.update(state="complete", walk=analysis, completed_at=self.store._now())
            else:
                job.update(state="failed", error="The phone could not analyze this walk. Check tracking and audio.")
            job["fingerprint"] = fingerprint
            return {"status": job["state"], "already_complete": False,
                    "duration_seconds": job.get("duration_seconds", 30),
                    "share_consent": bool(body.get("share_consent"))}

        completed = self._update(token, True, finish)
        if (completed["status"] == "complete" and completed["share_consent"]
                and result.walk and result.walk.location):
            # Submit outside the phone-link transaction; retries reuse this request ID.
            walk = result.walk
            samples = walk.samples
            levels = sorted(sample.level_dbfs for sample in samples)
            rms_dbfs = round(10 * math.log10(sum(10 ** (level / 10) for level in levels) / len(levels)), 2)
            variation_db = round(levels[round((len(levels) - 1) * .9)]
                                 - levels[round((len(levels) - 1) * .1)], 2)
            point = walk.location
            contribution = SharedContribution(
                id=result.request_id,
                schema_version="0.1",
                area_id=cell_id(round(point.lat, 3), round(point.lon, 3)),
                lat=point.lat,
                lon=point.lon,
                time_bucket=walk.started_at,
                duration_seconds=float(completed["duration_seconds"]),
                measurement=SharedMeasurement(
                    kind="relative_uncalibrated", rms_dbfs=rms_dbfs,
                    frame_level_spread_db=variation_db, calibrated=False,
                ),
                quality=ContributionQuality(capture_profile=walk.capture_profile, clipping_detected=False),
                source="device",
            )
            accepted = self.layer.submit_shared(contribution, share_consent=True)

            def attach_contribution(body, _):
                job = body.get("job")
                if job and job.get("fingerprint") == fingerprint:
                    job["contribution_result"] = accepted.model_dump(mode="json")
                return {"status": job["state"] if job else "complete"}

            self._update(token, True, attach_contribution)
        return {"status": completed["status"]}

    def recommend_walk(self, token, job, message, action, spot_index, max_walk_minutes, return_by):
        if (self.store.clock() - parse_ts(job["completed_at"])).total_seconds() > 900:
            raise PhoneError("Request a fresh walk before recommending")
        destination = None
        if action == "move":
            spot = next((s for s in job["walk"]["quiet_spots"] if s["spot_index"] == spot_index), None)
            if (not spot or spot["level_db"] > job["walk"]["current_level_dbfs"] - 3
                    or spot["distance_m"] < 1.5 or spot["distance_m"] / 60 > max_walk_minutes):
                raise PhoneError("No sufficiently quieter measured spot supports this move; report unknown")
            if return_by and 2 * spot["distance_m"] > (return_by - self.store.clock()).total_seconds():
                raise PhoneError("The estimated round trip does not fit the return time")
            destination = {**spot, "request_id": job["request_id"], "kind": "room", "route": "straight-line"}
        elif spot_index is not None:
            raise PhoneError("Only a move may name a spot", 422)
        recommendation = {"message": message.strip(), "action": action, "destination": destination,
                          "created_at": self.store._now(), "expires_at": self.status(token)["expires_at"]}

        def publish(body, _):
            if body["job"]["request_id"] != job["request_id"]:
                raise PhoneError("A new walk started; reassess before recommending")
            body["recommendation"] = recommendation
            return {"status": "queued_for_phone", "recommendation": recommendation}

        return self._update(token, False, publish)

    def recommend(
        self,
        token: str,
        message: str,
        action: str,
        area_id: str | None,
        goal: Goal,
        max_walk_minutes: int,
        return_by: datetime | None,
        spot_index: int | None = None,
    ):
        if not 1 <= len(message.strip()) <= 600 or action not in {"move", "stay", "unknown"}:
            raise PhoneError("A brief recommendation and valid action are required", 422)
        if not 1 <= max_walk_minutes <= 60 or (return_by is not None and return_by.tzinfo is None):
            raise PhoneError("Use a valid walk limit and a timezone-aware return time", 422)
        current = self.status(token)
        job = current["job"]
        if job and job["state"] == "complete" and job.get("mode") == "walk":
            if area_id is not None:
                raise PhoneError("Use spot_index for a room destination", 422)
            return self.recommend_walk(token, job, message, action, spot_index, max_walk_minutes, return_by)
        if spot_index is not None:
            raise PhoneError("Room spots require a native walk", 422)
        grant = job.get("contribution_result", {}) if job else {}
        if not job or job["state"] != "complete" or not self.store.has_access(grant.get("access_receipt")):
            raise PhoneError("Get a fresh phone measurement before recommending")
        destination = None
        if action == "move":
            candidates = self.layer.candidates(goal, job["lat"], job["lon"], max_walk_minutes, 15)
            target = next(
                (
                    candidate
                    for candidate in candidates
                    if candidate.aggregate.area_id == area_id
                    and candidate.aggregate.area_id != grant.get("area_id")
                    and candidate.aggregate.capture_profile == job["capture_profile"]
                    and candidate.aggregate.source == "device"
                    and candidate.aggregate.clipped_count == 0
                    and candidate.aggregate.median_rms_dbfs <= job["measurement"]["rms_dbfs"] - 3
                ),
                None,
            )
            if target is None:
                raise PhoneError("No comparable measured destination supports this move. Report unknown coverage.")
            if (
                return_by is not None
                and 2 * target.walk_minutes > (return_by - self.store.clock()).total_seconds() / 60
            ):
                raise PhoneError("The round trip does not fit the return time")
            destination = {
                "area_id": target.aggregate.area_id,
                "name": target.aggregate.area_name,
                "lat": target.aggregate.lat,
                "lon": target.aggregate.lon,
                "walk_minutes": round(target.walk_minutes, 1),
                "walk_source": "straight-line estimate",
                "age_minutes": round(target.aggregate.age_minutes, 1),
            }
        elif area_id is not None:
            raise PhoneError("Only a move may include a destination", 422)
        recommendation = {
            "message": message.strip(),
            "action": action,
            "destination": destination,
            "created_at": self.store._now(),
            "expires_at": grant["access_expires_at"],
        }

        def publish(body, _):
            if not body["job"] or body["job"]["request_id"] != job["request_id"]:
                raise PhoneError("A new measurement started; reassess before recommending")
            body["recommendation"] = recommendation
            return {
                "status": "queued_for_phone",
                "recommendation": recommendation,
                "note": "The phone page displays this on its next poll; this is not proof the user read it.",
            }

        return self._update(token, False, publish)


def register_phone_tools(mcp: MCPServer, bridge: PhoneBridge) -> None:
    def run(fn, *args):
        try:
            return fn(*args)
        except PhoneError as exc:
            raise ToolError(str(exc)) from exc

    @mcp.tool(
        annotations=ToolAnnotations(
            title="Connect the user's phone", readOnlyHint=False, destructiveHint=False, openWorldHint=False
        )
    )
    def connect_phone() -> dict[str, Any]:
        """Create a private 15-minute phone link. Show it to the user to open on THEIR phone.
        The phone owner must approve microphone, location and summary sharing there.
        No sensor starts from this tool alone. Keep phone_session_id private.
        """
        return run(bridge.connect)

    @mcp.tool(
        annotations=ToolAnnotations(
            title="Measure through the connected phone", readOnlyHint=False, destructiveHint=False, openWorldHint=False
        )
    )
    def request_phone_measurement(
        phone_session_id: str, mode: Literal["sample", "walk"] = "sample", duration_seconds: int = 60,
    ) -> dict[str, Any]:
        """Ask the connected browser phone to measure 10 seconds. Requires the user's consent.
        Use mode=walk for the linked iPhone app: 30–180 seconds of room mapping and sound
        analysis. With explicit sharing consent and location, it contributes a coarse summary
        and returns an access_receipt valid for 15 minutes. Browser mode=sample computes a
        10-second coarse summary and contributes automatically under that consent.
        Poll phone_measurement_status for the result and access_receipt; never invent readings.
        Repeating this call while pending returns the same request.
        """
        return run(bridge.request, phone_session_id, mode, duration_seconds)

    @mcp.tool(annotations=ToolAnnotations(title="Read the phone's measurement", readOnlyHint=True, openWorldHint=False))
    def phone_measurement_status(phone_session_id: str) -> dict[str, Any]:
        """Read actual phone state/result. A completed job contains contribution_result with
        access_receipt and access_expires_at for 15 minutes of shared queries in browser mode.
        Native mode=walk returns acoustic analysis and measured quiet_spots. With location and
        sharing consent, its coarse numeric summary also contributes to the shared map and returns
        a 15-minute access_receipt. Without sharing consent, its approximate location stays private
        to this owner and no receipt is issued. Use the receipt to query nearby shared sound data.
        Location is rounded to approximately 100 m. Null means unavailable. The experimental
        sound bearing is not verified source identification.
        Pending/offline is not success. Poll at most every 5 seconds. No need to resubmit the
        returned summary.
        """
        return run(bridge.status, phone_session_id)

    @mcp.tool(
        annotations=ToolAnnotations(
            title="Send a recommendation to the connected phone",
            readOnlyHint=False,
            destructiveHint=False,
            openWorldHint=False,
        )
    )
    def send_phone_recommendation(
        phone_session_id: str,
        message: str,
        action: Literal["move", "stay", "unknown"],
        area_id: str | None = None,
        goal: Goal = "rest",
        max_walk_minutes: int = 10,
        return_by: datetime | None = None,
        spot_index: int | None = None,
    ) -> dict[str, Any]:
        """Mirror a recommendation to the connected phone only when the owner asks for it.
        Normally, answer directly in the current Dot conversation; this tool does not write
        into that conversation. When used, a move must cite a returned area_id with recent real data from the
        SAME capture_profile and a level at least 3 dB lower than the current phone reading.
        Include the user's return_by deadline if known. If evidence is missing, use action
        unknown and explain the gap, never invent a quieter destination. This does not start
        navigation or schedule background monitoring; the user decides whether to move.
        For a native walk, use a returned quiet_spots spot_index instead of area_id; it must
        be at least 3 dB quieter than the last reading. Room maps stay private.
        """
        return run(bridge.recommend, phone_session_id, message, action, area_id, goal,
                   max_walk_minutes, return_by, spot_index)


def build_phone_routes(bridge: PhoneBridge) -> list[Route]:
    async def endpoint(request: Request):
        try:
            header = request.headers.get("authorization", "")
            if not header.startswith("Bearer "):
                raise PhoneError("Phone session required", 401)
            token = header[7:]
            action = request.path_params["action"]
            if action == "status":
                data = await run_in_threadpool(bridge.status, token, True)
            elif action == "native-consent":
                consent = await parse_body(request, NativeConsent)
                data = await run_in_threadpool(bridge.native_consent, token, consent)
            elif action == "native-poll":
                data = await run_in_threadpool(bridge.poll, token, True)
            elif action == "native-result":
                result = await parse_body(request, WalkResult)
                data = await run_in_threadpool(bridge.complete_walk, token, result)
            elif action == "consent":
                consent = await parse_body(request, Consent)
                data = await run_in_threadpool(bridge.consent, token, consent)
            elif action == "poll":
                data = await run_in_threadpool(bridge.poll, token)
            elif action == "result":
                result = await parse_body(request, PhoneResult)
                data = await run_in_threadpool(bridge.complete, token, result)
            elif action == "disconnect":
                data = await run_in_threadpool(bridge.disconnect, token)
            else:
                raise PhoneError("Unknown phone action", 404)
            return JSONResponse(data, headers={"Cache-Control": "no-store"})
        except (PhoneError, ApiError) as exc:
            status = exc.status if isinstance(exc, PhoneError) else exc.status_code
            detail = str(exc) if isinstance(exc, PhoneError) else exc.detail
            return JSONResponse({"error": detail}, status_code=status, headers={"Cache-Control": "no-store"})

    return [Route("/v1/phone/{action}", endpoint, methods=["POST"])]
