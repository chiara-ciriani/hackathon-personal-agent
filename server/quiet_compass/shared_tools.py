"""MCP tools for the shared sound layer: query_sound_map, find_suitable_places and
submit_observation. Names match the contract shown by the web map's MCP panel.

These tools see only released aggregates (and accept consented summaries); they never
read the personal session tables used by the quiet_* tools.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Literal
from uuid import UUID

from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError
from mcp_types import ToolAnnotations
from pydantic import ValidationError

from .contracts import Goal, format_utc
from .mcp_server import Lean
from .shared_contracts import (
    AreaId,
    ContributionQuality,
    ContributionResult,
    ContributionSource,
    SharedContribution,
    SharedMeasurement,
    SoundMapResponse,
)
from .shared_layer import WALK_SOURCE, Candidate, SharedLayer, has_synthetic, uncertainty

SYNTHETIC_NOTE = "Some results include synthetic demo data (source synthetic_demo); say so to the user."


class Supporting(Lean):
    time_bucket: str
    age_minutes: float
    n: int
    median_rms_dbfs: float
    median_frame_level_spread_db: float
    median_peaks_per_min: float | None = None
    source: str


class Walk(Lean):
    distance_m: float
    minutes: float
    source: str


class SuitablePlace(Lean):
    area_id: str
    area_name: str | None = None
    area_kind: str
    lat: float
    lon: float
    capture_profile: str
    score: float
    relative_quietness: float | None = None
    age_minutes: float
    walk: Walk
    fits_return_by: bool | None = None
    supporting_observations: list[Supporting]
    uncertainty: str


class SuitablePlaces(Lean):
    no_fit: bool
    reason: str | None = None
    goal: str
    candidates: list[SuitablePlace] | None = None
    note: str


def _supporting(c: Candidate) -> list[Supporting]:
    return [
        Supporting(
            time_bucket=format_utc(a.time_bucket), age_minutes=a.age_minutes, n=a.n,
            median_rms_dbfs=a.median_rms_dbfs, median_frame_level_spread_db=a.median_frame_level_spread_db,
            median_peaks_per_min=a.median_peaks_per_min, source=a.source,
        )
        for a in c.supporting
    ]


def _fits(c: Candidate, now: datetime, return_by: datetime | None) -> bool | None:
    if return_by is None:
        return None
    return 2 * c.walk_minutes <= (return_by - now).total_seconds() / 60


def _place(c: Candidate, now: datetime, return_by: datetime | None) -> SuitablePlace:
    a = c.aggregate
    return SuitablePlace(
        area_id=a.area_id, area_name=a.area_name, area_kind=a.area_kind, lat=a.lat, lon=a.lon,
        capture_profile=a.capture_profile, score=c.score,
        relative_quietness=None if c.relative_quietness is None else round(c.relative_quietness, 2),
        age_minutes=a.age_minutes,
        walk=Walk(distance_m=a.distance_m, minutes=round(c.walk_minutes, 1), source=WALK_SOURCE),
        fits_return_by=_fits(c, now, return_by), supporting_observations=_supporting(c),
        uncertainty=uncertainty(c),
    )


def find_suitable_places(
    layer: SharedLayer, goal: Goal, lat: float, lon: float, max_walk_minutes: int,
    return_by: datetime | None, max_age_minutes: int,
) -> SuitablePlaces:
    now = layer.clock()
    if return_by is not None:
        return_by = return_by if return_by.tzinfo else return_by.replace(tzinfo=UTC)
        if return_by <= now:
            raise ToolError(f"return_by is not in the future (now is {format_utc(now)}).")
    ranked = layer.candidates(goal, lat, lon, max_walk_minutes, max_age_minutes)
    places = [_place(c, now, return_by) for c in ranked]
    fitting = [p for p in places if p.fits_return_by is not False]
    note = "Ranking is a heuristic within one capture profile, not a promise of comfort or silence."
    if has_synthetic(c.aggregate for c in ranked):
        note += " " + SYNTHETIC_NOTE
    if not fitting:
        reason = (
            "No released aggregate within the walk limit and age limit; that area is unknown, not quiet."
            if not places else "Released areas exist, but none allows a round trip before return_by."
        )
        return SuitablePlaces(no_fit=True, reason=reason, goal=goal, note=layer.unknown_coverage())
    return SuitablePlaces(no_fit=False, goal=goal, candidates=fitting, note=note)


def _contribution(**fields: object) -> SharedContribution:
    try:
        return SharedContribution.model_validate(fields)
    except ValidationError as exc:
        details = "; ".join(f"{'.'.join(map(str, e['loc']))}: {e['msg']}" for e in exc.errors(include_url=False))
        raise ToolError(f"Invalid contribution: {details}") from exc


def register_shared_tools(mcp: MCPServer, layer: SharedLayer) -> None:
    """Add the three shared-layer tools to an MCP server."""

    @mcp.tool(annotations=ToolAnnotations(title="Shared sound map", readOnlyHint=True, openWorldHint=False))
    def query_sound_map(lat: float, lon: float, radius_m: int = 500, since_minutes: int = 60) -> SoundMapResponse:
        """Released shared sound aggregates near a point (radius_m 50-5000, since_minutes 5-1440).

        Each aggregate is one (area, 5-minute time bucket, capture_profile) cohort with n
        contributions: median relative level (rms_dbfs, uncalibrated, never dBA), spread,
        peaks per minute, age_minutes, source (device, synthetic_demo or mixed), coverage
        and clipping count. Only compare levels that share a capture_profile. Areas not
        listed are unknown, not quiet; sparse cohorts are withheld by policy.
        """
        if not (50 <= radius_m <= 5000 and 5 <= since_minutes <= 1440):
            raise ToolError("Use radius_m between 50 and 5000 and since_minutes between 5 and 1440.")
        return layer.sound_map(lat, lon, radius_m, since_minutes)

    @mcp.tool(
        name="find_suitable_places",
        annotations=ToolAnnotations(title="Find suitable places", readOnlyHint=True, openWorldHint=False),
    )
    def find_suitable_places_tool(
        goal: Goal,
        lat: float,
        lon: float,
        max_walk_minutes: int = 10,
        return_by: datetime | None = None,
        max_age_minutes: int = 30,
    ) -> SuitablePlaces:
        """Candidate areas from the shared map for a goal (talk, rest or work) near lat/lon.

        Ranked by relative quietness within each capture_profile cohort, low spread and
        peaks, and freshness. Each candidate has supporting observations, age, an
        uncertainty sentence and a walk estimate from straight-line distance at 0.8 m/s
        (no navigation). With return_by (ISO 8601 with offset), candidates whose round
        trip does not fit are dropped. Returns no_fit with a reason when nothing
        qualifies. Apply the user's personal preferences yourself; do not send them here.
        """
        if not (1 <= max_walk_minutes <= 60 and 5 <= max_age_minutes <= 1440):
            raise ToolError("Use max_walk_minutes between 1 and 60 and max_age_minutes between 5 and 1440.")
        return find_suitable_places(layer, goal, lat, lon, max_walk_minutes, return_by, max_age_minutes)

    @mcp.tool(
        annotations=ToolAnnotations(
            title="Contribute a sound summary", readOnlyHint=False, destructiveHint=False,
            idempotentHint=True, openWorldHint=False,
        )
    )
    def submit_observation(
        id: UUID,
        area_id: AreaId,
        time_bucket: datetime,
        duration_seconds: float,
        measurement: SharedMeasurement,
        quality: ContributionQuality,
        source: ContributionSource,
        schema_version: Literal["0.1"] = "0.1",
        area_name: str | None = None,
        lat: float | None = None,
        lon: float | None = None,
    ) -> ContributionResult:
        """Contribute one consented acoustic summary (SharedContribution) to the shared map.

        Only submit a summary the user agreed to share: area, time bucket, relative level,
        spread, peaks, capture profile and quality. Never include preferences, routes,
        health, calendar data, audio or transcripts. The server rounds lat/lon to ~100 m
        and floors time to 5 minutes. Result status: accepted (its aggregate is released),
        withheld (stored, waiting for more contributions) or rejected (with reason).
        Resending the same id is harmless. Use source synthetic_demo for anything not
        measured by a real device.
        """
        contribution = _contribution(
            id=id, schema_version=schema_version, area_id=area_id, area_name=area_name, lat=lat, lon=lon,
            time_bucket=time_bucket, duration_seconds=duration_seconds,
            measurement=measurement.model_dump(), quality=quality.model_dump(), source=source,
        )
        return layer.submit(contribution)
