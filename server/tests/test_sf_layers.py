"""SF layers with the network mocked: parsing, labelling, caching, failure isolation, MCP tool."""

from __future__ import annotations

from datetime import datetime
from typing import Any

import httpx2 as httpx
from conftest import NOW, TOKEN
from starlette.testclient import TestClient
from test_mcp import TOOLS, call, rpc

from quiet_compass.app import create_app
from quiet_compass.settings import Settings
from quiet_compass.sf_layers import (
    ALL_LAYERS,
    CAVEATS,
    DATASETS,
    REFERENCE_LEVELS,
    SfLayers,
    latest_sfo_monitors,
    parse_closure,
    parse_night_noise,
)

# Row shapes copied from live responses (2026-10-24), trimmed to the selected fields.
POPOS = [
    {"name": "Transamerica Redwood Park", "latitude": "37.79514", "longitude": "-122.40283",
     "type": "Park", "hours_type": "Open Business Hours", "indoor": False},
    {"name": "Broken row", "latitude": "", "longitude": ""},
]
LIBS = [
    {"common_name": "Main Library", "latitude": "37.77901", "longitude": "-122.41600"},
    {"common_name": "Library Support Services", "latitude": "37.7745", "longitude": "-122.4130"},
]
ENT = [
    {"dba_name": "111 Minna Gallery", "license_type": "Place of Entertainment",
     "point": {"type": "Point", "coordinates": [-122.399379, 37.787301]}},
    {"dba_name": "Far away bar", "point": {"type": "Point", "coordinates": [-122.2, 37.9]}},
]
NIGHT = [
    {"nnp": "111328", "type_of_work": "concrete staging", "start_date": "2026-10-24T00:00:00.000",
     "end_date": "2026-10-25T00:00:00.000", "start_end_time_each_day": "5:00am7:00am",
     "address": "3501 Cesar Chavez St",
     "point": {"type": "Point", "coordinates": [-122.421, 37.7473]}},
    {"nnp": "DENIED", "start_date": "2026-10-24T00:00:00.000", "end_date": "2026-10-24T00:00:00.000",
     "address": "x", "point": {"type": "Point", "coordinates": [-122.42, 37.75]}},
    {"nnp": "111", "start_date": "2026-10-24T00:00:00.000", "end_date": "2219-11-22T00:00:00.000",
     "address": "bogus end date", "point": {"type": "Point", "coordinates": [-122.42, 37.75]}},
]
CLOSURES = [
    {"type": "Special Event", "loc_desc": "OAK ST between STANYAN ST and BRODERICK ST", "veh_imp": "all-lanes-closed",
     "shape": {"type": "LineString", "coordinates": [[-122.45398, 37.77143], [-122.4533, 37.77139]]}},
    {"type": "Special Event", "loc_desc": "no geometry"},
]
SFO = [
    {"date": "2026-08-30T00:00:00.000", "location_id": "21", "latitude": "37.740", "longitude": "-122.433",
     "aircraft_cnel": "40.0", "community_cnel": "60.0", "total_cnel": "60.1"},
    {"date": "2026-08-31T00:00:00.000", "location_id": "21", "latitude": "37.740", "longitude": "-122.433",
     "aircraft_cnel": "45.2", "community_cnel": "61.0", "total_cnel": "61.1"},
    {"date": "2026-08-31T00:00:00.000", "location_id": "23", "latitude": "37.711", "longitude": "-122.399",
     "aircraft_cnel": "52.0", "community_cnel": "58.0", "total_cnel": ""},
]
BY_ID: dict[str, list[dict[str, Any]]] = {
    DATASETS["popos"]: POPOS, DATASETS["libraries"]: LIBS, DATASETS["entertainment"]: ENT,
    DATASETS["night_noise"]: NIGHT, DATASETS["closures"]: CLOSURES, DATASETS["sfo"]: SFO,
}


def make_layers(fail: set[str] | None = None, calls: list[str] | None = None) -> SfLayers:
    def handler(request: httpx.Request) -> httpx.Response:
        dataset = request.url.path.rsplit("/", 1)[-1].removesuffix(".json")
        if calls is not None:
            calls.append(dataset)
        if fail and dataset in fail:
            return httpx.Response(503)
        return httpx.Response(200, json=BY_ID[dataset])

    client = httpx.Client(transport=httpx.MockTransport(handler))
    return SfLayers(client=client, clock=lambda: NOW)


def test_candidates_are_unmeasured_seed_and_filtered() -> None:
    points = make_layers().layer("quiet_candidates")
    assert {p.label for p in points} == {"Transamerica Redwood Park", "Main Library"}
    assert all(p.evidence == "unmeasured_candidate" and p.source == "seed" for p in points)
    assert all(p.cnel_db is None and "nobody has measured" in p.caveat for p in points)


def test_only_sfo_is_measured_and_latest_per_monitor_wins() -> None:
    layers = make_layers()
    sfo = layers.layer("sfo_cnel")
    assert [(p.label, p.cnel_db, p.observed_on) for p in sfo] == [("SFO noise monitor 21", 61.1, "2026-08-31")]
    assert sfo[0].evidence == "measured"
    for name in ("entertainment_permits", "night_noise_permits", "street_closures"):
        assert all(p.evidence == "proxy" and p.cnel_db is None for p in layers.layer(name))
    assert latest_sfo_monitors([]) == []


