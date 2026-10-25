"""Native app → scoped phone bridge → actual acoustic analysis → agent advice.

All readings here are synthetic protocol fixtures, not evidence from a physical phone.
"""
from datetime import timedelta

from conftest import uid
from test_mcp import call
from test_phone_bridge import CONSENT, connect, phone, status

NATIVE = {"microphone_consent": True, "spatial_consent": True}


def request_walk(client, agent, duration=30):
    return call(client, "request_phone_measurement", phone_session_id=agent,
                mode="walk", duration_seconds=duration)


def payload(job, clock, location=None):
    walk = {
        "started_at": clock.now.isoformat(), "capture_profile": "ios-walk-v1:fixture:48000:1",
        "clipping_detected": False,
        "samples": [{"t": i * 2, "x": i * .6, "z": 0, "level_dbfs": -55 + i * 1.5,
                     "tracking": "normal"} for i in range(1, 15)],
    }
    if location is not None:
        walk["location"] = location
    return {"request_id": job, "walk": walk}


def ready(client):
    agent, token = connect(client)
    assert phone(client, token, "native-consent", NATIVE).status_code == 200
    return agent, token


def test_native_consent_client_isolation_and_no_unsolicited_walk(client):
    agent, token = connect(client)
    assert request_walk(client, agent)["isError"]
    assert phone(client, token, "native-consent", {**NATIVE, "spatial_consent": False}).status_code == 422
    assert phone(client, token, "native-consent", NATIVE).status_code == 200
    assert status(client, agent)["modes"] == ["walk"]
    assert phone(client, token, "poll").status_code == 403
    assert phone(client, token, "consent", CONSENT).status_code == 409
    assert call(client, "request_phone_measurement", phone_session_id=agent)["isError"]
    assert phone(client, token, "native-result", {"request_id": uid(), "error": "failed"}).status_code == 409


def test_full_walk_analysis_advice_retry_and_no_shared_access(client, clock):
    agent, token = ready(client)
    requested = request_walk(client, agent)["structuredContent"]
    job = requested["request_id"]
    assert phone(client, token, "native-poll").json()["mode"] == "walk"
    body = payload(job, clock)
    clock.now += timedelta(seconds=30)
    assert phone(client, token, "native-result", body).json()["status"] == "complete"
    result = status(client, agent)["job"]
    assert result["walk"]["sample_count"] == 14
    assert -53 < result["walk"]["analysis"]["mean_dbfs"] < -34
    assert result["walk"]["analysis"]["variation_db"] > 10
    assert "contribution_result" not in result
    assert call(client, "query_sound_map", lat=37.77, lon=-122.42)["isError"]
    assert phone(client, token, "native-result", body).json()["status"] == "complete"
    body["walk"]["samples"][0]["level_dbfs"] = -80
    assert phone(client, token, "native-result", body).status_code == 409
    advice = call(client, "send_phone_recommendation", phone_session_id=agent,
                  message="A measured corner was quieter. Check the path before moving.", action="move", spot_index=0)
    assert not advice.get("isError"), advice
    delivered = phone(client, token, "native-poll").json()["recommendation"]
    assert delivered["destination"]["request_id"] == job
    assert delivered["destination"]["kind"] == "room"
    assert call(client, "send_phone_recommendation", phone_session_id=agent,
                message="Guess", action="move", spot_index=90)["isError"]
    phone(client, token, "disconnect")
    assert phone(client, token, "native-poll").status_code == 410


def test_native_location_is_private_optional_and_coarsened(client, clock):
    agent, token = connect(client)
    assert phone(client, token, "native-consent", NATIVE).status_code == 200
    job = request_walk(client, agent)["structuredContent"]["request_id"]
    phone(client, token, "native-poll")
    denied = payload(job, clock, {"lat": 37.774912, "lon": -122.419486})
    clock.now += timedelta(seconds=30)
    assert phone(client, token, "native-result", denied).status_code == 422

    phone(client, token, "disconnect")
    agent, token = connect(client)
    assert phone(client, token, "native-consent", {**NATIVE, "location_consent": True}).status_code == 200
    job = request_walk(client, agent)["structuredContent"]["request_id"]
    phone(client, token, "native-poll")
    result = payload(job, clock, {"lat": 37.774912, "lon": -122.419486})
    clock.now += timedelta(seconds=30)
    response = phone(client, token, "native-result", result)
    assert response.status_code == 200, response.text
    location = status(client, agent)["job"]["walk"]["location"]
    assert location == {"lat": 37.775, "lon": -122.419, "precision": "approximately_100m"}
    assert "contribution_result" not in status(client, agent)["job"]


def test_native_rejects_replay_audio_clipping_and_stale_or_limited_samples(client, clock):
    agent, token = ready(client)
    job = request_walk(client, agent)["structuredContent"]["request_id"]
    body = payload(job, clock)
    assert phone(client, token, "native-result", body).status_code == 409
    phone(client, token, "native-poll")
    assert phone(client, token, "native-result", body).status_code == 422  # too early
    clock.now += timedelta(seconds=30)
    for key, value in (("raw_audio", "no"), ("clipping_detected", True)):
        invalid = {**body, "walk": {**body["walk"], key: value}}
        assert phone(client, token, "native-result", invalid).status_code == 422
    invalid = {**body, "walk": {**body["walk"], "samples": [{**s, "tracking": "limited"}
                                                              for s in body["walk"]["samples"]]}}
    assert phone(client, token, "native-result", invalid).status_code == 422
    clock.now += timedelta(seconds=61)
    assert phone(client, token, "native-result", body).status_code == 409


def test_native_request_duration_heartbeat_and_browser_separation(client, clock):
    agent, token = ready(client)
    assert request_walk(client, agent, 181)["isError"]
    requested = request_walk(client, agent, 120)["structuredContent"]
    assert request_walk(client, agent, 120)["structuredContent"]["request_id"] == requested["request_id"]
    phone(client, token, "native-poll")
    clock.now += timedelta(seconds=80)
    phone(client, token, "native-poll")
    assert status(client, agent)["job"]["state"] == "measuring"
    clock.now += timedelta(seconds=101)
    assert status(client, agent)["job"]["state"] == "failed"
    other_agent, browser = connect(client)
    phone(client, browser, "consent", CONSENT)
    assert request_walk(client, other_agent)["isError"]
    assert phone(client, browser, "native-poll").status_code == 403
    assert phone(client, browser, "native-consent", NATIVE).status_code == 409
