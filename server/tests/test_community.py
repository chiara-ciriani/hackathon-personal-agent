"""Community phone summaries reach the same shared data used by MCP and other map users."""
from conftest import AUTH
from test_mcp import call
from test_shared_api import post
from test_shared_layer import LAT, contribution


def summary(**changes):
    body = contribution(duration=30, **changes)
    body["quality"]["capture_profile"] = "qc-community-v1:test-phone:48000:1"
    return {"contract_version": 1, "share_consent": True, "contribution": body}


def test_native_summary_reaches_other_contributors_and_mcp(client):
    other_receipt = post(client, contribution(lat=0, lon=0)).json()["access_receipt"]
    first = client.post("/v1/community/contributions", json=summary())
    assert first.status_code == 200 and first.json()["status"] == "withheld"
    own_receipt = first.json()["access_receipt"]
    second = client.post("/v1/community/contributions", json=summary(rms=-44))
    assert second.json()["status"] == "accepted"
    view = client.get("/v1/map/view", headers={"Authorization": f"Bearer {other_receipt}"}).json()
    assert len(view["aggregates"]) == 1
    assert view["aggregates"][0]["source"] == "device"
    assert view["aggregates"][0]["n"] == 2
    assert round(view["aggregates"][0]["lat"], 3) == round(LAT, 3)
    result = call(client, "query_sound_map", lat=37.77, lon=-122.43, radius_m=5000,
                  since_minutes=1440, access_receipt=own_receipt)["structuredContent"]
    assert view["aggregates"] == result["aggregates"]
    assert client.get("/v1/map/aggregates", headers=AUTH).status_code == 428


def test_public_sharing_requires_explicit_real_geolocated_summary(client):
    for change in ["consent", "source", "coords", "duration", "clipping", "extra"]:
        body = summary()
        c = body["contribution"]
        if change == "consent":
            body["share_consent"] = False
        if change == "source":
            c["source"] = "simulated"
        if change == "coords":
            c["lat"], c["lon"] = 0, 0
        if change == "duration":
            c["duration_seconds"] = 1
        if change == "clipping":
            c["quality"]["clipping_detected"] = True
        if change == "extra":
            c["raw_audio"] = "not accepted"
        assert client.post("/v1/community/contributions", json=body).status_code == 422


def test_community_retries_do_not_duplicate_or_extend_access(client):
    body = summary()
    first = client.post("/v1/community/contributions", json=body).json()
    retry = client.post("/v1/community/contributions", json=body).json()
    assert retry["access_receipt"] == first["access_receipt"]
    assert retry["access_expires_at"] == first["access_expires_at"]
    assert retry["status"] == "withheld"


def test_community_ingestion_is_bounded(client):
    assert client.post("/v1/community/contributions", content=b'x'*8193).status_code == 413
    for _ in range(29):
        assert client.post("/v1/community/contributions", json={}).status_code == 422
    assert client.post("/v1/community/contributions", json=summary()).status_code == 429
