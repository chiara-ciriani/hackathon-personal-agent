"""SF layers with the network mocked: parsing, labelling, caching, failure isolation, MCP tool."""

from __future__ import annotations

import json
import tempfile
from datetime import datetime
from pathlib import Path
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
    cad_noise_areas,
    latest_sfo_monitors,
    noisecapture_cells,
    parse_closure,
    parse_night_noise,
    parse_park,
    parse_street_work,
    sfo_event_monitors,
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
# x8nh-xzn6 rows (2026-10-24), trimmed to the selected fields.
WORK = [
    {"permit_type": "Excavation", "streetname": "08TH ST", "cross_street_1": "NATOMA ST", "cross_street_2": "HOWARD ST",
     "permit_start_date": "2026-05-01T00:00:00.000", "permit_end_date": "2026-10-28T00:00:00.000",
     "location": {"type": "Point", "coordinates": [-122.41188, 37.77644]}},
    {"permit_type": "Boring", "streetname": "CLAY ST", "cross_street_1": "LARKIN ST",
     "permit_start_date": "2026-10-24T00:00:00.000", "permit_end_date": "2026-10-24T00:00:00.000",
     "location": {"type": "Point", "coordinates": [-122.4194, 37.79259]}},
    {"permit_type": "Wireless", "streetname": "x", "permit_start_date": "2026-10-01T00:00:00.000",
     "permit_end_date": "2026-11-01T00:00:00.000", "location": {"type": "Point", "coordinates": [-122.42, 37.75]}},
    {"permit_type": "Excavation", "streetname": "ended", "permit_start_date": "2026-10-01T00:00:00.000",
     "permit_end_date": "2026-10-23T00:00:00.000", "location": {"type": "Point", "coordinates": [-122.42, 37.75]}},
    {"permit_type": "Excavation", "streetname": "no point", "permit_start_date": "2026-10-01T00:00:00.000",
     "permit_end_date": "2026-11-01T00:00:00.000"},
]
SFO = [
    {"date": "2026-08-30T00:00:00.000", "location_id": "21", "latitude": "37.740", "longitude": "-122.433",
     "aircraft_cnel": "40.0", "community_cnel": "60.0", "total_cnel": "60.1"},
    {"date": "2026-08-31T00:00:00.000", "location_id": "21", "latitude": "37.740", "longitude": "-122.433",
     "aircraft_cnel": "45.2", "community_cnel": "61.0", "total_cnel": "61.1"},
    {"date": "2026-08-31T00:00:00.000", "location_id": "23", "latitude": "37.711", "longitude": "-122.399",
     "aircraft_cnel": "52.0", "community_cnel": "58.0", "total_cnel": ""},
]
PARKS = [
    {"property_name": "Dolores Park", "latitude": "37.75965", "longitude": "-122.42691",
     "propertytype": "Neighborhood Park or Playground", "acres": "15.9"},
    {"property_name": "Main Library", "latitude": "37.779", "longitude": "-122.416", "propertytype": "Library"},
    {"property_name": "Family Camp", "latitude": "37.9", "longitude": "-120.1", "propertytype": "Family Camp"},
    {"property_name": "No coords", "latitude": "", "longitude": "", "propertytype": "Mini Park"},
]
# tiju-qyvs: max_level is TEXT. Monitor 99 has no coordinates in qxw2, so it cannot be placed and is skipped.
SFO_EVENTS = [
    {"location_id": "21", "max_date_time": "2026-03-19T23:30:03.000", "max_level": "83.9"},
    {"location_id": "21", "max_date_time": "2026-01-02T01:00:00.000", "max_level": "81.1"},
    {"location_id": "21", "max_date_time": "2025-12-01T01:00:00.000", "max_level": "100.2"},
    {"location_id": "21", "max_date_time": "2025-11-01T01:00:00.000", "max_level": "n/a"},
    {"location_id": "23", "max_date_time": "2026-08-02T01:03:50.000", "max_level": "71.0"},
    {"location_id": "99", "max_date_time": "2026-08-02T01:03:50.000", "max_level": "90.0"},
]
CAD = [
    {"cad_number": "A1", "received_datetime": "2026-10-20T10:00:00.000", "intersection_name": "MISSION ST \\ 16TH ST",
     "intersection_point": {"type": "Point", "coordinates": [-122.41964, 37.76481]}, "sensitive_call": False},
    {"cad_number": "A2", "received_datetime": "2026-10-23T22:00:00.000", "intersection_name": "MISSION ST \\ 16TH ST",
     "intersection_point": {"type": "Point", "coordinates": [-122.41964, 37.76481]}, "sensitive_call": False},
    {"cad_number": "A2", "received_datetime": "2026-10-23T22:00:00.000", "intersection_name": "MISSION ST \\ 16TH ST",
     "intersection_point": {"type": "Point", "coordinates": [-122.41964, 37.76481]}, "sensitive_call": False},
    {"cad_number": "A3", "received_datetime": "2026-10-22T22:00:00.000", "intersection_name": "SENSITIVE",
     "intersection_point": {"type": "Point", "coordinates": [-122.4, 37.77]}, "sensitive_call": True},
    {"cad_number": "A4", "received_datetime": "2026-10-22T22:00:00.000", "intersection_name": "NO POINT"},
]
NC = {"type": "FeatureCollection", "features": [
    {"type": "Feature", "geometry": {"type": "Point", "coordinates": [-122.4183, 37.7579]},
     "properties": {"evidence": "measured_crowdsourced", "cell_m": 100, "laeq_db": 74.6, "median_window_db": 48.8,
                    "windows": 648, "tracks": 22, "periods": {"day": {"laeq_db": 77.3, "windows": 328}},
                    "first_date": "2021-02-07", "last_date": "2021-08-03"}},
    {"type": "Feature", "geometry": {"type": "Point", "coordinates": [-122.4, 37.9]},
     "properties": {"laeq_db": 60, "median_window_db": 60}},
]}
NC_PATH = Path(tempfile.mkdtemp()) / "nc.json"
NC_PATH.write_text(json.dumps(NC))
BY_ID: dict[str, list[dict[str, Any]]] = {
    DATASETS["popos"]: POPOS, DATASETS["libraries"]: LIBS, DATASETS["entertainment"]: ENT,
    DATASETS["night_noise"]: NIGHT, DATASETS["closures"]: CLOSURES, DATASETS["sfo"]: SFO,
    DATASETS["parks"]: PARKS, DATASETS["sfo_events"]: SFO_EVENTS, DATASETS["cad"]: CAD,
    DATASETS["street_work"]: WORK,
}


