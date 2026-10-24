"""Shared sound layer: validation, release policy and candidate search over contributions.

Privacy and comparability rules (QUIET_COMPASS_IDEA.md, "Privacy and trust"):

- A contribution is a coarse summary: area, 5-minute UTC bucket, relative level, spread,
  peaks and capture profile. The server re-rounds coordinates to 3 decimals (~100 m) and
  re-floors the bucket, whatever the client sent.
- Ingestion rows are short-lived: rows older than `contribution_retention_hours` are
  purged on every write. Aggregates are computed on read, so they expire with them.
- An (area, time_bucket, capture_profile) aggregate is released only once it holds at
  least `release_min_contributions` distinct contributions. Smaller cohorts stay hidden.
- Different capture profiles are never merged into one number; quietness is ranked only
  within a profile cohort, because uncalibrated dBFS is not comparable across devices.
"""

from __future__ import annotations

import math
from collections import defaultdict
from collections.abc import Callable, Iterable, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from statistics import median
from typing import Literal

from .contracts import Goal
from .db import utc_now
from .settings import Settings
from .shared_contracts import (
    Area,
    AreaAggregate,
    AreaKind,
    ContributionResult,
    SharedContribution,
    SoundMapResponse,
)
from .shared_db import ContributionRow, SharedStore, StoredCohort

BUCKET = timedelta(minutes=5)
COORD_DECIMALS = 3
MIN_RMS_DBFS = -120.0
MAX_SPREAD_DB = 60.0
MIN_DURATION_S = 5.0
MAX_DURATION_S = 600.0
MAX_PER_COHORT = 3
FUTURE_SLACK = timedelta(minutes=5)
WALK_SPEED_MPS = 0.8
EARTH_RADIUS_M = 6_371_000.0
WALK_SOURCE = "estimate: straight-line distance at 0.8 m/s; no navigation source"
UNKNOWN_COVERAGE = (
    "Anywhere without a released aggregate is unknown, not quiet. Cohorts with fewer than "
    "{min_n} contribution(s) are withheld by policy, and levels are relative dBFS that are "
    "only comparable within one capture_profile."
)


def floor_bucket(value: datetime) -> datetime:
    """Floor a timestamp to the start of its 5-minute UTC bucket."""
    value = value.astimezone(UTC).replace(second=0, microsecond=0)
    return value - timedelta(minutes=value.minute % 5)


def round_coord(value: float) -> float:
    return round(value, COORD_DECIMALS)


def cell_id(lat: float, lon: float) -> str:
    return f"cell:{lat:.{COORD_DECIMALS}f},{lon:.{COORD_DECIMALS}f}"


def distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in metres (haversine)."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(h))


def walk_minutes(meters: float) -> float:
    return meters / WALK_SPEED_MPS / 60


def implausible(c: SharedContribution) -> str | None:
    """Reason a contribution is physically implausible, or None."""
    m = c.measurement
    if m.rms_dbfs < MIN_RMS_DBFS:
        return f"rms_dbfs {m.rms_dbfs} is below {MIN_RMS_DBFS} dBFS"
    if m.frame_level_spread_db > MAX_SPREAD_DB:
        return f"frame_level_spread_db {m.frame_level_spread_db} exceeds {MAX_SPREAD_DB} dB"
    if not MIN_DURATION_S <= c.duration_seconds <= MAX_DURATION_S:
        return f"duration_seconds must be between {MIN_DURATION_S:.0f} and {MAX_DURATION_S:.0f}"
    return None


def _source_label(sources: set[str]) -> Literal["device", "simulated", "mixed"]:
    if sources == {"device"}:
        return "device"
    if sources == {"simulated"}:
        return "simulated"
    return "mixed"


def _coverage(area: Area, n: int, has_synthetic: bool) -> str:
    unit = "~100 m outdoor cell" if area.kind == "outdoor_cell" else "designated indoor zone"
    note = f"{n} contribution(s) from one capture profile in one 5-minute bucket; {unit}."
    return note + (" Includes simulated data, not real measurements." if has_synthetic else "")


