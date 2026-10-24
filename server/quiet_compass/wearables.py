"""Private wearable summaries for the existing single-participant installation.

Oura tokens, pending grants and HealthKit summaries are encrypted before storage.
No wearable data enters public map layers or acoustic observations.
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import logging
import secrets
from datetime import date, timedelta
from typing import Any, Literal
from urllib.parse import urlencode

import httpx2 as httpx
from cryptography.fernet import Fernet, InvalidToken
from pydantic import Field, model_validator

from .contracts import Contract, Timestamp, format_utc
from .db import Store
from .settings import Settings, SettingsError

OURA_AUTHORIZE = "https://cloud.ouraring.com/oauth/authorize"
OURA_TOKEN = "https://api.ouraring.com/oauth/token"
OURA_API = "https://api.ouraring.com/v2/usercollection"


class RedactOuraURL(logging.Filter):
    """httpx logs full request URLs at INFO, including Oura's revoke query string."""

    def filter(self, record: logging.LogRecord) -> bool:
        if "api.ouraring.com/oauth/revoke" in record.getMessage():
            record.msg, record.args = "Oura revocation request (URL redacted)", ()
        return True


logging.getLogger("httpx2").addFilter(RedactOuraURL())
MetricName = Literal[
    "sleep_seconds", "steps", "resting_heart_rate_bpm", "hrv_sdnn_ms", "sleep_score", "readiness_score"
]
UNITS = {
    "sleep_seconds": "seconds",
    "steps": "count",
    "resting_heart_rate_bpm": "bpm",
    "hrv_sdnn_ms": "ms",
    "sleep_score": "score",
    "readiness_score": "score",
}


class WearableError(Exception):
    def __init__(self, message: str, status: int = 503) -> None:
        self.status = status
        super().__init__(message)


class HealthMetric(Contract):
    name: MetricName
    value: float = Field(ge=0, allow_inf_nan=False)
    unit: str
    day: date

    @model_validator(mode="after")
    def validate_unit(self) -> HealthMetric:
        if self.unit != UNITS[self.name]:
            raise ValueError("Unit does not match metric")
        if self.name.endswith("score") and self.value > 100:
            raise ValueError("Score must be in the range 0–100")
        if self.name == "sleep_seconds" and self.value > 86400:
            raise ValueError("Sleep duration exceeds one day")
        return self


class HealthSnapshot(Contract):
    source: Literal["apple_health", "oura"]
    captured_at: Timestamp
    metrics: list[HealthMetric] = Field(max_length=40)
    note: str = Field(default="Daily summaries; not live measurements.", max_length=300)


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


class PrivateStore:
    def __init__(self, store: Store, key: str | None) -> None:
        self.store = store
        self.cipher: Fernet | None = None
        if key:
            try:
                raw = bytes.fromhex(key) if len(key) == 64 else base64.b64decode(key, altchars=b"-_", validate=True)
                if len(raw) != 32:
                    raise ValueError
                self.cipher = Fernet(base64.urlsafe_b64encode(raw))
            except (ValueError, TypeError) as exc:
                raise SettingsError("QC_ENCRYPTION_KEY must encode 32 random bytes as base64 or hex") from exc

    def encode(self, value: Any) -> bytes:
        if not self.cipher:
            raise WearableError("Private storage is not configured on this server.")
        return self.cipher.encrypt(json.dumps(value, allow_nan=False).encode())

    def decode(self, value: bytes) -> Any:
        if not self.cipher:
            raise WearableError("Private storage is not configured on this server.")
        try:
            return json.loads(self.cipher.decrypt(value))
        except (InvalidToken, ValueError) as exc:
            raise WearableError("Private data could not be opened. Check the server encryption key.") from exc

    def save(self, key: str, value: Any) -> None:
        encrypted = self.encode(value)
        with self.store._write() as conn:
            conn.execute(
                "INSERT INTO private_state VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET "
                "value=excluded.value, updated_at=excluded.updated_at",
                (key, encrypted, self.store._now()),
            )

    def read(self, key: str) -> Any:
        with self.store._read() as conn:
            row = conn.execute("SELECT value FROM private_state WHERE key=?", (key,)).fetchone()
        return self.decode(row[0]) if row else None

    def delete(self, *keys: str) -> None:
        with self.store._write() as conn:
            conn.executemany("DELETE FROM private_state WHERE key=?", ((key,) for key in keys))

    def pending(self, key: str, value: Any) -> None:
        encrypted = self.encode(value)
        now = self.store.clock()
        with self.store._write() as conn:
            conn.execute("DELETE FROM oauth_requests WHERE expires_at<=?", (format_utc(now),))
            conn.execute(
                "INSERT INTO oauth_requests VALUES (?, ?, ?)",
                (digest(key), encrypted, format_utc(now + timedelta(minutes=10))),
            )

    def consume(self, key: str) -> Any:
        with self.store._write() as conn:
            row = conn.execute("SELECT value, expires_at FROM oauth_requests WHERE key=?", (digest(key),)).fetchone()
            conn.execute("DELETE FROM oauth_requests WHERE key=?", (digest(key),))
        if not row or row[1] <= self.store._now():
            raise WearableError("This connection link expired or was already used. Start again.", 400)
        return self.decode(row[0])


