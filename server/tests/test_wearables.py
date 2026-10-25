from __future__ import annotations

import asyncio
import base64
import hashlib
import json
from datetime import timedelta
from urllib.parse import parse_qs, urlsplit

import httpx2 as httpx
import pytest
from conftest import AUTH, TOKEN, Clock, ts
from cryptography.fernet import Fernet
from starlette.testclient import TestClient
from test_mcp import call

from quiet_compass.app import create_app
from quiet_compass.db import Store
from quiet_compass.settings import Settings


@pytest.fixture
def rig(tmp_path):
    requests = []
    clock = Clock()

    def provider(request):
        requests.append(request)
        if request.url.path == "/oauth/token":
            return httpx.Response(
                200, json={"access_token": "secret-access", "refresh_token": "secret-refresh", "expires_in": 3600}
            )
        if request.url.path == "/oauth/revoke":
            return httpx.Response(200, json={})
        return httpx.Response(
            200,
            json={
                "data": [
                    {
                        "day": "2026-10-24",
                        "score": 82,
                        "steps": 5432,
                        "type": "long_sleep",
                        "total_sleep_duration": 25200,
                    }
                ]
            },
        )

    settings = Settings(
        api_token=TOKEN,
        db_path=tmp_path / "private.db",
        public_url="http://localhost",
        encryption_key=Fernet.generate_key().decode(),
        oura_client_id="fake-client",
        oura_client_secret="fake-client-secret",
    )
    app = create_app(settings, Store(settings.db_path, clock=clock), wearable_transport=httpx.MockTransport(provider))
    with TestClient(app, base_url="http://localhost") as client:
        yield client, app.state.wearables, requests, clock


def start(client):
    link = client.post("/v1/wearables/oura/link", headers=AUTH)
    assert link.status_code == 200
    assert TOKEN not in link.text
    response = client.get(link.json()["connection_url"], follow_redirects=False)
    assert response.status_code == 303
    params = parse_qs(urlsplit(response.headers["location"]).query)
    return params, link.json()["connection_url"]


def connect(client):
    params, _ = start(client)
    response = client.get("/oauth/oura/callback", params={"code": "fake-code", "state": params["state"][0]})
    assert response.status_code == 200
    return params


def health():
    return {
        "source": "apple_health",
        "captured_at": ts(),
        "metrics": [
            {"name": "hrv_sdnn_ms", "value": 34.5, "unit": "ms", "day": "2026-10-24"},
            {"name": "sleep_seconds", "value": 25000, "unit": "seconds", "day": "2026-10-24"},
        ],
    }


def test_oauth_bound_to_browser_pkce_one_use_and_encrypted(rig):
    client, service, requests, _ = rig
    params, link = start(client)
    assert params["scope"] == ["daily"]
    assert params["code_challenge_method"] == ["S256"]
    assert client.get(link, follow_redirects=False).status_code == 400
    # The failed replay clears the cookie; restart the flow for the legitimate browser.
    params, _ = start(client)
    callback = {"state": params["state"][0], "code": "fake-code"}
    assert client.get("/oauth/oura/callback", params=callback).status_code == 200
    exchange = parse_qs(requests[0].content.decode())
    challenge = (
        base64.urlsafe_b64encode(hashlib.sha256(exchange["code_verifier"][0].encode()).digest()).decode().rstrip("=")
    )
    assert challenge == params["code_challenge"][0]
    assert client.get("/oauth/oura/callback", params=callback).status_code == 400
    with service.store._read() as connection:
        row = connection.execute("SELECT value FROM private_state").fetchone()[0]
        assert b"secret-access" not in row and b"secret-refresh" not in row
    assert service.private.read("oura_tokens")["access_token"] == "secret-access"
    assert "secret-access" not in client.get("/v1/wearables/context", headers=AUTH).text


def test_missing_cookie_denied_and_expired_state(rig):
    client, service, requests, clock = rig
    params, _ = start(client)
    client.cookies.clear()
    assert client.get("/oauth/oura/callback", params={"state": params["state"][0], "code": "x"}).status_code == 400
    params, _ = start(client)
    assert (
        client.get("/oauth/oura/callback", params={"state": params["state"][0], "error": "access_denied"}).status_code
        == 400
    )
    params, _ = start(client)
    clock.now += timedelta(minutes=11)
    assert client.get("/oauth/oura/callback", params={"state": params["state"][0], "code": "x"}).status_code == 400
    assert requests == []
    assert not service.context()["oura_connected"]


