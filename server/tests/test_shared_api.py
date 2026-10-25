"""Shared sound layer over REST and MCP, as the phone, the web map and an agent use it."""

from __future__ import annotations

import json
from datetime import timedelta
from pathlib import Path
from typing import Any

import pytest
from conftest import AUTH, uid
from starlette.testclient import TestClient
from test_mcp import TOOLS, call, rpc
from test_shared_layer import LAT, LON, contribution

SHARED_TOOLS = {"query_sound_map", "find_suitable_places", "submit_observation"}
MAP_QUERY = {"lat": LAT, "lon": LON, "radius_m": 500, "since_minutes": 60}


def post(client: TestClient, body: dict[str, Any], headers: dict[str, str] = AUTH) -> Any:
    return client.post("/v1/contributions",
                       json={"contract_version": 1, "contribution": body, "share_consent": True}, headers=headers)


def test_contribution_requires_token(client: TestClient) -> None:
    assert post(client, contribution(), headers={}).status_code == 401
    assert client.put("/v1/areas/zone-a", json={"name": "A", "lat": LAT, "lon": LON,
                                                "kind": "indoor_zone"}).status_code == 401


def test_contribution_flow_withheld_then_released(client: TestClient) -> None:
    first = post(client, contribution())
    assert first.status_code == 200
    headers = {**AUTH, "X-QC-Access-Receipt": first.json()["access_receipt"]}
    assert first.json()["status"] == "withheld"
    assert first.json()["area_id"] == "cell:37.770,-122.420"
    assert first.json()["time_bucket"].endswith(":55:00.000Z")
    assert client.get("/v1/map/aggregates", params=MAP_QUERY, headers=headers).json()["aggregates"] == []
    assert post(client, contribution(rms=-44)).json()["status"] == "accepted"
    released = client.get("/v1/map/aggregates", params=MAP_QUERY, headers=headers)
    assert released.status_code == 200
    [agg] = released.json()["aggregates"]
    assert agg["n"] == 2 and agg["measurement_kind"] == "relative_uncalibrated"
    assert "unknown" in released.json()["unknown_coverage"]


def test_contribution_schema_errors_are_422(client: TestClient) -> None:
    assert post(client, contribution(rms=3)).status_code == 422
    bad = client.post("/v1/contributions", json={"contract_version": 2, "contribution": contribution()},
                      headers=AUTH)
    assert bad.status_code == 422


def test_put_area_then_contribute_without_coords(client: TestClient) -> None:
    r = client.put("/v1/areas/hall-quiet-room", json={"name": "Quiet room", "lat": LAT, "lon": LON,
                                                       "kind": "indoor_zone"}, headers=AUTH)
    assert r.status_code == 200 and r.json()["kind"] == "indoor_zone"
    out = post(client, contribution(area_id="hall-quiet-room", lat=None, lon=None)).json()
    assert out["area_id"] == "hall-quiet-room" and out["status"] == "withheld"
    assert client.put("/v1/areas/bad%20id", json={"name": None, "lat": LAT, "lon": LON, "kind": "indoor_zone"},
                      headers=AUTH).status_code == 422


def test_map_requires_contribution_with_cors(client: TestClient) -> None:
    origin = {"Origin": "https://map.example"}
    r = client.get("/v1/map/aggregates", params=MAP_QUERY, headers=origin)
    assert r.status_code == 401
    assert r.headers["access-control-allow-origin"] == "*"
    preflight = client.options("/v1/map/aggregates", headers={**origin, "Access-Control-Request-Method": "GET"})
    assert preflight.status_code == 200


def test_map_query_validation(client: TestClient) -> None:
    headers = {**AUTH, "X-QC-Access-Receipt": post(client, contribution()).json()["access_receipt"]}
    assert client.get("/v1/map/aggregates", params={"lon": LON}, headers=headers).status_code == 422
    assert client.get("/v1/map/aggregates", params={**MAP_QUERY, "radius_m": 99999}, headers=headers).status_code == 422
    assert client.get("/v1/map/aggregates", params={**MAP_QUERY, "lat": "north"}, headers=headers).status_code == 422


def test_mcp_lists_shared_tools_with_annotations(client: TestClient) -> None:
    tools = {t["name"]: t for t in rpc(client, "tools/list").json()["result"]["tools"]}
    assert SHARED_TOOLS <= set(tools) == TOOLS
    assert tools["query_sound_map"]["annotations"]["readOnlyHint"] is True
    assert tools["find_suitable_places"]["annotations"]["readOnlyHint"] is True
    submit = tools["submit_observation"]["annotations"]
    assert submit["idempotentHint"] is True and submit["destructiveHint"] is False


