"""Contribution receipts must gate every shared read without exposing personal tools."""
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

import pytest
from conftest import AUTH, NOW, TOKEN, Clock, uid
from starlette.testclient import TestClient
from test_mcp import HEADERS, call, rpc
from test_shared_api import MAP_QUERY, SHARED_TOOLS, post
from test_shared_layer import contribution, make_layer

from quiet_compass.app import create_app
from quiet_compass.db import Store
from quiet_compass.settings import Settings, SettingsError
from quiet_compass.shared_contracts import SharedContribution

SHARED_TOKEN = "shared-only-test-0123456789"
SHARED_AUTH = {"Authorization": f"Bearer {SHARED_TOKEN}"}


def read(client, receipt=None, auth=AUTH):
    headers = {**auth, **({"X-QC-Access-Receipt": receipt} if receipt else {})}
    return client.get("/v1/map/aggregates", params=MAP_QUERY, headers=headers)


def test_receipt_window_and_new_contribution(client, clock):
    assert read(client).status_code == 428
    blocked = call(client, "query_sound_map", lat=37.77, lon=-122.42)
    assert blocked["isError"] and "contribution_required" in str(blocked)
    result = post(client, contribution()).json()
    receipt = result["access_receipt"]
    assert result["status"] == "withheld" and receipt
    assert result["access_expires_at"] == "2026-10-24T21:15:00.000Z"
    for _ in range(3):
        assert read(client, receipt).status_code == 200
    clock.now = NOW + timedelta(minutes=15, microseconds=-1)
    assert read(client, receipt).status_code == 200
    clock.now += timedelta(microseconds=1)
    assert read(client, receipt).status_code == 428
    for tool, args in (("query_sound_map", {}), ("find_suitable_places", {"goal": "work"})):
        assert call(client, tool, lat=37.77, lon=-122.42, access_receipt=receipt, **args)["isError"]
    fresh = contribution(minutes_ago=-14, rms=-43)
    renewed = post(client, fresh).json()
    assert renewed["access_receipt"] != receipt
    assert read(client, renewed["access_receipt"]).status_code == 200


def test_replay_does_not_extend_window_or_inflate_cohort(client, clock):
    body = contribution()
    first = post(client, body).json()
    clock.now += timedelta(minutes=10)
    for repeated in (body, {**body, "id": uid()}):
        result = post(client, repeated).json()
        assert result["status"] == "withheld"
        assert result["access_receipt"] == first["access_receipt"]
        assert result["access_expires_at"] == first["access_expires_at"]
    clock.now += timedelta(minutes=6)
    assert read(client, first["access_receipt"]).status_code == 428
    replay = post(client, {**body, "id": uid()}).json()
    assert replay["access_expires_at"] == first["access_expires_at"]
    assert read(client, replay["access_receipt"]).status_code == 428


def test_changed_id_payload_cannot_upgrade_or_renew(client):
    body = contribution(source="simulated")
    assert post(client, body).json()["access_receipt"] is None
    changed = post(client, {**body, "source": "device"}).json()
    assert changed["status"] == "rejected" and changed["access_receipt"] is None
    body = contribution(rms=-42)
    first = post(client, body).json()
    changed = post(client, {**body, "measurement": {**body["measurement"], "rms_dbfs": -41}}).json()
    assert changed["status"] == "rejected" and changed["access_receipt"] is None
    assert read(client, first["access_receipt"]).status_code == 200


@pytest.mark.parametrize("kwargs", [
    {"source": "simulated"}, {"minutes_ago": 16}, {"minutes_ago": -10},
    {"duration": 2}, {"clipping": True}, {"rms": -130},
])
def test_ineligible_summaries_do_not_unlock(client, kwargs):
    result = post(client, contribution(**kwargs)).json()
    assert result["access_receipt"] is None and result["access_expires_at"] is None
    assert read(client).status_code == 428


def test_consent_required_before_storing(client):
    body = contribution()
    result = client.post("/v1/contributions", headers=AUTH,
                         json={"contract_version": 1, "contribution": body}).json()
    assert result["status"] == "rejected" and result["access_receipt"] is None
    result = call(client, "submit_observation", **body)["structuredContent"]
    assert result["status"] == "rejected"
    accepted = call(client, "submit_observation", share_consent=True, **body)["structuredContent"]
    assert accepted["status"] == "withheld" and accepted["access_receipt"]
    assert read(client, accepted["access_receipt"]).status_code == 200