def make_layers(
    fail: set[str] | None = None, calls: list[str] | None = None, nc_path: Path | None = NC_PATH
) -> SfLayers:
    def handler(request: httpx.Request) -> httpx.Response:
        dataset = request.url.path.rsplit("/", 1)[-1].removesuffix(".json")
        if calls is not None:
            calls.append(dataset)
        if fail and dataset in fail:
            return httpx.Response(503)
        return httpx.Response(200, json=BY_ID[dataset])

    client = httpx.Client(transport=httpx.MockTransport(handler))
    return SfLayers(client=client, clock=lambda: NOW, noisecapture_path=nc_path)


def test_candidates_are_unmeasured_seed_and_filtered() -> None:
    points = make_layers().layer("quiet_candidates")
    assert {p.label for p in points} == {"Transamerica Redwood Park", "Main Library", "Dolores Park"}
    assert all(p.evidence == "unmeasured_candidate" and p.source == "seed" for p in points)
    assert all(p.cnel_db is None and "nobody has measured" in p.caveat for p in points)
    park = next(p for p in points if p.kind == "park")
    assert park.dataset == DATASETS["parks"] and "15.9 acres" in (park.detail or "") and "loud" in park.caveat
    assert parse_park(PARKS[1]) is None and parse_park(PARKS[2]) is None and parse_park(PARKS[3]) is None


def test_only_sfo_is_measured_and_latest_per_monitor_wins() -> None:
    layers = make_layers()
    sfo = layers.layer("sfo_cnel")
    assert [(p.label, p.cnel_db, p.observed_on) for p in sfo] == [("SFO noise monitor 21", 61.1, "2026-08-31")]
    assert sfo[0].evidence == "measured"
    for name in ("entertainment_permits", "night_noise_permits", "street_closures", "street_work_permits"):
        assert all(p.evidence == "proxy" and p.cnel_db is None for p in layers.layer(name))
    assert latest_sfo_monitors([]) == []


def test_night_permits_skip_denied_and_bogus_dates() -> None:
    today = datetime(2026, 10, 24)
    assert parse_night_noise(NIGHT[0], today) is not None
    assert parse_night_noise(NIGHT[1], today) is None
    assert parse_night_noise(NIGHT[2], today) is None


def test_street_work_keeps_noisy_types_valid_today() -> None:
    today = datetime(2026, 10, 24)
    first = parse_street_work(WORK[0], today)
    assert first is not None and first.label == "08TH ST between NATOMA ST and HOWARD ST"
    assert first.detail == "Excavation; until 2026-10-28" and first.evidence == "proxy"
    assert (first.lat, first.lon) == (37.77644, -122.41188) and first.dataset == "x8nh-xzn6"
    assert "may not be happening right now" in first.caveat
    one_day = parse_street_work(WORK[1], today)
    assert one_day is not None and one_day.label == "CLAY ST at LARKIN ST"
    assert [parse_street_work(r, today) for r in WORK[2:]] == [None, None, None]
    labels = {p.label for p in make_layers().layer("street_work_permits")}
    assert labels == {"08TH ST between NATOMA ST and HOWARD ST", "CLAY ST at LARKIN ST"}


