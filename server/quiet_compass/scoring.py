"""Pure scoring for quiet_find_space. No I/O; every constant lives in `ScoringConfig`.

Pipeline for one request:

1. Filter places: required tags (`needs`), at least one observation, and the time budget
   (walk there and back at 0.8 m/s plus the stay must fit before `return_by`). Every
   constraint a place fails is recorded so `relax` can name the one worth loosening.
2. Personal band per goal: the quietest third of the session's levels by default, or the
   median latest level of places rated "good" for that goal ±3 dB once there are at least
   two such ratings. Each "bad" rating shrinks the band by 1 dB on the edge nearest that
   place's level (the band never gets narrower than `min_band_width_db`).
3. Fit (0..1) = min(level fit, spread fit, peaks fit), times (1 − 0.5·speech_share) for
   rest and work. F_measured uses the latest observation and is capped at 0.2 after a
   "chaotic" rating in the last 30 min; F_prior uses the place's median observation
   (0.5 when the place has fewer than two observations).
4. S = w·F_measured + (1 − w)·F_prior − λ·d with w = exp(−age/τ) and d in 10 m units,
   clamped to [0, 1]. Results with S below `min_score` are a no-fit.

Levels are relative dBFS from one device profile. Callers must only pass observations
from a single session (one session = one device profile), so levels stay comparable.
"""

from __future__ import annotations

import itertools
import math
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import datetime
from statistics import median
from typing import Literal

Goal = Literal["talk", "rest", "work"]
Need = Literal["seating", "step_free"]
Constraint = Literal["time", "seating", "step_free", "unmeasured"]
Relax = Literal["time", "seating", "step_free", "measure_more"]
DistanceSource = Literal["path", "straight_line", "assumed"]

RELAX_PRIORITY: tuple[Relax, ...] = ("time", "seating", "step_free")


@dataclass(frozen=True)
class ScoringConfig:
    walk_speed_mps: float = 0.8
    assumed_distance_m: float = 20.0
    default_band_quantile: float = 1 / 3
    min_good_feedback: int = 2
    good_band_half_width_db: float = 3.0
    bad_feedback_shift_db: float = 1.0
    min_band_width_db: float = 1.0
    level_falloff_db: float = 10.0
    spread_ok_db: float = 6.0
    spread_zero_db: float = 18.0
    peaks_ok_per_min: float = 2.0
    peaks_zero_per_min: float = 12.0
    speech_weight: float = 0.5
    speech_goals: frozenset[str] = frozenset({"work", "rest"})
    chaotic_window_min: float = 30.0
    chaotic_cap: float = 0.2
    min_prior_observations: int = 2
    prior_default: float = 0.5
    freshness_tau_min: float = 15.0
    distance_unit_m: float = 10.0
    distance_lambda: float = 0.1
    min_score: float = 0.4
    max_results: int = 3


DEFAULT_CONFIG = ScoringConfig()


@dataclass(frozen=True)
class Features:
    level_db: float
    spread_db: float
    peaks_per_min: float
    speech_share: float | None = None


@dataclass(frozen=True)
class Observed:
    t: datetime
    features: Features


@dataclass(frozen=True)
class PlaceInput:
    place_id: str
    label: str
    tags: frozenset[str]
    observations: tuple[Observed, ...]
    distance_m: float
    distance_source: DistanceSource

    @property
    def latest(self) -> Observed | None:
        return max(self.observations, key=lambda o: o.t, default=None)


@dataclass(frozen=True)
class FeedbackInput:
    place_id: str
    goal: Goal
    verdict: Literal["good", "ok", "bad"]
    feel: Literal["calm", "neutral", "chaotic"] | None
    t: datetime


@dataclass(frozen=True)
class Band:
    lo: float
    hi: float
    source: Literal["default", "feedback"]

    def contains(self, level: float) -> bool:
        return self.lo <= level <= self.hi


@dataclass(frozen=True)
class SpaceRequest:
    goal: Goal
    duration_minutes: float
    return_by: datetime
    now: datetime
    needs: frozenset[str] = frozenset()

    @property
    def minutes_available(self) -> float:
        return (self.return_by - self.now).total_seconds() / 60


@dataclass(frozen=True)
class ScoreTerms:
    score: float
    f_measured: float
    f_prior: float
    freshness_w: float
    distance_penalty: float
    age_min: float
    chaotic_capped: bool


@dataclass(frozen=True)
class Candidate:
    place: PlaceInput
    terms: ScoreTerms
    walk_minutes: float
    blocked_by: tuple[Constraint, ...] = ()


@dataclass(frozen=True)
class SpaceOutcome:
    results: tuple[Candidate, ...]
    band: Band | None
    minutes_available: float
    closest: Candidate | None = None
    relax: Relax | None = None
    eliminated: Mapping[str, tuple[Constraint, ...]] = field(default_factory=dict)

    @property
    def no_fit(self) -> bool:
        return not self.results


# --- small numeric helpers -------------------------------------------------------------


