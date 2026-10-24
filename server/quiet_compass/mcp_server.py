"""MCP tools for the agent. They act on the active session (see `Service.active_session`).

Responses are Pydantic models (structured output). Concise responses carry place
labels and ages only; `response_format="detailed"` adds ids. Invalid input raises
`ToolError` (returned as `isError`), every other situation is a normal result.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from statistics import median
from typing import Any, Literal

from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError
from mcp_types import ToolAnnotations
from pydantic import BaseModel, SerializerFunctionWrapHandler, model_serializer

from . import scoring
from .city import CityDataError, CityNoiseLayer
from .contracts import Feedback, Goal, Observation, Place, Session, format_utc
from .db import Store, utc_now
from .settings import Settings
from .sf_layers import ALL_LAYERS, REFERENCE_LEVELS, REFERENCE_NOTE, LayerName, SfLayers

ResponseFormat = Literal["concise", "detailed"]
RECENT_WINDOW = timedelta(seconds=30)
NO_SESSION = (
    "No recording session yet. Ask the user to open Quiet Compass on the phone and walk "
    "around for a minute so there is something to recommend from."
)
INSTRUCTIONS = (
    "Quiet Compass remembers relative sound levels (dBFS, not dBA) the user's phone "
    "measured at places in this venue. Call quiet_get_context before recommending, always "
    "state how old a measurement is, never call an unmeasured place quiet, and call "
    "quiet_start_guidance only after the user agrees."
)


class Lean(BaseModel):
    """Drops null fields from the output to keep responses short."""

    @model_serializer(mode="wrap")
    def _drop_none(self, handler: SerializerFunctionWrapHandler) -> dict[str, Any]:
        return {k: v for k, v in handler(self).items() if v is not None}


# --- output models ----------------------------------------------------------------------


class SoundNow(Lean):
    level_dbfs_rel: float
    spread_db: float
    peaks_per_min: float
    speech_share: float | None = None
    classes: list[str] | None = None
    age_s: float
    tracking: str
    observations_in_window: int


class PlaceBrief(Lean):
    label: str
    tags: list[str]
    last_level_dbfs_rel: float | None = None
    last_measured_min_ago: float | None = None
    place_id: str | None = None


class GuidanceBrief(Lean):
    target_label: str
    status: str
    reason: str | None = None
    updated_min_ago: float
    target_place_id: str | None = None


class FeedbackBrief(Lean):
    goal: str
    verdict: str
    feel: str | None = None
    min_ago: float


class PlaceHistory(Lean):
    count: int
    latest_level_dbfs_rel: float | None = None
    latest_spread_db: float | None = None
    latest_peaks_per_min: float | None = None
    latest_speech_share: float | None = None
    median_level_dbfs_rel: float | None = None
    newest_min_ago: float | None = None
    oldest_min_ago: float | None = None


class Changes(Lean):
    first_call: bool
    new_observations: int
    level_change_db: float | None = None
    summary: str


class Route(Lean):
    walked_distance_m: float
    walk_minutes: float
    source: str


class Context(Lean):
    session_name: str | None = None
    capture_mode: str | None = None
    message: str | None = None
    now: SoundNow | None = None
    places: list[PlaceBrief] | None = None
    guidance: GuidanceBrief | None = None
    place: PlaceBrief | None = None
    history: PlaceHistory | None = None
    feedback: list[FeedbackBrief] | None = None
    changes_since_last_call: Changes | None = None
    route: Route | None = None
    session_id: str | None = None


class Evidence(Lean):
    level_dbfs_rel: float
    spread_db: float
    peaks_per_min: float
    speech_share: float | None = None
    age_min: float


class Terms(Lean):
    S: float
    F_measured: float
    F_prior: float
    freshness_w: float
    distance_penalty: float


class SpaceResult(Lean):
    label: str
    score: Terms
    evidence: Evidence
    walk_minutes: float
    why: str
    place_id: str | None = None


class FindSpaceResult(Lean):
    no_fit: bool
    results: list[SpaceResult] | None = None
    closest: list[SpaceResult] | None = None
    relax: str | None = None
    message: str
    minutes_available: float


class GuidanceResult(Lean):
    status: str
    target_label: str
    reason: str | None = None
    message: str


class FeedbackResult(Lean):
    stored: bool
    message: str


class CityResult(Lean):
    lat: float
    lon: float
    radius_m: int
    hours: int
    total_reports: int
    by_subtype: dict[str, int]
    newest_report_min_ago: float | None = None
    caveat: str


class LayerPointOut(Lean):
    layer: str
    kind: str
    label: str
    lat: float
    lon: float
    evidence: Literal["unmeasured_candidate", "proxy", "measured", "measured_crowdsourced"]
    caveat: str
    dataset: str
    source: str | None = None
    detail: str | None = None
    cnel_db: float | None = None
    observed_on: str | None = None
    distance_m: int | None = None
    count: int | None = None
    max_level_db: float | None = None
    median_level_db: float | None = None
    laeq_db: float | None = None
    quality: str | None = None


class ReferenceOut(Lean):
    id: str
    area: str
    location: str
    level_dba_ldn: int
    duration: str
    measured_on: str
    source: str
    source_url: str
    evidence: str


class SfLayersResult(Lean):
    lat: float
    lon: float
    radius_m: int
    layers: dict[str, list[LayerPointOut]]
    unavailable: dict[str, str] | None = None
    references: list[ReferenceOut] | None = None
    reference_note: str | None = None
    note: str


# --- service ----------------------------------------------------------------------------


def _minutes(delta: timedelta) -> float:
    return round(max(delta.total_seconds(), 0) / 60, 1)


def _xz(position: Any) -> tuple[float, float] | None:
    return (position.x, position.z) if position is not None else None


def _features(o: Observation) -> scoring.Features:
    return scoring.Features(o.level_dbfs_rel, o.spread_db, o.peaks_per_min, o.speech_share)


class Service:
    """Tool logic, independent of the MCP transport so it is easy to test."""

    def __init__(
        self,
        store: Store,
        settings: Settings,
        clock: Callable[[], datetime] = utc_now,
        cfg: scoring.ScoringConfig = scoring.DEFAULT_CONFIG,
    ) -> None:
        self.store = store
        self.settings = settings
        self.clock = clock
        self.cfg = cfg

    def active_session(self) -> Session | None:
        if self.settings.active_session_id:
            return self.store.get_session(self.settings.active_session_id)
        return self.store.latest_session()

    def _place(self, session: Session, place_id: str) -> Place:
        for place in self.store.places(session.id):
            if str(place.id) == place_id.strip().lower():
                return place
        raise ToolError(
            f"Unknown place_id {place_id!r}. Call quiet_get_context with "
            "response_format='detailed' to list place ids."
        )

    # -- distances -----------------------------------------------------------------------

    def _distance(self, session: Session, place: Place) -> tuple[float, scoring.DistanceSource]:
        crumbs = self.store.crumbs(session.id)
        path = [(c.position.x, c.position.z) for c in crumbs]
        index = next((i for i, c in enumerate(crumbs) if c.id == place.crumb_id), None)
        user = self._user_position(session, path)
        return scoring.estimate_distance(path, index, _xz(place.position), user, self.cfg)

    def _user_position(
        self, session: Session, path: list[tuple[float, float]]
    ) -> tuple[float, float] | None:
        if path:
            return path[-1]
        located = [o for o in self.store.observations(session.id) if o.position is not None]
        return _xz(located[-1].position) if located else None

    # -- quiet_get_context ---------------------------------------------------------------

    def get_context(self, place_id: str | None, response_format: ResponseFormat) -> Context:
        session = self.active_session()
        if session is None:
            return Context(message=NO_SESSION)
        detailed = response_format == "detailed"
        base = Context(
            session_name=session.name,
            capture_mode=session.device_profile.capture_mode,
            session_id=str(session.id) if detailed else None,
        )
        if place_id is None:
            return self._overview(session, base, detailed)
        return self._place_context(session, self._place(session, place_id), base, detailed)

    def _brief(self, place: Place, obs: list[Observation], detailed: bool) -> PlaceBrief:
        now = self.clock()
        mine = [o for o in obs if o.place_id == place.id]
        latest = mine[-1] if mine else None
        return PlaceBrief(
            label=place.label,
            tags=list(place.tags),
            last_level_dbfs_rel=round(latest.level_dbfs_rel, 1) if latest else None,
            last_measured_min_ago=_minutes(now - latest.t) if latest else None,
            place_id=str(place.id) if detailed else None,
        )

    def _overview(self, session: Session, base: Context, detailed: bool) -> Context:
        now = self.clock()
        obs = self.store.observations(session.id)
        places = self.store.places(session.id)
        guidance = self.store.get_guidance(session.id)
        update: dict[str, Any] = {
            "places": [self._brief(p, obs, detailed) for p in places],
            "now": self._sound_now(obs, now),
        }
        if guidance is not None and guidance.status == "active":
            update["guidance"] = GuidanceBrief(
                target_label=guidance.target_label,
                status=guidance.status,
                reason=guidance.reason,
                updated_min_ago=_minutes(now - guidance.updated_at),
                target_place_id=str(guidance.target_place_id) if detailed else None,
            )
        if not obs:
            update["message"] = "Nothing measured yet in this session."
        # TODO(next_event): add a labelled demo schedule / calendar hint here if wanted.
        return base.model_copy(update=update)

    def _sound_now(self, obs: list[Observation], now: datetime) -> SoundNow | None:
        if not obs:
            return None
        latest = obs[-1]
        window = [o for o in obs if latest.t - o.t <= RECENT_WINDOW]
        speech = [o.speech_share for o in window if o.speech_share is not None]
        return SoundNow(
            level_dbfs_rel=round(median(o.level_dbfs_rel for o in window), 1),
            spread_db=round(median(o.spread_db for o in window), 1),
            peaks_per_min=round(median(o.peaks_per_min for o in window), 1),
            speech_share=round(median(speech), 2) if speech else None,
            classes=[c.label for c in latest.classes] or None,
            age_s=round(max((now - latest.t).total_seconds(), 0), 0),
            tracking=latest.tracking,
            observations_in_window=len(window),
        )

    def _place_context(
        self, session: Session, place: Place, base: Context, detailed: bool
    ) -> Context:
        now = self.clock()
        obs = [o for o in self.store.observations(session.id) if o.place_id == place.id]
        latest = obs[-1] if obs else None
        history = PlaceHistory(count=len(obs))
        if latest is not None:
            history = PlaceHistory(
                count=len(obs),
                latest_level_dbfs_rel=round(latest.level_dbfs_rel, 1),
                latest_spread_db=round(latest.spread_db, 1),
                latest_peaks_per_min=round(latest.peaks_per_min, 1),
                latest_speech_share=latest.speech_share,
                median_level_dbfs_rel=round(median(o.level_dbfs_rel for o in obs), 1),
                newest_min_ago=_minutes(now - latest.t),
                oldest_min_ago=_minutes(now - obs[0].t),
            )
        feedback = [
            FeedbackBrief(goal=f.goal, verdict=f.verdict, feel=f.feel, min_ago=_minutes(now - f.t))
            for f in self.store.feedback(session.id)
            if f.place_id == place.id
        ]
        distance, source = self._distance(session, place)
        changes = self._changes(session, place, obs)
        self.store.record_context_read(
            session.id, place.id, latest.t if latest else None,
            latest.level_dbfs_rel if latest else None,
        )
        return base.model_copy(
            update={
                "place": self._brief(place, obs, detailed),
                "history": history,
                "feedback": feedback,
                "changes_since_last_call": changes,
                "route": Route(
                    walked_distance_m=round(distance, 1),
                    walk_minutes=round(scoring.walk_minutes(distance, self.cfg), 1),
                    source=source,
                ),
            }
        )

    def _changes(self, session: Session, place: Place, obs: list[Observation]) -> Changes:
        previous = self.store.last_context_read(session.id, place.id)
        if previous is None:
            return Changes(first_call=True, new_observations=len(obs), summary="First look at this place.")
        since = previous.latest_obs_t
        new = [o for o in obs if since is None or o.t > since]
        if not new:
            return Changes(first_call=False, new_observations=0, summary="No new measurements since you last checked.")
        delta = None
        if previous.latest_level is not None:
            delta = round(new[-1].level_dbfs_rel - previous.latest_level, 1)
        summary = f"{len(new)} new measurement(s)"
        if delta is not None:
            summary += f"; level {'up' if delta > 0 else 'down'} {abs(delta)} dB" if delta else "; level unchanged"
        return Changes(first_call=False, new_observations=len(new), level_change_db=delta, summary=summary)

    # -- quiet_find_space ----------------------------------------------------------------

    def find_space(
        self,
        goal: Goal,
        duration_minutes: int,
        return_by: datetime,
        needs: list[str] | None,
        detailed: bool = False,
    ) -> FindSpaceResult:
        now = self.clock()
        if return_by.tzinfo is None:
            return_by = return_by.replace(tzinfo=UTC)
        if return_by <= now:
            raise ToolError(
                f"return_by {format_utc(return_by)} is not in the future (now is {format_utc(now)}). "
                "Pass a later time in ISO 8601, e.g. the start of the user's next activity."
            )
        if duration_minutes <= 0:
            raise ToolError("duration_minutes must be a positive number of minutes.")
        session = self.active_session()
        if session is None:
            return FindSpaceResult(
                no_fit=True, relax="measure_more", message=NO_SESSION,
                minutes_available=_minutes(return_by - now),
            )
        obs = self.store.observations(session.id)
        inputs = [self._place_input(session, p, obs) for p in self.store.places(session.id)]
        feedback = [self._feedback_input(f) for f in self.store.feedback(session.id)]
        request = scoring.SpaceRequest(goal, duration_minutes, return_by, now, frozenset(needs or ()))
        outcome = scoring.find_space(request, inputs, [o.level_dbfs_rel for o in obs], feedback, self.cfg)
        return self._present(outcome, goal, detailed)

    def _place_input(self, session: Session, place: Place, obs: list[Observation]) -> scoring.PlaceInput:
        distance, source = self._distance(session, place)
        mine = tuple(scoring.Observed(o.t, _features(o)) for o in obs if o.place_id == place.id)
        return scoring.PlaceInput(str(place.id), place.label, frozenset(place.tags), mine, distance, source)

    @staticmethod
    def _feedback_input(f: Feedback) -> scoring.FeedbackInput:
        return scoring.FeedbackInput(str(f.place_id), f.goal, f.verdict, f.feel, f.t)

    def _result(self, c: scoring.Candidate, detailed: bool) -> SpaceResult:
        latest = c.place.latest
        assert latest is not None
        f = latest.features
        t = c.terms
        return SpaceResult(
            label=c.place.label,
            score=Terms(
                S=round(t.score, 2), F_measured=round(t.f_measured, 2), F_prior=round(t.f_prior, 2),
                freshness_w=round(t.freshness_w, 2), distance_penalty=round(t.distance_penalty, 2),
            ),
            evidence=Evidence(
                level_dbfs_rel=round(f.level_db, 1), spread_db=round(f.spread_db, 1),
                peaks_per_min=round(f.peaks_per_min, 1), speech_share=f.speech_share,
                age_min=round(t.age_min, 1),
            ),
            walk_minutes=round(c.walk_minutes, 1),
            why=self._why(c),
            place_id=c.place.place_id if detailed else None,
        )

    @staticmethod
    def _why(c: scoring.Candidate) -> str:
        latest = c.place.latest
        assert latest is not None
        f = latest.features
        parts = [f"{f.level_db:.0f} dBFS rel measured {c.terms.age_min:.0f} min ago"]
        parts.append("steady" if f.spread_db <= 6 else "variable")
        parts.append("few peaks" if f.peaks_per_min <= 2 else f"{f.peaks_per_min:.0f} peaks/min")
        if c.terms.chaotic_capped:
            parts.append("rated chaotic recently")
        parts.append(f"{c.walk_minutes:.0f} min walk")
        return ", ".join(parts)

    def _present(self, outcome: scoring.SpaceOutcome, goal: Goal, detailed: bool) -> FindSpaceResult:
        minutes = round(outcome.minutes_available, 1)
        if not outcome.no_fit:
            return FindSpaceResult(
                no_fit=False,
                results=[self._result(c, detailed) for c in outcome.results],
                message=f"{len(outcome.results)} place(s) fit {goal}. Levels are relative; mention the age.",
                minutes_available=minutes,
            )
        closest = [self._result(outcome.closest, detailed)] if outcome.closest else []
        hints = {
            "time": "Nothing fits the time available; a shorter stay or a later return would help.",
            "seating": "Places that fit lack seating; dropping that need would open options.",
            "step_free": "Places that fit are not marked step-free; check if that need can change.",
            "measure_more": "No measured place fits well; measuring a few more spots would help.",
        }
        return FindSpaceResult(
            no_fit=True,
            closest=closest,
            relax=outcome.relax,
            message=hints[outcome.relax or "measure_more"],
            minutes_available=minutes,
        )

    # -- writes ----------------------------------------------------------------------------

    def start_guidance(self, place_id: str, reason: str | None) -> GuidanceResult:
        session = self.active_session()
        if session is None:
            return GuidanceResult(status="none", target_label="", message=NO_SESSION)
        place = self._place(session, place_id)
        guidance = self.store.start_guidance(place, reason)
        return GuidanceResult(
            status=guidance.status, target_label=guidance.target_label, reason=guidance.reason,
            message=f"The phone will guide the user to {place.label} within a few seconds.",
        )

    def record_feedback(self, place_id: str, goal: Goal, verdict: str, feel: str | None) -> FeedbackResult:
        session = self.active_session()
        if session is None:
            return FeedbackResult(stored=False, message=NO_SESSION)
        place = self._place(session, place_id)
        row = Feedback(
            id=uuid.uuid4(), session_id=session.id, place_id=place.id,
            goal=goal, verdict=verdict, feel=feel, t=self.clock(),  # type: ignore[arg-type]
        )
        self.store.add_feedback([row])
        return FeedbackResult(stored=True, message=f"Saved: {place.label} was {verdict} for {goal}.")


# --- MCP wiring -------------------------------------------------------------------------


def build_mcp(
    service: Service, city: CityNoiseLayer | None = None, layers: SfLayers | None = None
) -> MCPServer:
    mcp = MCPServer("quiet-compass", instructions=INSTRUCTIONS)

    @mcp.tool(annotations=ToolAnnotations(title="Sound context", readOnlyHint=True, openWorldHint=False))
    def quiet_get_context(place_id: str | None = None, response_format: ResponseFormat = "concise") -> Context:
        """Recent sound around the user and the places they marked, or one place in depth.

        Without place_id: the last ~30 s at the user's phone (relative level in dBFS,
        spread, peaks per minute, speech share, sound classes, age), every known place with
        its last level and how many minutes ago it was measured, and active guidance.
        With place_id: that place's measurement history, ratings, what changed since you
        last asked, and the walking distance along the user's recorded path.
        Levels are relative to this phone (higher = louder, never dBA). Use
        response_format='detailed' to get place ids for the other tools.
        """
        return service.get_context(place_id, response_format)

    @mcp.tool(annotations=ToolAnnotations(title="Find a space", readOnlyHint=True, openWorldHint=False))
    def quiet_find_space(
        goal: Goal,
        duration_minutes: int,
        return_by: datetime,
        needs: list[Literal["seating", "step_free"]] | None = None,
        response_format: ResponseFormat = "detailed",
    ) -> FindSpaceResult:
        """Rank up to 3 measured places for a goal (talk, rest or work) that the user can
        reach, stay at for duration_minutes and walk back from before return_by.

        return_by is ISO 8601; a time without an offset is treated as UTC, so include the
        offset (e.g. 2026-10-24T15:30:00-07:00). Each result has a score S (0-1), its terms,
        the evidence (latest level, spread, peaks, speech share, age in minutes), walk time
        and a one-line why. If nothing fits, the result has no_fit=true, at most one closest
        option and `relax`: the constraint to ask the user about (time, seating, step_free)
        or measure_more. Never present an unmeasured place as quiet.
        """
        return service.find_space(goal, duration_minutes, return_by, needs, response_format == "detailed")

    @mcp.tool(
        annotations=ToolAnnotations(
            title="Guide the user to a place", readOnlyHint=False, destructiveHint=False,
            idempotentHint=True, openWorldHint=False,
        )
    )
    def quiet_start_guidance(place_id: str, reason: str | None = None) -> GuidanceResult:
        """Tell the user's phone to guide them back to a place along their recorded path.

        Call only after the user agreed to go. `reason` is shown on the phone; keep it under
        ~60 characters, calm and factual (e.g. 'Quietest spot you measured, 4 min ago').
        Calling again with the same place is harmless; a different place replaces the target.
        """
        return service.start_guidance(place_id, reason)

    @mcp.tool(
        annotations=ToolAnnotations(
            title="Save the user's rating", readOnlyHint=False, destructiveHint=False,
            idempotentHint=False, openWorldHint=False,
        )
    )
    def quiet_record_feedback(
        place_id: str,
        goal: Goal,
        verdict: Literal["good", "ok", "bad"],
        feel: Literal["calm", "neutral", "chaotic"] | None = None,
    ) -> FeedbackResult:
        """Store the user's own rating of a place for a goal, after they arrived and you
        asked one short question. Ratings personalise future recommendations. Record only
        what the user said; do not infer it."""
        return service.record_feedback(place_id, goal, verdict, feel)

    if city is not None:

        @mcp.tool(
            annotations=ToolAnnotations(
                title="SF 311 noise reports", readOnlyHint=True, openWorldHint=True
            )
        )
        def quiet_city_noise_reports(
            lat: float, lon: float, radius_m: int = 200, hours: int = 48
        ) -> CityResult:
            """Count San Francisco 311 noise complaints near a point (DataSF). These are
            complaints, not measurements; zero reports does not mean a place is quiet.
            radius_m 50-2000, hours 1-168."""
            if not (37.6 <= lat <= 37.85 and -122.55 <= lon <= -122.35):
                raise ToolError("lat/lon must be inside San Francisco.")
            if not (50 <= radius_m <= 2000 and 1 <= hours <= 168):
                raise ToolError("Use radius_m between 50 and 2000 and hours between 1 and 168.")
            try:
                s = city.nearby(lat, lon, radius_m, hours)
            except CityDataError as exc:
                raise ToolError(f"DataSF is unavailable right now ({exc}). Try again later.") from exc
            return CityResult(
                lat=s.lat, lon=s.lon, radius_m=s.radius_m, hours=s.hours, total_reports=s.total,
                by_subtype=s.by_subtype, newest_report_min_ago=s.newest_age_min, caveat=s.caveat,
            )

    if layers is not None:

        @mcp.tool(
            annotations=ToolAnnotations(title="SF sound context layers", readOnlyHint=True, openWorldHint=True)
        )
        def quiet_sf_layers(
            lat: float,
            lon: float,
            radius_m: int = 600,
            include: list[LayerName] | None = None,
            include_references: bool = False,
        ) -> SfLayersResult:
            """Real San Francisco layers near a point (DataSF), each labelled by evidence.

            quiet_candidates: POPOS, public libraries and Rec & Park parks/play areas,
            evidence=unmeasured_candidate, source=seed (parks can be loud too).
            Nobody measured their sound; never call them quiet, mention
            hours must be checked. entertainment_permits, night_noise_permits (today or
            tomorrow) and street_closures (in effect now): evidence=proxy, they hint that
            something may be loud, they are not levels. sfo_cnel: the nearest SFO
            community noise monitors, evidence=measured, daily CNEL in A-weighted dB at the
            monitor (not at the point, not live; see observed_on and distance_m).
            sfo_events: per SFO monitor, count / median / max of aircraft noise exceedance
            events in the last 365 days (evidence=measured, max_level_db in dBA, always
            quote observed_on; only events above that monitor's threshold are published, so
            it is not the typical level; the dataset has no declared license).
            cad_noise_calls: NOISE NUISANCE police dispatches per masked intersection, last
            30 days (evidence=proxy, count): complaints, not levels.
            noisecapture: ~100 m cells of crowdsourced, mostly uncalibrated phone
            measurements 2017-2025 (evidence=measured_crowdsourced, quality=
            measured_crowdsourced_uncalibrated; median_level_db is the median 5-minute
            LAeq; ODbL, attribute NoiseCapture / Noise-Planet; sparse, about 20 cells).
            include_references=true adds published Central SoMa Ldn dBA measurements
            (evidence=reference_measured, with source_url; 2014, area-specific).
            Never compare these dB values with the phone's relative dBFS levels.
            radius_m 50-2000. A layer that cannot be fetched is listed in `unavailable`.
            """
            if not (37.6 <= lat <= 37.85 and -122.55 <= lon <= -122.3):
                raise ToolError("lat/lon must be inside San Francisco.")
            if not 50 <= radius_m <= 2000:
                raise ToolError("Use radius_m between 50 and 2000.")
            chosen = list(dict.fromkeys(include)) if include else list(ALL_LAYERS)
            s = layers.around(lat, lon, radius_m, chosen)
            return SfLayersResult(
                lat=s.lat, lon=s.lon, radius_m=s.radius_m,
                layers={
                    name: [LayerPointOut(**p.__dict__) for p in pts] for name, pts in s.points.items()
                },
                unavailable=s.unavailable or None,
                references=[ReferenceOut(**r.__dict__) for r in REFERENCE_LEVELS] if include_references else None,
                reference_note=REFERENCE_NOTE if include_references else None,
                note=(
                    "Only sfo_cnel and sfo_events are sensor measurements; noisecapture is crowdsourced and "
                    "uncalibrated. Missing data is unknown, not quiet."
                ),
            )

    return mcp