def test_closure_uses_middle_vertex_and_needs_geometry() -> None:
    p = parse_closure(CLOSURES[0])
    assert p is not None and p.lat == 37.77139 and p.lon == -122.4533
    assert parse_closure(CLOSURES[1]) is None


def test_around_filters_by_radius_sorts_and_caps_sfo() -> None:
    s = make_layers().around(37.7952, -122.4030, 300)
    assert [p.label for p in s.points["quiet_candidates"]] == ["Transamerica Redwood Park"]  # Dolores is 4 km away
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


def test_sfo_events_summarise_per_monitor_with_date_and_skip_unplaceable() -> None:
    pts = make_layers().layer("sfo_events")
    by = {p.label: p for p in pts}
    m21 = by["SFO noise monitor 21"]
    assert m21.evidence == "measured" and m21.dataset == DATASETS["sfo_events"]
    # 83.9 / 81.1 / 100.2 ("n/a" skipped): count 3, median 83.9, max 100.2, latest date shown
    assert (m21.count, m21.median_level_db, m21.max_level_db, m21.observed_on) == (3, 83.9, 100.2, "2026-03-19")
    assert "2026-03-19" in (m21.detail or "") and "declares no license" in m21.caveat
    assert "SFO noise monitor 99" not in by  # not in the SF monitor list, so never invented
    assert m21.cnel_db is None  # event levels are not CNEL
    assert sfo_event_monitors([], SFO_EVENTS, 365) == []  # no coordinates, no points


def test_sfo_events_query_uses_text_level_ids_from_monitor_join() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        dataset = request.url.path.rsplit("/", 1)[-1].removesuffix(".json")
        return httpx.Response(200, json=BY_ID[dataset])

    SfLayers(client=httpx.Client(transport=httpx.MockTransport(handler)), clock=lambda: NOW).layer("sfo_events")
    events = next(r for r in seen if DATASETS["sfo_events"] in str(r.url))
    where = events.url.params["$where"]
    assert "location_id in('21','23')" in where and "max_date_time >= '2025-10-24T00:00:00'" in where


def test_cad_noise_calls_count_per_masked_intersection() -> None:
    pts = make_layers().layer("cad_noise_calls")
    assert len(pts) == 1  # sensitive, duplicate and pointless rows dropped
    p = pts[0]
    assert (p.count, p.evidence, p.observed_on, p.label) == (2, "proxy", "2026-10-23", "MISSION ST / 16TH ST")
    assert "complaints, not measurements" in p.caveat and p.cnel_db is None and p.max_level_db is None
    assert cad_noise_areas([], 24) == []


def test_noisecapture_cells_are_crowdsourced_and_never_plain_measured() -> None:
    pts = make_layers().layer("noisecapture")
    assert len(pts) == 1  # the out-of-city cell is dropped
    p = pts[0]
    assert p.evidence == "measured_crowdsourced" and p.quality == "measured_crowdsourced_uncalibrated"
    assert (p.median_level_db, p.laeq_db, p.count) == (48.8, 74.6, 648)
    assert "ODbL" in p.caveat and "uncalibrated" in p.caveat and p.cnel_db is None
    assert noisecapture_cells({"features": []}) == []


def test_noisecapture_missing_file_is_unavailable_not_invented() -> None:
    layers = make_layers(nc_path=Path(tempfile.gettempdir()) / "does-not-exist-nc.json")
    s = layers.around(37.7579, -122.4183, 500, ["noisecapture"])
    assert "noisecapture" in s.unavailable and s.points == {}


def test_shipped_noisecapture_file_is_labelled_and_in_city() -> None:
    from quiet_compass.sf_layers import NOISECAPTURE_FILE

    data = json.loads(NOISECAPTURE_FILE.read_text())
    assert "ODbL" in data["attribution"] and data["features"]
    for f in data["features"]:
        pr = f["properties"]
        assert pr["evidence"] == "measured_crowdsourced" and pr["tracks"] >= 3 and pr["windows"] >= 5
    pts = SfLayers(clock=lambda: NOW).layer("noisecapture")
    assert len(pts) == len(data["features"])


def test_mcp_tool_new_layers_labels(tmp_path: Any) -> None:
    with _app(tmp_path, make_layers()) as c:
        body = call(c, "quiet_sf_layers", lat=37.7579, lon=-122.4183, radius_m=2000)["structuredContent"]
        assert {"sfo_events", "cad_noise_calls", "noisecapture"} <= set(body["layers"])
        assert body["layers"]["noisecapture"][0]["evidence"] == "measured_crowdsourced"
        assert body["layers"]["cad_noise_calls"][0]["evidence"] == "proxy"
        ev = call(c, "quiet_sf_layers", lat=37.74, lon=-122.433, include=["sfo_events"])["structuredContent"]
        assert ev["layers"]["sfo_events"][0]["evidence"] == "measured"
        assert ev["layers"]["sfo_events"][0]["observed_on"] == "2026-03-19"