def percentile(values: Sequence[float], q: float) -> float:
    """Linear-interpolated percentile (q in 0..1), matching numpy's default method."""
    if not values:
        raise ValueError("percentile of an empty sequence")
    ordered = sorted(values)
    pos = (len(ordered) - 1) * min(max(q, 0.0), 1.0)
    low = math.floor(pos)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (pos - low)


def ramp(value: float, ok: float, zero: float) -> float:
    """1 at or below `ok`, falling linearly to 0 at `zero`."""
    if value <= ok:
        return 1.0
    if value >= zero:
        return 0.0
    return 1.0 - (value - ok) / (zero - ok)


def freshness(age_min: float, cfg: ScoringConfig = DEFAULT_CONFIG) -> float:
    return math.exp(-max(age_min, 0.0) / cfg.freshness_tau_min)


def walk_minutes(distance_m: float, cfg: ScoringConfig = DEFAULT_CONFIG) -> float:
    return distance_m / cfg.walk_speed_mps / 60


def path_length(points: Sequence[tuple[float, float]]) -> float:
    """Length of a polyline of (x, z) points in metres."""
    return sum(math.dist(a, b) for a, b in itertools.pairwise(points))


def walked_distance(
    path: Sequence[tuple[float, float]], from_index: int, to_index: int
) -> float:
    """Distance along the recorded path between two crumb indices (either order)."""
    lo, hi = sorted((from_index, to_index))
    return path_length(path[lo : hi + 1])


def nearest_index(path: Sequence[tuple[float, float]], point: tuple[float, float]) -> int:
    return min(range(len(path)), key=lambda i: math.dist(path[i], point))


def estimate_distance(
    path: Sequence[tuple[float, float]],
    place_index: int | None,
    place_position: tuple[float, float] | None,
    user_position: tuple[float, float] | None,
    cfg: ScoringConfig = DEFAULT_CONFIG,
    snap_radius_m: float = 3.0,
) -> tuple[float, DistanceSource]:
    """Distance from the user to a place, preferring the walked path.

    `path` is the session's crumb positions in seq order; the user is at its last point.
    A place without a crumb is snapped to the nearest crumb within `snap_radius_m`.
    Falls back to the straight line between positions, then to an assumed distance
    (zone-only places, mode B).
    """
    if path and place_index is None and place_position is not None:
        candidate = nearest_index(path, place_position)
        if math.dist(path[candidate], place_position) <= snap_radius_m:
            place_index = candidate
    if path and place_index is not None:
        return walked_distance(path, place_index, len(path) - 1), "path"
    if place_position is not None and user_position is not None:
        return math.dist(place_position, user_position), "straight_line"
    return cfg.assumed_distance_m, "assumed"


# --- band and fits ----------------------------------------------------------------------


def default_band(levels: Sequence[float], cfg: ScoringConfig = DEFAULT_CONFIG) -> Band | None:
    if not levels:
        return None
    return Band(min(levels), percentile(levels, cfg.default_band_quantile), "default")


def _shrink_toward_center(band: Band, level: float, cfg: ScoringConfig) -> Band:
    room = (band.hi - band.lo) - cfg.min_band_width_db
    step = min(cfg.bad_feedback_shift_db, max(room, 0.0))
    if step <= 0:
        return band
    if abs(level - band.lo) <= abs(level - band.hi):
        return Band(band.lo + step, band.hi, band.source)
    return Band(band.lo, band.hi - step, band.source)


def personal_band(
    goal: Goal,
    session_levels: Sequence[float],
    feedback: Iterable[FeedbackInput],
    latest_levels: Mapping[str, float],
    cfg: ScoringConfig = DEFAULT_CONFIG,
) -> Band | None:
    """The level band the user is comfortable with for `goal` (see module docstring)."""
    rows = [f for f in feedback if f.goal == goal]
    good = [f for f in rows if f.verdict == "good"]
    good_levels = [latest_levels[p] for p in {f.place_id for f in good} if p in latest_levels]
    band: Band | None
    if len(good) >= cfg.min_good_feedback and good_levels:
        center = median(good_levels)
        half = cfg.good_band_half_width_db
        band = Band(center - half, center + half, "feedback")
    else:
        band = default_band(session_levels, cfg)
    if band is None:
        return None
    for row in rows:
        if row.verdict == "bad" and row.place_id in latest_levels:
            band = _shrink_toward_center(band, latest_levels[row.place_id], cfg)
    return band


def level_fit(level: float, band: Band | None, cfg: ScoringConfig = DEFAULT_CONFIG) -> float:
    if band is None:
        return cfg.prior_default
    outside = max(band.lo - level, level - band.hi, 0.0)
    return ramp(outside, 0.0, cfg.level_falloff_db)


def feature_fit(
    features: Features, band: Band | None, goal: Goal, cfg: ScoringConfig = DEFAULT_CONFIG
) -> float:
    fit = min(
        level_fit(features.level_db, band, cfg),
        ramp(features.spread_db, cfg.spread_ok_db, cfg.spread_zero_db),
        ramp(features.peaks_per_min, cfg.peaks_ok_per_min, cfg.peaks_zero_per_min),
    )
    if goal in cfg.speech_goals and features.speech_share is not None:
        fit *= 1 - cfg.speech_weight * features.speech_share
    return fit