# --- candidate search ---------------------------------------------------------------------

GOAL_WEIGHTS: dict[str, tuple[float, float, float]] = {
    # (relative quietness, steadiness, few peaks); freshness is added separately.
    "rest": (0.50, 0.20, 0.15),
    "work": (0.45, 0.20, 0.20),
    "talk": (0.30, 0.30, 0.25),
}
FRESHNESS_WEIGHT = 0.15
FRESHNESS_TAU_MIN = 15.0
WALK_PENALTY = 0.05
MAX_CANDIDATES = 5


def _ramp(value: float, ok: float, zero: float) -> float:
    """1 at or below `ok`, 0 at or above `zero`, linear between."""
    return min(1.0, max(0.0, (zero - value) / (zero - ok)))


@dataclass(frozen=True)
class Candidate:
    aggregate: AreaAggregate
    supporting: tuple[AreaAggregate, ...]
    cohort_areas: int
    relative_quietness: float | None
    walk_minutes: float
    score: float


def relative_quietness(levels: dict[str, float]) -> dict[str, float | None]:
    """Per area: 1 = quietest in its cohort, 0 = loudest; None when nothing to compare."""
    if len(levels) < 2:
        return dict.fromkeys(levels)
    ordered = sorted(levels.values())
    span = len(ordered) - 1
    return {area: 1 - sum(v < level for v in ordered) / span for area, level in levels.items()}


def score(goal: Goal, quiet: float | None, agg: AreaAggregate, walk: float, max_walk: float) -> float:
    w_quiet, w_spread, w_peaks = GOAL_WEIGHTS[goal]
    peaks = agg.median_peaks_per_min
    peaks_fit = 0.5 if peaks is None else _ramp(peaks, 2.0, 12.0)
    fresh = math.exp(-agg.age_minutes / FRESHNESS_TAU_MIN)
    total = (
        w_quiet * (0.5 if quiet is None else quiet)
        + w_spread * _ramp(agg.median_frame_level_spread_db, 6.0, 18.0)
        + w_peaks * peaks_fit
        + FRESHNESS_WEIGHT * fresh
        - WALK_PENALTY * (walk / max_walk if max_walk else 0)
    )
    return round(min(1.0, max(0.0, total)), 3)


def rank_candidates(
    goal: Goal, aggregates: Sequence[AreaAggregate], max_walk: float
) -> list[Candidate]:
    """Latest aggregate per (area, profile), quietness ranked within each profile cohort."""
    groups: dict[tuple[str, str], list[AreaAggregate]] = defaultdict(list)
    for agg in sorted(aggregates, key=lambda a: a.time_bucket, reverse=True):
        groups[(agg.capture_profile, agg.area_id)].append(agg)
    by_profile: dict[str, dict[str, float]] = defaultdict(dict)
    for (profile, area), aggs in groups.items():
        by_profile[profile][area] = aggs[0].median_rms_dbfs
    quietness = {p: relative_quietness(levels) for p, levels in by_profile.items()}
    candidates = []
    for (profile, area), aggs in groups.items():
        latest = aggs[0]
        walk = walk_minutes(latest.distance_m)
        quiet = quietness[profile][area]
        candidates.append(
            Candidate(latest, tuple(aggs[:3]), len(by_profile[profile]), quiet, walk,
                      score(goal, quiet, latest, walk, max_walk))
        )
    return sorted(candidates, key=lambda c: (-c.score, c.walk_minutes))[:MAX_CANDIDATES]


def uncertainty(c: Candidate) -> str:
    agg = c.aggregate
    parts = [
        f"Based on {agg.n} contribution(s) measured {agg.age_minutes:.0f} min ago with capture profile "
        f"{agg.capture_profile!r}; levels are relative and uncalibrated, so conditions may have changed."
    ]
    if c.relative_quietness is None:
        parts.append("No other area in this cohort to compare against, so relative quietness is unknown.")
    else:
        parts.append(f"Quietness is ranked against {c.cohort_areas - 1} other area(s) in the same cohort only.")
    if agg.has_synthetic:
        parts.append("Includes simulated data, not a real reading.")
    if agg.clipped_count:
        parts.append(f"{agg.clipped_count} contribution(s) reported clipping.")
    return " ".join(parts)