def test_sync_refresh_and_mcp_only_receive_summaries(rig):
    client, service, requests, clock = rig
    connect(client)
    clock.now += timedelta(hours=2)
    assert client.post("/v1/wearables/oura/sync", headers=AUTH).status_code == 200
    assert len([r for r in requests if r.url.path == "/oauth/token"]) == 2
    context = call(client, "quiet_get_personal_context")["structuredContent"]
    assert context["sources"]["oura"]["metrics"][0]["value"] == 82
    assert "secret-access" not in json.dumps(context)
    # Reopening the persisted encrypted state survives server restarts.
    from quiet_compass.wearables import WearableService

    reopened = WearableService(service.store, service.settings)
    assert reopened.context() == service.context()


def test_concurrent_sync_rotates_refresh_only_once(rig):
    client, service, requests, clock = rig
    connect(client)
    clock.now += timedelta(hours=2)

    async def sync_twice():
        await asyncio.gather(service.sync_oura(), service.sync_oura())

    asyncio.run(sync_twice())
    assert len([r for r in requests if r.url.path == "/oauth/token"]) == 2


def test_health_upload_auth_dates_units_and_delete(rig):
    client, service, _, _ = rig
    assert client.put("/v1/wearables/apple-health", json=health()).status_code == 401
    assert client.put("/v1/wearables/apple-health", json=health(), headers=AUTH).status_code == 200
    context = call(client, "quiet_get_personal_context")["structuredContent"]
    assert context["sources"]["apple_health"]["metrics"][0]["name"] == "hrv_sdnn_ms"
    public_map = client.get("/v1/map/aggregates", params={"lat": 37.78, "lon": -122.42})
    assert public_map.status_code == 401
    assert "hrv_sdnn_ms" not in public_map.text
    bad = health()
    bad["metrics"][0]["unit"] = "bpm"
    assert client.put("/v1/wearables/apple-health", json=bad, headers=AUTH).status_code == 422
    bad = health()
    bad["source"] = "oura"
    assert client.put("/v1/wearables/apple-health", json=bad, headers=AUTH).status_code == 422
    bad = health()
    bad["captured_at"] = "2027-01-01T00:00:00Z"
    assert client.put("/v1/wearables/apple-health", json=bad, headers=AUTH).status_code == 422
    assert client.put("/v1/wearables/apple-health", content=b"x" * 65537, headers=AUTH).status_code == 413
    assert client.delete("/v1/wearables/apple_health", headers=AUTH).status_code == 200
    assert service.context()["sources"] == {}


def test_disconnect_revokes_and_invalidates_pending_flow(rig):
    client, service, requests, _ = rig
    connect(client)
    client.post("/v1/wearables/oura/sync", headers=AUTH)
    params, _ = start(client)
    result = client.delete("/v1/wearables/oura", headers=AUTH)
    assert result.json()["provider_revoked"] is True
    assert requests[-1].url.path == "/oauth/revoke"
    assert client.get("/oauth/oura/callback", params={"state": params["state"][0], "code": "x"}).status_code == 400
    assert service.context()["sources"] == {}
    assert service.private.read("oura_tokens") is None


def test_provider_outage_preserves_old_dates_and_revocation_clears_data(rig):
    client, service, _, clock = rig
    connect(client)
    client.post("/v1/wearables/oura/sync", headers=AUTH)
    previous = service.context()
    service.transport = httpx.MockTransport(lambda _: httpx.Response(503))
    clock.now += timedelta(minutes=1)
    assert client.post("/v1/wearables/oura/sync", headers=AUTH).status_code == 503
    assert service.context() == previous
    clock.now += timedelta(hours=2)
    service.transport = httpx.MockTransport(lambda _: httpx.Response(401))
    assert client.post("/v1/wearables/oura/sync", headers=AUTH).status_code == 401
    assert service.context()["sources"] == {}


def test_unconfigured_is_explicit(client):
    assert client.get("/v1/wearables/context", headers=AUTH).json()["status"] == "not_configured"
    assert client.post("/v1/wearables/oura/link", headers=AUTH).status_code == 503
    assert client.put("/v1/wearables/apple-health", json=health(), headers=AUTH).status_code == 503