def median_features(observations: Sequence[Observed]) -> Features:
    speech = [o.features.speech_share for o in observations if o.features.speech_share is not None]
    return Features(
        level_db=median(o.features.level_db for o in observations),
        spread_db=median(o.features.spread_db for o in observations),
        peaks_per_min=median(o.features.peaks_per_min for o in observations),
        speech_share=median(speech) if speech else None,
    )


def recently_chaotic(
    place_id: str, feedback: Iterable[FeedbackInput], now: datetime, cfg: ScoringConfig
) -> bool:
    window_s = cfg.chaotic_window_min * 60
    return any(
        f.place_id == place_id
        and f.feel == "chaotic"
        and 0 <= (now - f.t).total_seconds() <= window_s
        for f in feedback
    )


# --- scoring ----------------------------------------------------------------------------


def score_place(
    place: PlaceInput,
    band: Band | None,
    goal: Goal,
    feedback: Sequence[FeedbackInput],
    now: datetime,
    cfg: ScoringConfig = DEFAULT_CONFIG,
) -> ScoreTerms:
    latest = place.latest
    if latest is None:
        raise ValueError(f"place {place.place_id} has no observations")
    f_measured = feature_fit(latest.features, band, goal, cfg)
    capped = recently_chaotic(place.place_id, feedback, now, cfg)
    if capped:
        f_measured = min(f_measured, cfg.chaotic_cap)
    if len(place.observations) >= cfg.min_prior_observations:
        f_prior = feature_fit(median_features(place.observations), band, goal, cfg)
    else:
        f_prior = cfg.prior_default
    age_min = max((now - latest.t).total_seconds() / 60, 0.0)
    w = freshness(age_min, cfg)
    penalty = cfg.distance_lambda * place.distance_m / cfg.distance_unit_m
    raw = w * f_measured + (1 - w) * f_prior - penalty
    return ScoreTerms(
        score=min(max(raw, 0.0), 1.0),
        f_measured=f_measured,
        f_prior=f_prior,
        freshness_w=w,
        distance_penalty=penalty,
        age_min=age_min,
        chaotic_capped=capped,
    )


def blocking_constraints(
    place: PlaceInput, request: SpaceRequest, cfg: ScoringConfig = DEFAULT_CONFIG
) -> tuple[Constraint, ...]:
    """Every constraint that rules the place out, in a stable order."""
    blocked: list[Constraint] = []
    if not place.observations:
        blocked.append("unmeasured")
    needed_minutes = 2 * walk_minutes(place.distance_m, cfg) + request.duration_minutes
    if needed_minutes > request.minutes_available:
        blocked.append("time")
    for need in ("seating", "step_free"):
        if need in request.needs and need not in place.tags:
            blocked.append(need)  # type: ignore[arg-type]
    return tuple(blocked)


def choose_relax(
    blocked: Sequence[Candidate], cfg: ScoringConfig = DEFAULT_CONFIG
) -> Relax:
    """The constraint whose removal would let the most otherwise-good places through."""
    good = [c for c in blocked if c.terms.score >= cfg.min_score]

    def key(constraint: Relax) -> tuple[int, int, int]:
        single = sum(1 for c in good if c.blocked_by == (constraint,))
        anywhere = sum(1 for c in good if constraint in c.blocked_by)
        return single, anywhere, -RELAX_PRIORITY.index(constraint)

    best = max(RELAX_PRIORITY, key=key)
    return best if key(best)[1] > 0 else "measure_more"


def find_space(
    request: SpaceRequest,
    places: Sequence[PlaceInput],
    session_levels: Sequence[float],
    feedback: Sequence[FeedbackInput],
    cfg: ScoringConfig = DEFAULT_CONFIG,
) -> SpaceOutcome:
    latest_levels = {
        p.place_id: latest.features.level_db for p in places if (latest := p.latest) is not None
    }
    band = personal_band(request.goal, session_levels, feedback, latest_levels, cfg)
    eliminated: dict[str, tuple[Constraint, ...]] = {}
    scored: list[Candidate] = []
    for place in places:
        blocked = blocking_constraints(place, request, cfg)
        if blocked:
            eliminated[place.place_id] = blocked
        if "unmeasured" in blocked:
            continue
        terms = score_place(place, band, request.goal, feedback, request.now, cfg)
        scored.append(Candidate(place, terms, walk_minutes(place.distance_m, cfg), blocked))

    def rank(candidate: Candidate) -> tuple[float, float]:
        return -candidate.terms.score, candidate.place.distance_m

    scored.sort(key=rank)
    eligible = [c for c in scored if not c.blocked_by]
    results = tuple(c for c in eligible if c.terms.score >= cfg.min_score)[: cfg.max_results]
    if results:
        return SpaceOutcome(results, band, request.minutes_available, eliminated=eliminated)
    closest = eligible[0] if eligible else (scored[0] if scored else None)
    return SpaceOutcome(
        (),
        band,
        request.minutes_available,
        closest=closest,
        relax=choose_relax([c for c in scored if c.blocked_by], cfg),
        eliminated=eliminated,
    )
