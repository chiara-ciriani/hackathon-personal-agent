"""Shared sound layer logic: rounding, validation, release policy, retention and ranking."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import pytest
from conftest import NOW, TOKEN, Clock, uid
from pydantic import ValidationError

from quiet_compass.contracts import format_utc
from quiet_compass.settings import Settings, SettingsError
from quiet_compass.shared_contracts import SharedContribution
from quiet_compass.shared_db import SharedStore
from quiet_compass.shared_layer import (
    SharedLayer,
    cell_id,
    floor_bucket,
    rank_candidates,
    relative_quietness,
)
from quiet_compass.shared_tools import find_suitable_places

LAT, LON = 37.7701, -122.4201  # rounds to the cell 37.770,-122.420


def contribution(
    rms: float = -40.0,
    *,
    area_id: str = "sample-courtyard",
    lat: float | None = LAT,
    lon: float | None = LON,
    minutes_ago: float = 1,
    spread: float = 5.0,
    peaks: float | None = 1.0,
    duration: float = 30,
    profile: str = "iphone-measurement-v1",
    clipping: bool = False,
    source: str = "device",
    contribution_id: str | None = None,
) -> dict[str, Any]:
    return {
        "id": contribution_id or uid(),
        "schema_version": "0.1",
        "area_id": area_id,
        "area_name": None,
        "lat": lat,
        "lon": lon,
        "time_bucket": format_utc(NOW - timedelta(minutes=minutes_ago)),
        "duration_seconds": duration,
        "measurement": {
            "kind": "relative_uncalibrated", "rms_dbfs": rms, "frame_level_spread_db": spread,
            "peaks_per_min": peaks, "calibrated": False,
        },
        "quality": {"capture_profile": profile, "clipping_detected": clipping},
        "source": source,
    }


def make_layer(tmp_path: Path, clock: Clock, **overrides: Any) -> SharedLayer:
    settings = Settings(api_token=TOKEN, db_path=tmp_path / "shared.db", **overrides)
    store = SharedStore(settings.db_path, clock=clock)
    store.migrate_shared()
    return SharedLayer(store, settings, clock=clock)


@pytest.fixture
def layer(tmp_path: Path, clock: Clock) -> SharedLayer:
    return make_layer(tmp_path, clock)


def submit(layer: SharedLayer, **kwargs: Any) -> Any:
    return layer.submit(SharedContribution.model_validate(contribution(**kwargs)))


def test_floor_bucket_and_cell_rounding() -> None:
    t = datetime(2026, 10, 24, 20, 14, 59, 999000, tzinfo=UTC)
    assert floor_bucket(t) == datetime(2026, 10, 24, 20, 10, tzinfo=UTC)
    assert cell_id(round(LAT, 3), round(LON, 3)) == "cell:37.770,-122.420"


def test_unknown_area_with_coords_creates_rounded_cell(layer: SharedLayer) -> None:
    result = submit(layer, minutes_ago=3.5)
    assert result.area_id == "cell:37.770,-122.420"
    assert result.time_bucket == datetime(2026, 10, 24, 20, 55, tzinfo=UTC)
    area = layer.store.get_area(result.area_id)
    assert area is not None and (area.lat, area.lon, area.kind) == (37.77, -122.42, "outdoor_cell")


def test_unknown_area_without_coords_is_rejected(layer: SharedLayer) -> None:
    result = submit(layer, lat=None, lon=None)
    assert result.status == "rejected"
    assert "unknown area_id" in (result.reason or "")


def test_known_indoor_zone_is_used_without_coords(layer: SharedLayer) -> None:
    layer.upsert_area("hall-quiet-room", "Quiet room", 37.78, -122.41, "indoor_zone")
    result = submit(layer, area_id="hall-quiet-room", lat=None, lon=None)
    assert result.area_id == "hall-quiet-room"
    assert result.status == "withheld"


@pytest.mark.parametrize(
    ("kwargs", "needle"),
    [
        ({"rms": -121.0}, "below"),
        ({"spread": 61.0}, "exceeds"),
        ({"duration": 4}, "duration_seconds"),
        ({"duration": 601}, "duration_seconds"),
        ({"minutes_ago": -30}, "future"),
        ({"minutes_ago": 25 * 60}, "retention"),
    ],
)
def test_implausible_values_are_rejected(layer: SharedLayer, kwargs: dict[str, Any], needle: str) -> None:
    result = submit(layer, **kwargs)
    assert result.status == "rejected"
    assert needle in (result.reason or "")


def test_schema_rejects_positive_dbfs_and_calibrated_claims() -> None:
    with pytest.raises(ValidationError):
        SharedContribution.model_validate(contribution(rms=1.0))
    body = contribution()
    body["measurement"]["calibrated"] = True
    with pytest.raises(ValidationError):
        SharedContribution.model_validate(body)
    with pytest.raises(ValidationError):
        SharedContribution.model_validate(contribution(lat=None))


def test_withheld_until_threshold_then_released(layer: SharedLayer) -> None:
    first = submit(layer)
    assert first.status == "withheld"
    assert layer.aggregates(LAT, LON, 500, 60) == []
    second = submit(layer, rms=-44.0)
    assert second.status == "accepted"
    [agg] = layer.aggregates(LAT, LON, 500, 60)
    assert agg.n == 2 and agg.median_rms_dbfs == -42.0
    assert agg.source == "device" and agg.has_synthetic is False


def test_duplicate_id_is_idempotent(layer: SharedLayer) -> None:
    cid = uid()
    assert submit(layer, contribution_id=cid).status == "withheld"
    again = submit(layer, contribution_id=cid)
    assert again.status == "withheld" and "duplicate" in (again.reason or "")
    assert layer.store.cohort_size("cell:37.770,-122.420", floor_bucket(NOW - timedelta(minutes=1)),
                                   "iphone-measurement-v1") == 1


def test_clipping_is_stored_and_flagged(layer: SharedLayer) -> None:
    result = submit(layer, clipping=True)
    assert result.status == "withheld" and "clipping" in (result.reason or "")
    submit(layer)
    [agg] = layer.aggregates(LAT, LON, 500, 60)
    assert agg.clipped_count == 1


def test_rate_limit_per_cohort(layer: SharedLayer) -> None:
    assert [submit(layer).status for _ in range(3)] == ["withheld", "accepted", "accepted"]
    fourth = submit(layer)
    assert fourth.status == "rejected" and "rate limit" in (fourth.reason or "")
    assert submit(layer, profile="other-profile").status == "withheld"


def test_cohorts_with_different_profiles_never_merge(layer: SharedLayer) -> None:
    for rms, profile in [(-40, "a"), (-42, "a"), (-20, "b"), (-22, "b")]:
        submit(layer, rms=rms, profile=profile)
    aggs = {a.capture_profile: a for a in layer.aggregates(LAT, LON, 500, 60)}
    assert set(aggs) == {"a", "b"}
    assert aggs["a"].median_rms_dbfs == -41.0 and aggs["b"].median_rms_dbfs == -21.0


def test_synthetic_source_is_labelled(layer: SharedLayer) -> None:
    submit(layer, source="simulated")
    submit(layer)
    [agg] = layer.aggregates(LAT, LON, 500, 60)
    assert agg.has_synthetic and agg.source == "mixed" and "simulated" in agg.coverage


def test_retention_purges_old_contributions_on_write(layer: SharedLayer, clock: Clock) -> None:
    submit(layer)
    submit(layer)
    clock.now = NOW + timedelta(hours=25)
    submit(layer, minutes_ago=-25 * 60 + 1)  # a fresh contribution triggers the purge
    assert layer.store.cohort_size("cell:37.770,-122.420", floor_bucket(NOW - timedelta(minutes=1)),
                                   "iphone-measurement-v1") == 0


def test_release_threshold_is_configurable(tmp_path: Path, clock: Clock) -> None:
    single = make_layer(tmp_path, clock, release_min_contributions=1)
    assert submit(single).status == "accepted"
    with pytest.raises(SettingsError):
        Settings(api_token=TOKEN, release_min_contributions=0)


def test_relative_quietness_within_cohort() -> None:
    assert relative_quietness({"x": -40}) == {"x": None}
    assert relative_quietness({"x": -50, "y": -40, "z": -30}) == {"x": 1.0, "y": 0.5, "z": 0.0}


def seed_two_areas(layer: SharedLayer) -> None:
    layer.upsert_area("quiet-room", "Quiet room", 37.7701, -122.4201, "indoor_zone")
    layer.upsert_area("food-court", "Food court", 37.7705, -122.4201, "indoor_zone")
    for _ in range(2):
        submit(layer, area_id="quiet-room", rms=-50, spread=3, peaks=0.5)
        submit(layer, area_id="food-court", rms=-25, spread=14, peaks=9)


def test_find_suitable_places_ranks_quieter_area_first(layer: SharedLayer) -> None:
    seed_two_areas(layer)
    result = find_suitable_places(layer, "rest", LAT, LON, 10, None, 30)
    assert result.no_fit is False and result.candidates is not None
    top = result.candidates[0]
    assert top.area_id == "quiet-room" and top.relative_quietness == 1.0
    assert "estimate" in top.walk.source and top.supporting_observations
    assert "capture profile" in top.uncertainty


def test_ranking_does_not_compare_across_profiles(layer: SharedLayer) -> None:
    layer.upsert_area("a", None, LAT, LON, "indoor_zone")
    layer.upsert_area("b", None, LAT, LON, "indoor_zone")
    for _ in range(2):
        submit(layer, area_id="a", rms=-60, profile="p1")
        submit(layer, area_id="b", rms=-20, profile="p2")
    ranked = rank_candidates("rest", layer.aggregates(LAT, LON, 500, 60), 10)
    assert all(c.relative_quietness is None for c in ranked)


def test_find_suitable_places_no_fit(layer: SharedLayer) -> None:
    result = find_suitable_places(layer, "work", LAT, LON, 10, None, 30)
    assert result.no_fit is True and "unknown" in (result.reason or "")
    seed_two_areas(layer)
    far = find_suitable_places(layer, "work", 37.80, -122.40, 5, None, 30)
    assert far.no_fit is True


def test_find_suitable_places_respects_age(layer: SharedLayer) -> None:
    layer.upsert_area("old", None, LAT, LON, "indoor_zone")
    for _ in range(2):
        submit(layer, area_id="old", minutes_ago=60)
    assert find_suitable_places(layer, "rest", LAT, LON, 10, None, 30).no_fit is True
    assert find_suitable_places(layer, "rest", LAT, LON, 10, None, 90).no_fit is False


def test_find_suitable_places_drops_candidates_that_miss_return_by(layer: SharedLayer) -> None:
    layer.upsert_area("far", None, 37.7760, -122.4201, "indoor_zone")  # ~655 m, ~13.6 min each way
    for _ in range(2):
        submit(layer, area_id="far")
    tight = find_suitable_places(layer, "rest", LAT, LON, 20, NOW + timedelta(minutes=20), 30)
    assert tight.no_fit is True and "round trip" in (tight.reason or "")
    roomy = find_suitable_places(layer, "rest", LAT, LON, 20, NOW + timedelta(minutes=40), 30)
    assert roomy.candidates is not None and roomy.candidates[0].fits_return_by is True