def test_receipt_forgery_and_public_bypass_rejected(client):
    result = post(client, contribution()).json()
    receipt = result["access_receipt"]
    assert read(client, receipt, auth={}).status_code == 401
    for wrong in (uid(), receipt + "x", "x" * 129, TOKEN):
        assert read(client, wrong).status_code == 428
    assert client.get("/v1/map/aggregates", headers=AUTH,
                      params={**MAP_QUERY, "access_receipt": receipt}).status_code == 428
    assert read(client, receipt).headers["cache-control"] == "no-store"


def test_receipt_survives_restart_and_expires(tmp_path):
    clock = Clock()
    settings = Settings(api_token=TOKEN, shared_api_token=SHARED_TOKEN, db_path=tmp_path / "restart.db")
    def app():
        return create_app(settings, Store(settings.db_path, clock=clock))
    with TestClient(app(), base_url="http://localhost") as client:
        receipt = post(client, contribution(), headers=SHARED_AUTH).json()["access_receipt"]
    with TestClient(app(), base_url="http://localhost") as client:
        assert read(client, receipt, SHARED_AUTH).status_code == 200
        clock.now += timedelta(minutes=15)
        assert read(client, receipt, SHARED_AUTH).status_code == 428


def test_shared_endpoint_is_isolated(tmp_path, clock):
    settings = Settings(api_token=TOKEN, shared_api_token=SHARED_TOKEN, db_path=tmp_path / "isolated.db")
    with TestClient(create_app(settings, Store(settings.db_path, clock=clock)), base_url="http://localhost") as client:
        headers = {**HEADERS, **SHARED_AUTH}
        init = rpc(client, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                   "clientInfo": {"name": "external-agent", "version": "1"}}, headers=headers, path="/mcp/shared")
        assert "15 minutes" in init.json()["result"]["instructions"]
        listed = rpc(client, "tools/list", headers=headers, path="/mcp/shared")
        assert {tool["name"] for tool in listed.json()["result"]["tools"]} == SHARED_TOOLS
        result = rpc(client, "tools/call", {"name": "submit_observation", "arguments": {
            **contribution(), "share_consent": True}}, headers=headers, path="/mcp/shared").json()["result"]
        receipt = result["structuredContent"]["access_receipt"]
        assert read(client, receipt, SHARED_AUTH).status_code == 200
        assert rpc(client, "tools/list", headers=headers).status_code == 401
        assert client.get("/v1/wearables/context", headers=SHARED_AUTH).status_code == 401
        assert client.put("/v1/areas/secret-zone", headers=SHARED_AUTH, json={}).status_code == 401
        private = rpc(client, "tools/call", {"name": "quiet_get_personal_context", "arguments": {}},
                      headers=headers, path="/mcp/shared").json()["result"]
        assert private["isError"]
        result = rpc(client, "tools/call", {"name": "query_sound_map", "arguments": {
            **MAP_QUERY, "access_receipt": receipt}}, headers=headers, path="/mcp/shared").json()["result"]
        assert "aggregates" in result["structuredContent"]


def test_unconfigured_endpoint_fails_closed_and_status_has_no_secrets(client):
    assert rpc(client, "tools/list", path="/mcp/shared").status_code == 503
    response = client.get("/v1/exchange/status")
    assert response.json()["shared_endpoint_enabled"] is False
    assert response.json()["access_window_seconds"] == 900
    assert TOKEN not in response.text
    with pytest.raises(SettingsError):
        Settings(api_token=TOKEN, shared_api_token=TOKEN)
    with pytest.raises(SettingsError):
        Settings(api_token=TOKEN, contribution_retention_hours=0.25)


def test_concurrent_duplicate_submission_has_one_deadline(tmp_path, clock):
    layer = make_layer(tmp_path, clock)
    bodies = [SharedContribution.model_validate(contribution()) for _ in range(6)]
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(lambda body: layer.submit_shared(body, True), bodies))
    assert {r.status for r in results} == {"withheld"}
    assert len({r.access_receipt for r in results}) == 1
    assert len({r.access_expires_at for r in results}) == 1
    assert results[0].access_receipt