# --- service ------------------------------------------------------------------------------


@dataclass(frozen=True)
class Placement:
    area: Area | None
    reason: str | None


class SharedLayer:
    """Shared-layer logic, independent of REST and MCP so both reuse it."""

    def __init__(
        self, store: SharedStore, settings: Settings, clock: Callable[[], datetime] = utc_now
    ) -> None:
        self.store = store
        self.settings = settings
        self.clock = clock

    @property
    def min_release(self) -> int:
        return self.settings.release_min_contributions

    @property
    def retention(self) -> timedelta:
        return timedelta(hours=self.settings.contribution_retention_hours)

    # -- areas -------------------------------------------------------------------------

    def upsert_area(self, area_id: str, name: str | None, lat: float, lon: float, kind: AreaKind) -> Area:
        return self.store.upsert_area(area_id, name, lat, lon, kind)

    def _place(self, c: SharedContribution) -> Placement:
        known = self.store.get_area(c.area_id)
        if known is not None:
            return Placement(known, None)
        if c.lat is None or c.lon is None:
            return Placement(None, f"unknown area_id {c.area_id!r} and no lat/lon to place it in an outdoor cell")
        lat, lon = round_coord(c.lat), round_coord(c.lon)
        area_id = cell_id(lat, lon)
        self.store.ensure_cell(area_id, c.area_name, lat, lon)
        return Placement(self.store.get_area(area_id), None)

    # -- submit ------------------------------------------------------------------------

    def _status(self, cohort: StoredCohort, clipped: bool, duplicate: bool = False) -> ContributionResult:
        released = cohort.size >= self.min_release
        notes = []
        if duplicate:
            notes.append("duplicate id; already stored")
        if not released:
            notes.append(
                f"stored; aggregate withheld until {self.min_release} contributions share this area, "
                "time bucket and capture profile"
            )
        if clipped:
            notes.append("clipping detected; stored and flagged")
        return ContributionResult(
            status="accepted" if released else "withheld",
            reason="; ".join(notes) or None,
            area_id=cohort.area_id,
            time_bucket=cohort.time_bucket,
        )

    def _reject(self, reason: str, area_id: str, bucket: datetime) -> ContributionResult:
        return ContributionResult(status="rejected", reason=reason, area_id=area_id, time_bucket=bucket)

    def _timing_problem(self, bucket: datetime, now: datetime) -> str | None:
        if bucket > now + FUTURE_SLACK:
            return "time_bucket is in the future"
        if bucket < now - self.retention:
            return f"time_bucket is older than the {self.settings.contribution_retention_hours:g} h retention window"
        return None

    def submit(self, c: SharedContribution) -> ContributionResult:
        now = self.clock()
        self.store.purge_before(now - self.retention)
        bucket = floor_bucket(c.time_bucket)
        existing = self.store.find_contribution(str(c.id))
        if existing is not None:
            return self._status(existing, c.quality.clipping_detected, duplicate=True)
        problem = implausible(c) or self._timing_problem(bucket, now)
        if problem:
            return self._reject(problem, c.area_id, bucket)
        placement = self._place(c)
        if placement.area is None:
            return self._reject(placement.reason or "unknown area", c.area_id, bucket)
        row = self._row(c, placement.area.id, bucket)
        cohort = self.store.insert_contribution(row, MAX_PER_COHORT)
        if cohort is None:
            reason = f"rate limit: at most {MAX_PER_COHORT} contributions per area, time bucket and capture profile"
            return self._reject(reason, placement.area.id, bucket)
        return self._status(cohort, c.quality.clipping_detected)

    @staticmethod
    def _row(c: SharedContribution, area_id: str, bucket: datetime) -> ContributionRow:
        m = c.measurement
        return ContributionRow(
            id=str(c.id), area_id=area_id, time_bucket=bucket, capture_profile=c.quality.capture_profile,
            source=c.source, rms_dbfs=m.rms_dbfs, spread_db=m.frame_level_spread_db,
            peaks_per_min=m.peaks_per_min, clipping=c.quality.clipping_detected, duration_s=c.duration_seconds,
        )

    # -- released aggregates -----------------------------------------------------------

    def _areas_near(self, lat: float, lon: float, radius_m: float) -> dict[str, tuple[Area, float]]:
        dlat = math.degrees(radius_m / EARTH_RADIUS_M)
        dlon = dlat / max(math.cos(math.radians(lat)), 1e-6)
        boxed = self.store.areas_in_box(lat - dlat, lat + dlat, lon - dlon, lon + dlon)
        near = ((a, distance_m(lat, lon, a.lat, a.lon)) for a in boxed)
        return {a.id: (a, d) for a, d in near if d <= radius_m}

    def aggregates(self, lat: float, lon: float, radius_m: float, since_minutes: float) -> list[AreaAggregate]:
        now = self.clock()
        areas = self._areas_near(lat, lon, radius_m)
        since = floor_bucket(now - timedelta(minutes=since_minutes))
        cohorts: dict[tuple[str, datetime, str], list[ContributionRow]] = defaultdict(list)
        for row in self.store.contributions_for(list(areas), since):
            cohorts[(row.area_id, row.time_bucket, row.capture_profile)].append(row)
        released = [
            self._aggregate(areas[area_id], rows, now)
            for (area_id, _, _), rows in cohorts.items()
            if len({r.id for r in rows}) >= self.min_release
        ]
        return sorted(released, key=lambda a: (a.distance_m, -a.time_bucket.timestamp(), a.capture_profile))

    @staticmethod
    def _aggregate(placed: tuple[Area, float], rows: Sequence[ContributionRow], now: datetime) -> AreaAggregate:
        area, dist = placed
        sources = {r.source for r in rows}
        peaks = [r.peaks_per_min for r in rows if r.peaks_per_min is not None]
        has_synthetic = "simulated" in sources
        bucket = rows[0].time_bucket
        return AreaAggregate(
            area_id=area.id, area_name=area.name, lat=area.lat, lon=area.lon, area_kind=area.kind,
            distance_m=round(dist, 1), time_bucket=bucket, capture_profile=rows[0].capture_profile,
            n=len(rows), measurement_kind="relative_uncalibrated",
            median_rms_dbfs=round(median(r.rms_dbfs for r in rows), 1),
            median_frame_level_spread_db=round(median(r.spread_db for r in rows), 1),
            median_peaks_per_min=round(median(peaks), 1) if peaks else None,
            clipped_count=sum(r.clipping for r in rows),
            age_minutes=round(max((now - bucket).total_seconds(), 0) / 60, 1),
            has_synthetic=has_synthetic, source=_source_label(sources),
            coverage=_coverage(area, len(rows), has_synthetic),
        )

    def sound_map(self, lat: float, lon: float, radius_m: int, since_minutes: int) -> SoundMapResponse:
        return SoundMapResponse(
            generated_at=self.clock(), lat=lat, lon=lon, radius_m=radius_m, since_minutes=since_minutes,
            release_min_contributions=self.min_release,
            aggregates=self.aggregates(lat, lon, radius_m, since_minutes),
            unknown_coverage=self.unknown_coverage(),
        )

    def unknown_coverage(self) -> str:
        return UNKNOWN_COVERAGE.format(min_n=self.min_release)

    def candidates(
        self, goal: Goal, lat: float, lon: float, max_walk_minutes: float, max_age_minutes: int
    ) -> list[Candidate]:
        radius = max_walk_minutes * 60 * WALK_SPEED_MPS
        return rank_candidates(goal, self.aggregates(lat, lon, radius, max_age_minutes), max_walk_minutes)


def has_synthetic(aggregates: Iterable[AreaAggregate]) -> bool:
    return any(a.has_synthetic for a in aggregates)
