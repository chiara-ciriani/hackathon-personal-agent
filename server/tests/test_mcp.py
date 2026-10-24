"""MCP tools exercised over HTTP JSON-RPC against /mcp, as a remote connector would."""

from __future__ import annotations

from typing import Any

import pytest
from conftest import AUTH, TOKEN
from starlette.testclient import TestClient

from quiet_compass.app import create_app
from quiet_compass.settings import Settings

HEADERS = {
    **AUTH,
    "Accept": "application/json, text/event-stream",
    "MCP-Protocol-Version": "2025-06-18",
}
TOOLS = {
    "quiet_get_context", "quiet_find_space", "quiet_start_guidance", "quiet_record_feedback",
    "quiet_get_personal_context", "quiet_get_sound_map",
}
TOOLS |= {"query_sound_map", "find_suitable_places", "submit_observation"}  # shared sound layer
TOOLS |= {"connect_phone", "request_phone_measurement", "phone_measurement_status", "send_phone_recommendation"}


def rpc(client: TestClient, method: str, params: dict[str, Any] | None = None,
        headers: dict[str, str] = HEADERS, path: str = "/mcp") -> Any:
    body: dict[str, Any] = {"jsonrpc": "2.0", "id": 1, "method": method}
    if params is not None:
        body["params"] = params
    return client.post(path, json=body, headers=headers)


def call(client: TestClient, name: str, **arguments: Any) -> dict[str, Any]:
    r = rpc(client, "tools/call", {"name": name, "arguments": arguments})
    assert r.status_code == 200, r.text
    return r.json()["result"]


def test_initialize_and_list_tools(client: TestClient) -> None:
    init = rpc(client, "initialize", {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "test", "version": "0"},
    })
    assert init.status_code == 200
    assert init.json()["result"]["serverInfo"]["name"] == "quiet-compass"
    tools = {t["name"]: t for t in rpc(client, "tools/list").json()["result"]["tools"]}
    assert set(tools) == TOOLS
    assert tools["quiet_get_context"]["annotations"]["readOnlyHint"] is True
    guidance = tools["quiet_start_guidance"]["annotations"]
    assert guidance["idempotentHint"] is True and guidance["destructiveHint"] is False


def test_mcp_requires_token(client: TestClient) -> None:
    headers = {k: v for k, v in HEADERS.items() if k != "Authorization"}
    assert rpc(client, "tools/list", headers=headers).status_code == 401


def test_mcp_rejects_unknown_host(client: TestClient) -> None:
    assert rpc(client, "tools/list", headers={**HEADERS, "Host": "evil.example"}).status_code == 421


def test_context_without_session(client: TestClient) -> None:
    result = call(client, "quiet_get_context")
    assert "No recording session" in result["structuredContent"]["message"]


def test_context_overview_is_concise(client: TestClient, venue: dict[str, Any]) -> None:
    ctx = call(client, "quiet_get_context")["structuredContent"]
    labels = {p["label"] for p in ctx["places"]}
    assert labels == {"Quiet corner by the windows", "Side hallway", "Coffee bar"}
    assert all("place_id" not in p for p in ctx["places"])
    assert ctx["now"]["level_dbfs_rel"] == -31
    quiet = next(p for p in ctx["places"] if p["label"].startswith("Quiet"))
    assert quiet["last_measured_min_ago"] == 4.0


def test_context_place_tracks_changes(client: TestClient, venue: dict[str, Any]) -> None:
    pid = venue["quiet"]["id"]
    first = call(client, "quiet_get_context", place_id=pid, response_format="detailed")["structuredContent"]
    assert first["history"]["count"] == 3
    assert first["changes_since_last_call"]["first_call"] is True
    assert first["route"] == {"walked_distance_m": 25.0, "walk_minutes": 0.5, "source": "path"}
    second = call(client, "quiet_get_context", place_id=pid)["structuredContent"]
    assert second["changes_since_last_call"]["new_observations"] == 0


def test_find_space_ranks_quiet_corner_first(client: TestClient, venue: dict[str, Any]) -> None:
    result = call(client, "quiet_find_space", goal="rest", duration_minutes=10,
                  return_by="2026-10-24T21:30:00Z")["structuredContent"]
    assert result["no_fit"] is False
    top = result["results"][0]
    assert top["label"] == "Quiet corner by the windows"
    assert top["place_id"] == venue["quiet"]["id"]
    assert set(top["score"]) == {"S", "F_measured", "F_prior", "freshness_w", "distance_penalty"}


