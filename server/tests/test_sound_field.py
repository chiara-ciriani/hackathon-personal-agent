"""The sound field fills in where the phone measured and stays unknown everywhere else."""

from __future__ import annotations

from typing import Any

from conftest import AUTH, TOKEN, Clock, observation, session_body, uid
from starlette.testclient import TestClient
from test_mcp import call

from quiet_compass.app import create_app
from quiet_compass.db import Store
from quiet_compass.settings import Settings
from quiet_compass.sound_field import FieldConfig, Sample, build_field


def cell_at(field: Any, x: float, z: float) -> Any:
    return min(field.cells, key=lambda c: (c.x - x) ** 2 + (c.z - z) ** 2)


def test_no_positioned_samples_gives_no_field() -> None:
    assert build_field([]) is None


def test_quiet_and_loud_corners_are_where_they_were_measured() -> None:
    samples = [Sample(0, 0, -50, 1), Sample(0.5, 0, -49, 1), Sample(8, 0, -28, 1), Sample(8.5, 0, -27, 1)]
    field = build_field(samples, user=(4, 0))
    assert field is not None
    assert cell_at(field, 0, 0).level_db < -46
    assert cell_at(field, 8, 0).level_db > -31
    spot = field.quiet_spots[0]
    assert spot.x < 2 and spot.distance_m is not None and 2 < spot.distance_m < 5
    assert field.level_range_db == (-50, -27)


def test_walked_but_unmeasured_area_is_unknown_and_never_a_quiet_spot() -> None:
    path = [(float(x), 0.0) for x in range(21)]
    field = build_field([Sample(0, 0, -45, 1)], path=path)
    assert field is not None
    far = cell_at(field, 20, 0)
    assert far.level_db is None and far.confidence == 0
    assert all(s.x < 4 for s in field.quiet_spots)


def test_quiet_spots_sit_on_measured_ground_not_past_the_edge() -> None:
    field = build_field([Sample(0, 0, -50, 1), Sample(6, 0, -30, 1)])
    assert field is not None
    assert all(abs(s.x) <= 1.0 or abs(s.x - 6) <= 1.0 for s in field.quiet_spots)


def test_newer_reading_outweighs_older_one_at_the_same_spot() -> None:
    field = build_field([Sample(0, 0, -30, 60), Sample(0, 0, -50, 1)])
    assert field is not None
    assert cell_at(field, 0, 0).level_db < -45


def test_more_readings_raise_confidence() -> None:
    one = build_field([Sample(0, 0, -40, 0)])
    three = build_field([Sample(0, 0, -40, 0), Sample(0.2, 0, -40, 0), Sample(0, 0.2, -40, 0)])
    assert one is not None and three is not None
    assert cell_at(three, 0, 0).confidence > cell_at(one, 0, 0).confidence


def test_large_spaces_use_bigger_cells_instead_of_huge_grids() -> None:
    cfg = FieldConfig(max_cells=400)
    field = build_field([Sample(0, 0, -40, 0), Sample(60, 40, -40, 0)], cfg=cfg)
    assert field is not None
    assert field.cols * field.rows <= 400 and field.cell_m > cfg.cell_m


# --- endpoint and tool -------------------------------------------------------------------


def walked_session(client: TestClient) -> str:
    """Readings along x: quiet near x=0, loud near x=10; crumbs walk on to x=20."""
    sid = uid()
    client.put(f"/v1/sessions/{sid}", json=session_body(sid), headers=AUTH)
    crumbs = [
        {"id": uid(), "session_id": sid, "seq": i, "position": {"x": float(i), "z": 0.0},
         "heading_rad": 0.0, "t": "2026-10-24T20:40:00Z", "tracking": "normal"}
        for i in range(21)
    ]
    client.post("/v1/crumbs", json={"contract_version": 1, "crumbs": crumbs}, headers=AUTH)
    obs = []
    for x, level in ((0, -50), (1, -49), (9, -30), (10, -29)):
        o = observation(sid, level, minutes_ago=2)
        o["position"] = {"x": float(x), "z": 0.0}
        obs.append(o)
    client.post("/v1/observations", json={"contract_version": 1, "observations": obs}, headers=AUTH)
    return sid


def test_session_field_requires_token(client: TestClient) -> None:
    sid = walked_session(client)
    assert client.get(f"/v1/sessions/{sid}/sound_field").status_code == 401


def test_session_field_shows_measured_cells_and_keeps_the_rest_unknown(client: TestClient) -> None:
    sid = walked_session(client)
    body = client.get(f"/v1/sessions/{sid}/sound_field", headers=AUTH).json()
    assert len(body["cells"]) == body["cols"] * body["rows"]
    assert body["level_range_db"] == [-50, -29]
    assert len(body["samples"]) == 4 and len(body["path"]) == 21
    assert body["quiet_spots"][0]["x"] < 2
    far = min(body["cells"], key=lambda c: (c["x"] - 20) ** 2 + c["z"] ** 2)
    assert far["level_db"] is None


def test_observations_without_position_borrow_their_place(client: TestClient, venue: dict[str, Any]) -> None:
    body = client.get(f"/v1/sessions/{venue['session_id']}/sound_field", headers=AUTH).json()
    assert body["samples"] and body["quiet_spots"][0]["x"] < 4  # the quiet corner sits at x=0


def test_unknown_session_is_404(client: TestClient) -> None:
    assert client.get(f"/v1/sessions/{uid()}/sound_field", headers=AUTH).status_code == 404


def test_venue_field_is_private_unless_enabled(client: TestClient) -> None:
    walked_session(client)
    assert client.get("/v1/venue/sound_field").status_code == 404


def test_venue_field_when_enabled(tmp_path: Any) -> None:
    settings = Settings(api_token=TOKEN, db_path=tmp_path / "qc.db", public_venue_field=True)
    app = create_app(settings, Store(settings.db_path, clock=Clock()))
    with TestClient(app, base_url="http://localhost") as client:
        walked_session(client)
        r = client.get("/v1/venue/sound_field", headers={"Origin": "https://example.org"})
        assert r.status_code == 200
        assert r.headers["access-control-allow-origin"] == "*"
        assert r.json()["quiet_spots"]


def test_sound_map_tool_reports_quiet_spots(client: TestClient) -> None:
    walked_session(client)
    data = call(client, "quiet_get_sound_map")["structuredContent"]
    assert data["measured_spots"] == 4
    assert data["quiet_spots"][0]["x"] < 2
    assert "unknown, not quiet" in data["note"]