class WearableService:
    def __init__(self, store: Store, settings: Settings, transport: httpx.AsyncBaseTransport | None = None) -> None:
        self.store, self.settings = store, settings
        self.private = PrivateStore(store, settings.encryption_key)
        self.transport = transport
        self.lock = asyncio.Lock()

    @property
    def configured(self) -> bool:
        return bool(
            self.private.cipher
            and self.settings.oura_client_id
            and self.settings.oura_client_secret
            and self.settings.public_url
        )

    @property
    def callback_url(self) -> str:
        return (self.settings.public_url or "").rstrip("/") + "/oauth/oura/callback"

    def connection_link(self) -> str:
        if not self.configured:
            raise WearableError("Oura is not configured. Set the server's Oura application credentials and public URL.")
        ticket = secrets.token_urlsafe(32)
        self.private.pending("ticket:" + ticket, {"purpose": "oura_connect"})
        return self.settings.public_url.rstrip("/") + "/connect/oura?" + urlencode({"ticket": ticket})

    def begin(self, ticket: str) -> tuple[str, str]:
        self.private.consume("ticket:" + ticket)
        state, browser, verifier = (secrets.token_urlsafe(32) for _ in range(3))
        self.private.pending("state:" + state, {"browser": digest(browser), "verifier": verifier})
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
        params = {
            "response_type": "code",
            "client_id": self.settings.oura_client_id,
            "redirect_uri": self.callback_url,
            "scope": "daily",
            "state": state,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
        }
        return OURA_AUTHORIZE + "?" + urlencode(params), browser

    def client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(timeout=15, transport=self.transport, follow_redirects=False)

    async def _exchange(self, grant: dict[str, str]) -> dict[str, Any]:
        async with self.client() as client:
            try:
                response = await client.post(
                    OURA_TOKEN,
                    data={
                        **grant,
                        "client_id": self.settings.oura_client_id,
                        "client_secret": self.settings.oura_client_secret,
                    },
                )
            except httpx.HTTPError as exc:
                raise WearableError("Oura could not be reached. Try again.") from exc
        if response.status_code in {400, 401, 403}:
            raise WearableError("Oura authorization expired or was rejected. Reconnect Oura.", 401)
        if response.status_code != 200:
            raise WearableError("Oura could not complete authorization. Try again later.")
        try:
            token = response.json()
            access, refresh = token["access_token"], token["refresh_token"]
            expires = int(token["expires_in"])
            if not isinstance(access, str) or not access or not isinstance(refresh, str) or not refresh or expires <= 0:
                raise ValueError
        except (KeyError, TypeError, ValueError) as exc:
            raise WearableError("Oura returned an incomplete authorization.") from exc
        return {
            "access_token": access,
            "refresh_token": refresh,
            "expires_at": self.store.clock().timestamp() + expires,
        }

    async def finish(self, state: str, browser: str, code: str | None, denied: bool) -> None:
        async with self.lock:
            grant = self.private.consume("state:" + state)
            if not browser or not hmac.compare_digest(grant["browser"], digest(browser)):
                raise WearableError("The authorization does not match this browser. Start again.", 400)
            if denied or not code:
                raise WearableError("Oura access was not granted.", 400)
            token = await self._exchange(
                {
                    "grant_type": "authorization_code",
                    "code": code,
                    "code_verifier": grant["verifier"],
                    "redirect_uri": self.callback_url,
                }
            )
            self.private.save("oura_tokens", token)
            self.private.delete("summary:oura")

    async def _access(self, force: bool = False) -> str:
        token = self.private.read("oura_tokens")
        if not token:
            raise WearableError("Connect Oura first.", 409)
        if force or token["expires_at"] <= self.store.clock().timestamp() + 60:
            try:
                token = await self._exchange({"grant_type": "refresh_token", "refresh_token": token["refresh_token"]})
            except WearableError as exc:
                if exc.status == 401:
                    self.private.delete("oura_tokens", "summary:oura")
                raise
            self.private.save("oura_tokens", token)
        return token["access_token"]

    async def sync_oura(self) -> dict[str, Any]:
        async with self.lock:
            access = await self._access()
            today = self.store.clock().date()
            params = {"start_date": str(today - timedelta(days=8)), "end_date": str(today)}
            endpoints = {
                "daily_sleep": ("sleep_score", "score"),
                "daily_readiness": ("readiness_score", "score"),
                "daily_activity": ("steps", "steps"),
                "sleep": ("sleep_seconds", "total_sleep_duration"),
            }
            metrics: list[HealthMetric] = []
            warnings: list[str] = []
            refreshed = False
            async with self.client() as client:
                for kind, (name, field_name) in endpoints.items():
                    try:
                        response = await client.get(
                            f"{OURA_API}/{kind}", params=params, headers={"Authorization": f"Bearer {access}"}
                        )
                        if response.status_code == 401 and not refreshed:
                            access = await self._access(force=True)
                            refreshed = True
                            response = await client.get(
                                f"{OURA_API}/{kind}", params=params, headers={"Authorization": f"Bearer {access}"}
                            )
                        if response.status_code == 401:
                            self.private.delete("oura_tokens", "summary:oura")
                            raise WearableError("Oura access was revoked. Reconnect Oura.", 401)
                        if response.status_code != 200:
                            warnings.append(f"{kind}: unavailable ({response.status_code})")
                            continue
                        rows = response.json().get("data", [])
                        if not isinstance(rows, list) or any(not isinstance(r, dict) for r in rows):
                            raise ValueError("Invalid summary list")
                        if kind == "sleep":
                            rows = [r for r in rows if r.get("type") == "long_sleep"]
                        valid = [r for r in rows if r.get(field_name) is not None and r.get("day")]
                        if valid:
                            last = max(valid, key=lambda r: r["day"])
                            metrics.append(
                                HealthMetric(name=name, value=last[field_name], unit=UNITS[name], day=last["day"])
                            )
                    except (httpx.HTTPError, ValueError, TypeError, KeyError, AttributeError):
                        warnings.append(f"{kind}: could not retrieve a valid summary")
            snapshot = HealthSnapshot(source="oura", captured_at=self.store.clock(), metrics=metrics)
            result = {**snapshot.model_dump(mode="json"), "warnings": warnings}
            # Do not replace the last useful data with an upstream outage.
            if warnings and not metrics:
                raise WearableError("Oura summaries are temporarily unavailable. Previously saved data is unchanged.")
            self.private.save("summary:oura", result)
            return result

    async def sync_periodically(self) -> None:
        """One worker per private server; the lock serializes rotating refresh tokens."""
        while True:
            await asyncio.sleep(15 * 60)
            try:
                if self.private.read("oura_tokens"):
                    await self.sync_oura()
            except WearableError:
                # Keep the original captured_at timestamp during outages. Manual sync
                # returns actionable errors; never log provider URLs or health values.
                continue

    def save_health(self, snapshot: HealthSnapshot) -> None:
        if snapshot.source != "apple_health":
            raise WearableError("Only Apple Health summaries may be uploaded here.", 422)
        now = self.store.clock()
        if snapshot.captured_at > now + timedelta(minutes=5) or any(
            m.day > now.date() + timedelta(days=1) for m in snapshot.metrics
        ):
            raise WearableError("Summary dates cannot be in the future.", 422)
        if any(m.name.endswith("score") for m in snapshot.metrics):
            raise WearableError("Oura scores cannot be attributed to Apple Health.", 422)
        current = self.private.read("summary:apple_health")
        if current and current["captured_at"] > snapshot.model_dump(mode="json")["captured_at"]:
            raise WearableError("A newer Apple Health summary is already stored.", 409)
        self.private.save("summary:apple_health", snapshot.model_dump(mode="json"))

    def context(self) -> dict[str, Any]:
        if not self.private.cipher:
            return {"status": "not_configured", "sources": {}, "note": "Private wearable storage is not configured."}
        sources = {}
        for source in ("oura", "apple_health"):
            summary = self.private.read("summary:" + source)
            if summary:
                sources[source] = summary
        return {
            "status": "available" if sources else "no_data",
            "sources": sources,
            "oura_configured": self.configured,
            "oura_connected": bool(self.private.read("oura_tokens")),
            "note": "Private daily context, not live physiology or environmental measurements. Use metric dates.",
        }

    async def disconnect(self, source: str) -> dict[str, Any]:
        if source not in {"oura", "apple_health"}:
            raise WearableError("Unknown wearable source.", 404)
        async with self.lock:
            token = self.private.read("oura_tokens") if source == "oura" else None
            revoked = False
            if token:
                # Oura's documented revocation API uses a query parameter. Do not log
                # HTTP client URLs or exceptions, and disable access logs in deployment.
                try:
                    async with self.client() as client:
                        response = await client.get(
                            "https://api.ouraring.com/oauth/revoke", params={"access_token": token["access_token"]}
                        )
                    revoked = response.is_success
                except httpx.HTTPError:
                    pass
            self.private.delete("summary:" + source, *(["oura_tokens"] if source == "oura" else []))
            # Invalidate outstanding links so a late callback cannot restore a disconnected account.
            if source == "oura":
                with self.store._write() as conn:
                    conn.execute("DELETE FROM oauth_requests")
            return {
                "disconnected": True,
                "provider_revoked": revoked if token else None,
                "message": "Private server data deleted."
                if not token or revoked
                else "Server data deleted. Also remove this app in Oura settings; remote revocation was unavailable.",
            }