def test_find_space_no_fit_names_relax(client: TestClient, venue: dict[str, Any]) -> None:
    # Remove the only step-free option to exercise an unsatisfied requirement.
    hall = {**venue["hall"], "tags": []}
    updated = client.post("/v1/places", json={"contract_version": 1, "places": [hall]}, headers=AUTH)
    assert updated.status_code == 200
    result = call(client, "quiet_find_space", goal="rest", duration_minutes=10,
                  return_by="2026-10-24T21:30:00Z", needs=["step_free"])["structuredContent"]
    assert result["no_fit"] is True
    assert result["relax"] == "step_free"
    assert len(result["closest"]) <= 1


def test_find_space_respects_available_step_free_option(client: TestClient, venue: dict[str, Any]) -> None:
    result = call(client, "quiet_find_space", goal="rest", duration_minutes=10,
                  return_by="2026-10-24T21:30:00Z", needs=["step_free"])["structuredContent"]
    assert result["no_fit"] is False
    assert result["results"][0]["place_id"] == venue["hall"]["id"]


def test_find_space_past_return_by_is_error(client: TestClient, venue: dict[str, Any]) -> None:
    result = call(client, "quiet_find_space", goal="rest", duration_minutes=10,
                  return_by="2026-10-24T20:00:00Z")
    assert result["isError"] is True
    assert "not in the future" in result["content"][0]["text"]


def test_find_space_unknown_goal_is_error(client: TestClient, venue: dict[str, Any]) -> None:
    result = call(client, "quiet_find_space", goal="party", duration_minutes=10,
                  return_by="2026-10-24T21:30:00Z")
    assert result["isError"] is True


def test_guidance_flow(client: TestClient, venue: dict[str, Any]) -> None:
    sid, pid = venue["session_id"], venue["quiet"]["id"]
    for _ in range(2):  # idempotent
        out = call(client, "quiet_start_guidance", place_id=pid, reason="Quietest spot, 4 min ago")
        assert out["structuredContent"]["status"] == "active"
    g = client.get(f"/v1/sessions/{sid}/guidance", headers=AUTH)
    assert g.status_code == 200
    assert g.json()["target_label"] == "Quiet corner by the windows"
    assert g.json()["updated_at"].endswith("Z")
    done = client.post(f"/v1/sessions/{sid}/guidance/status",
                       json={"contract_version": 1, "status": "arrived"}, headers=AUTH)
    assert done.json()["status"] == "arrived"
    assert client.get(f"/v1/sessions/{sid}/guidance", headers=AUTH).status_code == 204


def test_unknown_place_is_tool_error(client: TestClient, venue: dict[str, Any]) -> None:
    result = call(client, "quiet_start_guidance", place_id="nope")
    assert result["isError"] is True


def test_record_feedback_is_visible_in_context(client: TestClient, venue: dict[str, Any]) -> None:
    pid = venue["hall"]["id"]
    out = call(client, "quiet_record_feedback", place_id=pid, goal="talk", verdict="good", feel="calm")
    assert out["structuredContent"]["stored"] is True
    ctx = call(client, "quiet_get_context", place_id=pid)["structuredContent"]
    assert ctx["feedback"][0]["verdict"] == "good"


@pytest.mark.parametrize("secret_path_ok", [True])
def test_path_secret_mode(tmp_path: Any, secret_path_ok: bool) -> None:
    secret = "a" * 24
    settings = Settings(api_token=TOKEN, db_path=tmp_path / "s.db", mcp_path_secret=secret)
    with TestClient(create_app(settings), base_url="http://localhost") as c:
        no_auth = {k: v for k, v in HEADERS.items() if k != "Authorization"}
        assert rpc(c, "tools/list", headers=no_auth, path=f"/mcp/{secret}").status_code == 200
        assert rpc(c, "tools/list", headers=HEADERS, path="/mcp").status_code == 404


def test_city_tool_registered_only_when_enabled(tmp_path: Any) -> None:
    settings = Settings(api_token=TOKEN, db_path=tmp_path / "c.db", city_layer_enabled=True)
    with TestClient(create_app(settings), base_url="http://localhost") as c:
        names = {t["name"] for t in rpc(c, "tools/list").json()["result"]["tools"]}
    assert names == TOOLS | {"quiet_city_noise_reports", "quiet_sf_layers"}
