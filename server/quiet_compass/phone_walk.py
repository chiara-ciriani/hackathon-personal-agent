"""Bounded native acoustic summaries. Private to the paired agent, never shared map currency."""
from __future__ import annotations

import math
from dataclasses import asdict
from datetime import datetime
from itertools import pairwise
from statistics import median
from typing import Literal
from uuid import UUID

from pydantic import AwareDatetime, Field

from .contracts import Contract
from .sound_field import Sample, build_field


class NativeConsent(Contract):
    microphone_consent: bool
    spatial_consent: bool
    location_consent: bool = False


class ApproximateLocation(Contract):
    lat: float = Field(ge=-90, le=90, allow_inf_nan=False)
    lon: float = Field(ge=-180, le=180, allow_inf_nan=False)


class WalkSample(Contract):
    t: float = Field(ge=0, le=180, allow_inf_nan=False)
    x: float = Field(ge=-1000, le=1000, allow_inf_nan=False)
    z: float = Field(ge=-1000, le=1000, allow_inf_nan=False)
    level_dbfs: float = Field(ge=-120, le=0, allow_inf_nan=False)
    tracking: Literal["normal"]


class Direction(Contract):
    bearing_degrees: float = Field(ge=0, lt=360, allow_inf_nan=False)
    confidence: float = Field(ge=0.5, le=1, allow_inf_nan=False)


class WalkCapture(Contract):
    started_at: AwareDatetime
    capture_profile: str = Field(pattern=r"^ios-walk-v1:[A-Za-z0-9:._-]{1,100}$")
    samples: list[WalkSample] = Field(min_length=3, max_length=90)
    clipping_detected: Literal[False]
    dominant_sound: Direction | None = None
    location: ApproximateLocation | None = None


class WalkResult(Contract):
    request_id: UUID
    walk: WalkCapture | None = None
    error: str | None = Field(default=None, max_length=200)


def analyze_walk(walk: WalkCapture, requested_at: datetime, now: datetime, duration: int) -> dict:
    """Validate one capture window and reuse the app/server field, without merging devices."""
    age = (now - walk.started_at).total_seconds()
    if not -2 <= (walk.started_at - requested_at).total_seconds() <= 45 or not duration - 5 <= age <= duration + 60:
        raise ValueError("The walk must belong to this recent request")
    times = [s.t for s in walk.samples]
    if any(b <= a for a, b in pairwise(times)) or times[-1] > duration + 1 or times[-1] > age + 2:
        raise ValueError("Invalid sample timing")
    if times[-1] - times[0] < duration / 2 or age - times[-1] > 8:
        raise ValueError("Not enough recent tracked sound samples; request another walk")
    samples = [Sample(s.x, s.z, s.level_dbfs, max(0, age - s.t) / 60) for s in walk.samples]
    last = walk.samples[-1]
    field = build_field(samples, user=(last.x, last.z))
    levels = sorted(s.level_dbfs for s in walk.samples)
    energy = sum(10 ** (value / 10) for value in levels) / len(levels)
    return {
        "sample_count": len(samples), "duration_seconds": duration,
        "capture_profile": walk.capture_profile, "verification": "phone_reported_summary",
        "analysis": {"mean_dbfs": round(10 * math.log10(energy), 2), "median_dbfs": median(levels),
                     "min_dbfs": levels[0], "max_dbfs": levels[-1],
                     "variation_db": round(levels[round((len(levels)-1)*.9)] - levels[round((len(levels)-1)*.1)], 2)},
        "current_level_dbfs": last.level_dbfs, "user": {"x": last.x, "z": last.z},
        "quiet_spots": [{"spot_index": i, **asdict(spot)} for i, spot in enumerate(field.quiet_spots)],
        "dominant_sound": walk.dominant_sound.model_dump() if walk.dominant_sound else None,
        "location": ({"lat": round(walk.location.lat, 3), "lon": round(walk.location.lon, 3),
                      "precision": "approximately_100m"} if walk.location else None),
        "note": "Private ARKit room map; relative uncalibrated dBFS, not dBA. Unknown cells are not quiet. "
                "Distances/directions are straight-line, not obstacle-free routes. "
                "Any sound bearing is experimental FOA, not verified source identification. "
                "No audio, images, speech transcript or shared-query access receipt.",
    }