def test_mcp_submit_query_and_find(client: TestClient) -> None:
    receipt = post(client, contribution(lat=0, lon=0)).json()["access_receipt"]
    for rms in (-50, -48):
        body = contribution(rms=rms, source="simulated")
        out = call(client, "submit_observation", share_consent=True, **body)["structuredContent"]
    assert out["status"] == "accepted"
    sound_map = call(client, "query_sound_map", lat=LAT, lon=LON, access_receipt=receipt)["structuredContent"]
    [agg] = sound_map["aggregates"]
    assert agg["source"] == "simulated" and agg["has_synthetic"] is True
    found = call(client, "find_suitable_places", goal="rest", lat=LAT, lon=LON,
                 access_receipt=receipt)["structuredContent"]
    assert found["no_fit"] is False
    assert "simulated" in found["note"]
    assert found["candidates"][0]["walk"]["source"].startswith("estimate")


def test_mcp_find_no_fit_and_bad_submit(client: TestClient) -> None:
    receipt = post(client, contribution(lat=0, lon=0)).json()["access_receipt"]
    found = call(client, "find_suitable_places", goal="talk", lat=LAT, lon=LON,
                 access_receipt=receipt)["structuredContent"]
    assert found["no_fit"] is True and found["reason"]
    bad = call(client, "submit_observation", **{**contribution(), "id": uid(), "lat": LAT, "lon": None})
    assert bad["isError"] is True
    rejected = call(client, "submit_observation", share_consent=True, **contribution(duration=2))["structuredContent"]
    assert rejected["status"] == "rejected"


def test_responses_match_json_schema(client: TestClient) -> None:
    jsonschema = pytest.importorskip("jsonschema")
    schema = json.loads((Path(__file__).parents[2] / "contracts" / "quiet-compass.schema.json").read_text())

    def check(name: str, instance: Any) -> None:
        jsonschema.validate(instance, {**schema, "$ref": f"#/$defs/{name}"})

    body = contribution()
    check("SharedContribution", body)
    first = post(client, body).json()
    headers = {**AUTH, "X-QC-Access-Receipt": first["access_receipt"]}
    check("ContributionResult", first)
    check("ContributionResult", post(client, contribution(rms=-44)).json())
    check("SoundMapResponse", client.get("/v1/map/aggregates", params=MAP_QUERY, headers=headers).json())
    area = client.put("/v1/areas/zone-a", json={"name": "A", "lat": LAT, "lon": LON, "kind": "indoor_zone"},
                      headers=AUTH)
    check("Area", area.json())


def test_map_view_reads_same_released_device_data_as_mcp(client: TestClient) -> None:
    first = post(client, contribution()).json()
    receipt = first["access_receipt"]
    headers = {"Authorization": f"Bearer {receipt}"}
    assert client.get("/v1/map/view").status_code == 428
    assert client.get("/v1/map/view", headers=AUTH).status_code == 428
    assert client.get("/v1/map/view", headers=headers).json()["aggregates"] == []
    post(client, contribution(rms=-44))
    view = client.get("/v1/map/view", headers=headers)
    tool = call(client, "query_sound_map", lat=37.77, lon=-122.43, radius_m=5000,
                since_minutes=1440, access_receipt=receipt)["structuredContent"]
    assert view.status_code == 200
    assert view.headers["cache-control"] == "no-store"
    assert view.json()["aggregates"] == tool["aggregates"]
    assert len(view.json()["aggregates"]) == 1
    client.app_clock.now += timedelta(minutes=15)
    assert client.get("/v1/map/view", headers=headers).status_code == 428


def test_map_view_excludes_simulated_cohorts(client: TestClient) -> None:
    receipt = post(client, contribution()).json()["access_receipt"]
    for rms in (-50, -48):
        post(client, contribution(rms=rms, source="simulated"))
    response = client.get("/v1/map/view", headers={"Authorization": f"Bearer {receipt}"})
    assert response.status_code == 200
    assert response.json()["aggregates"] == []


def test_public_map_shows_released_measurements_to_any_visitor(client: TestClient) -> None:
    first = post(client, contribution())
    assert first.json()["status"] == "withheld"
    response = client.get("/v1/map/public")
    assert response.status_code == 200
    assert response.json()["aggregates"] == []
    post(client, contribution(rms=-44))
    public = client.get("/v1/map/public")
    assert public.status_code == 200
    [aggregate] = public.json()["aggregates"]
    assert aggregate["n"] == 2
    assert aggregate["source"] == "device"
    assert "access_receipt" not in public.text
    # Other viewers still see the released data after the contributor's pass expires.
    client.app_clock.now += timedelta(minutes=16)
    assert len(client.get("/v1/map/public").json()["aggregates"]) == 1
    assert client.get("/v1/map/view").status_code == 428
    client.app_clock.now += timedelta(hours=25)
    assert client.get("/v1/map/public").json()["aggregates"] == []


def test_public_map_excludes_simulated_measurements(client: TestClient) -> None:
    for rms in (-50, -48):
        post(client, contribution(rms=rms, source="simulated"))
    assert client.get("/v1/map/public").json()["aggregates"] == []
