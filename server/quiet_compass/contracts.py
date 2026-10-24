"""Pydantic models mirroring contracts/quiet-compass.schema.json (v1).

Written by hand; keep in step with the schema and the Swift models. Every model forbids
unknown fields, ids are UUIDs (serialized lowercase), and timestamps must carry a time
zone; they are normalized to UTC and serialized as ISO 8601 with a `Z` suffix.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AfterValidator, AwareDatetime, BaseModel, ConfigDict, Field, PlainSerializer


def to_utc(value: datetime) -> datetime:
    return value.astimezone(UTC)


def format_utc(value: datetime) -> str:
    """ISO 8601 UTC with millisecond precision and a Z suffix."""
    return value.astimezone(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _unique(values: list[str]) -> list[str]:
    if len(set(values)) != len(values):
        raise ValueError("tags must be unique")
    return values


Timestamp = Annotated[
    AwareDatetime,
    AfterValidator(to_utc),
    PlainSerializer(format_utc, return_type=str, when_used="json"),
]

ContractVersion = Literal[1]
CaptureMode = Literal["A", "B", "C"]
TrackingState = Literal["normal", "limited", "not_available", "none"]
Goal = Literal["talk", "rest", "work"]
Verdict = Literal["good", "ok", "bad"]
Feel = Literal["calm", "neutral", "chaotic"]
PlaceTag = Literal["seating", "step_free", "authorized"]
PlaceSource = Literal["user", "organizer", "seed"]
GuidanceStatus = Literal["active", "arrived", "cancelled"]


class Contract(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Position(Contract):
    x: float
    z: float


class DeviceProfile(Contract):
    model: str
    os_version: str
    capture_mode: CaptureMode
    audio_session_mode: str
    sample_rate_hz: int
    app_version: str


class Session(Contract):
    id: UUID
    name: str | None = None
    started_at: Timestamp
    device_profile: DeviceProfile


class SoundClass(Contract):
    label: str
    confidence: float = Field(ge=0, le=1)


class DirectionEstimate(Contract):
    frame: Literal["world", "device"]
    azimuth_deg: float = Field(ge=-180, le=180)
    elevation_deg: float | None = Field(default=None, ge=-90, le=90)
    sector: int = Field(ge=0, le=7)
    confidence: float = Field(ge=0, le=1)


class Observation(Contract):
    id: UUID
    session_id: UUID
    t: Timestamp
    duration_s: float = Field(gt=0)
    position: Position | None = None
    crumb_id: UUID | None = None
    place_id: UUID | None = None
    level_dbfs_rel: float = Field(le=0)
    level_aw_dbfs_rel: float | None = Field(default=None, le=0)
    spread_db: float = Field(ge=0)
    peaks_per_min: float = Field(ge=0)
    bands_db: list[float] | None = Field(default=None, min_length=6, max_length=6)
    speech_share: float | None = Field(default=None, ge=0, le=1)
    classes: list[SoundClass] = Field(default_factory=list, max_length=3)
    doa: DirectionEstimate | None = None
    tracking: TrackingState


class Crumb(Contract):
    id: UUID
    session_id: UUID
    seq: int = Field(ge=0)
    segment: int = Field(default=0, ge=0)
    position: Position
    heading_rad: float
    t: Timestamp
    tracking: TrackingState


class Place(Contract):
    id: UUID
    session_id: UUID
    label: str = Field(min_length=1, max_length=80)
    position: Position | None = None
    crumb_id: UUID | None = None
    zone: str | None = None
    tags: Annotated[list[PlaceTag], AfterValidator(_unique)]
    source: PlaceSource
    created_at: Timestamp


class Feedback(Contract):
    id: UUID
    session_id: UUID
    place_id: UUID
    goal: Goal
    verdict: Verdict
    feel: Feel | None = None
    t: Timestamp


class Guidance(Contract):
    session_id: UUID
    target_place_id: UUID
    target_label: str
    status: GuidanceStatus
    reason: str | None = None
    updated_at: Timestamp


class SessionUpsert(Contract):
    contract_version: ContractVersion
    session: Session


class ObservationBatch(Contract):
    contract_version: ContractVersion
    observations: list[Observation] = Field(max_length=500)


class CrumbBatch(Contract):
    contract_version: ContractVersion
    crumbs: list[Crumb] = Field(max_length=2000)


class PlaceBatch(Contract):
    contract_version: ContractVersion
    places: list[Place] = Field(max_length=200)


class FeedbackBatch(Contract):
    contract_version: ContractVersion
    feedback: list[Feedback] = Field(max_length=200)


class GuidanceStatusUpdate(Contract):
    contract_version: ContractVersion
    status: Literal["arrived", "cancelled"]


class IngestResult(Contract):
    accepted: int = Field(ge=0)
    duplicates: int = Field(ge=0)