def test_night_permits_skip_denied_and_bogus_dates() -> None:
    today = datetime(2026, 10, 24)
    assert parse_night_noise(NIGHT[0], today) is not None
    assert parse_night_noise(NIGHT[1], today) is None
    assert parse_night_noise(NIGHT[2], today) is None


def test_closure_uses_middle_vertex_and_needs_geometry() -> None:
    p = parse_closure(CLOSURES[0])
    assert p is not None and p.lat == 37.77139 and p.lon == -122.4533
    assert parse_closure(CLOSURES[1]) is None


def test_around_filters_by_radius_sorts_and_caps_sfo() -> None:
    s = make_layers().around(37.7952, -122.4030, 300)
    assert [p.label for p in s.points["quiet_candidates"]] == ["Transamerica Redwood Park"]
    assert s.points["entertainment_permits"] == []  # 111 Minna is ~1.3 km away
    assert s.points["sfo_cnel"] == []  # nearest monitor is beyond 5 km
    far = make_layers().around(37.74, -122.43, 300)
    assert far.points["sfo_cnel"][0].distance_m is not None and far.points["sfo_cnel"][0].distance_m < 500


def test_cache_and_failure_isolation() -> None:
    calls: list[str] = []
    layers = make_layers(fail={DATASETS["closures"]}, calls=calls)
    first = layers.around(37.7952, -122.4030, 500)
    assert DATASETS["closures"] in first.unavailable["street_closures"]
    assert "quiet_candidates" in first.points and "street_closures" not in first.points
    layers.around(37.7952, -122.4030, 500)
    assert calls.count(DATASETS["popos"]) == 1  # cached
    assert calls.count(DATASETS["closures"]) == 2  # failures are not cached


def test_reference_levels_are_cited_and_have_no_free_coordinates() -> None:
    assert REFERENCE_LEVELS and all(r.evidence == "reference_measured" for r in REFERENCE_LEVELS)
    assert all(r.source_url.startswith("https://") and not hasattr(r, "lat") for r in REFERENCE_LEVELS)
    streets = [r.level_dba_ldn for r in REFERENCE_LEVELS if "main street" in r.location]
    alleys = [r.level_dba_ldn for r in REFERENCE_LEVELS if "alley" in r.location]
    assert min(streets) >= 69 and max(alleys) <= 67


def test_every_layer_has_a_caveat() -> None:
    assert set(CAVEATS) == set(ALL_LAYERS)


def _app(tmp_path: Any, layers: SfLayers | None) -> TestClient:
    settings = Settings(api_token=TOKEN, db_path=tmp_path / "l.db", city_layer_enabled=layers is not None)
    return TestClient(create_app(settings, layers=layers), base_url="http://localhost")


def test_mcp_tool_labels_and_references(tmp_path: Any) -> None:
    with _app(tmp_path, make_layers()) as c:
        names = {t["name"] for t in rpc(c, "tools/list").json()["result"]["tools"]}
        assert "quiet_sf_layers" in names
        out = call(c, "quiet_sf_layers", lat=37.7952, lon=-122.403, radius_m=300, include_references=True)
        body = out["structuredContent"]
        cand = body["layers"]["quiet_candidates"][0]
        assert cand["evidence"] == "unmeasured_candidate" and cand["source"] == "seed"
        assert body["references"][0]["evidence"] == "reference_measured"
        assert "source_url" in body["references"][0] and "unavailable" not in body
        only = call(c, "quiet_sf_layers", lat=37.74, lon=-122.43, include=["sfo_cnel"])["structuredContent"]
        assert list(only["layers"]) == ["sfo_cnel"] and only["layers"]["sfo_cnel"][0]["evidence"] == "measured"
        assert "references" not in only


def test_mcp_tool_validates_input_and_reports_partial_failure(tmp_path: Any) -> None:
    with _app(tmp_path, make_layers(fail={DATASETS["sfo"]})) as c:
        assert call(c, "quiet_sf_layers", lat=40.0, lon=-122.4)["isError"] is True
        assert call(c, "quiet_sf_layers", lat=37.79, lon=-122.4, radius_m=5)["isError"] is True
        body = call(c, "quiet_sf_layers", lat=37.79, lon=-122.4)["structuredContent"]
        assert "sfo_cnel" in body["unavailable"] and "quiet_candidates" in body["layers"]


def test_tool_absent_when_layers_disabled(tmp_path: Any) -> None:
    with _app(tmp_path, None) as c:
        names = {t["name"] for t in rpc(c, "tools/list").json()["result"]["tools"]}
    assert names == TOOLS




def test_tool_output_matches_json_schema(tmp_path: Any) -> None:
    import json
    from pathlib import Path

    import jsonschema

    d = json.loads((Path(__file__).parents[2] / "contracts" / "quiet-compass.schema.json").read_text())
    schema = {"$schema": d["$schema"], "$defs": d["$defs"], "$ref": "#/$defs/SfLayersResult"}
    with _app(tmp_path, make_layers()) as c:
        body = call(c, "quiet_sf_layers", lat=37.7952, lon=-122.403, radius_m=2000, include_references=True)
    validator = jsonschema.Draft202012Validator(schema, format_checker=jsonschema.FormatChecker())
    validator.validate(body["structuredContent"])
    assert {"quiet_candidates", "sfo_cnel"} <= set(body["structuredContent"]["layers"])
