"""Pydantic models for the shared sound layer (contracts/quiet-compass.schema.json).

Mirrors `SharedContribution`, `ContributionResult`, `Area`, `AreaAggregate` and the REST
bodies around them. Schema-level violations (wrong types, a positive dBFS level, unknown
fields) fail validation; plausibility limits that depend on policy (for example a level
below -120 dBFS) are checked by `shared_layer` and reported as a `rejected` result.
"""

from __future__ import annotations

from typing import Annotated, Literal
from uuid import UUID

from pydantic import Field, StringConstraints, model_validator

from .contracts import Contract, ContractVersion, Timestamp

AREA_ID_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9:._,-]{0,119}$"

AreaId = Annotated[str, StringConstraints(pattern=AREA_ID_PATTERN)]
AreaKind = Literal["indoor_zone", "outdoor_cell"]
ContributionSource = Literal["device", "simulated"]
ContributionStatus = Literal["accepted", "withheld", "rejected"]
Latitude = Annotated[float, Field(ge=-90, le=90)]
Longitude = Annotated[float, Field(ge=-180, le=180)]


class SharedMeasurement(Contract):
    kind: Literal["relative_uncalibrated"]
    rms_dbfs: float = Field(le=0)
    frame_level_spread_db: float = Field(ge=0)
    peaks_per_min: float | None = Field(default=None, ge=0)
    calibrated: Literal[False]


class ContributionQuality(Contract):
    capture_profile: str = Field(min_length=1, max_length=80)
    clipping_detected: bool


class SharedContribution(Contract):
    """One consented acoustic summary. Carries no audio, route, identity or preference."""

    id: UUID
    schema_version: Literal["0.1"]
    area_id: AreaId
    area_name: str | None = Field(default=None, max_length=80)
    lat: Latitude | None = None
    lon: Longitude | None = None
    time_bucket: Timestamp
    duration_seconds: float = Field(gt=0)
    measurement: SharedMeasurement
    quality: ContributionQuality
    source: ContributionSource

    @model_validator(mode="after")
    def _coordinates_together(self) -> SharedContribution:
        if (self.lat is None) != (self.lon is None):
            raise ValueError("lat and lon must be given together or both omitted")
        return self


class ContributionUpload(Contract):
    contract_version: ContractVersion
    contribution: SharedContribution


class ContributionResult(Contract):
    status: ContributionStatus
    reason: str | None
    area_id: str
    time_bucket: Timestamp


class AreaUpsert(Contract):
    name: str | None = Field(default=None, max_length=80)
    lat: Latitude
    lon: Longitude
    kind: AreaKind


class Area(Contract):
    id: AreaId
    name: str | None
    lat: Latitude
    lon: Longitude
    kind: AreaKind
    created_at: Timestamp


class AreaAggregate(Contract):
    """A released (area, time_bucket, capture_profile) cohort summary."""

    area_id: str
    area_name: str | None
    lat: float
    lon: float
    area_kind: AreaKind
    distance_m: float = Field(ge=0)
    time_bucket: Timestamp
    capture_profile: str
    n: int = Field(ge=1)
    measurement_kind: Literal["relative_uncalibrated"]
    median_rms_dbfs: float
    median_frame_level_spread_db: float
    median_peaks_per_min: float | None
    clipped_count: int = Field(ge=0)
    age_minutes: float = Field(ge=0)
    has_synthetic: bool
    source: Literal["device", "simulated", "mixed"]
    coverage: str


class SoundMapResponse(Contract):
    generated_at: Timestamp
    lat: float
    lon: float
    radius_m: int
    since_minutes: int
    release_min_contributions: int
    aggregates: list[AreaAggregate]
    unknown_coverage: str
