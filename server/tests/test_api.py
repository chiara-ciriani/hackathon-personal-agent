from __future__ import annotations

from typing import Any

from conftest import AUTH, observation, session_body, uid
from starlette.testclient import TestClient


def test_healthz_is_open(client: TestClient) -> None:
    assert client.get("/healthz").json() == {"ok": True}


def test_rest_requires_token(client: TestClient) -> None:
    sid = uid()
    assert client.put(f"/v1/sessions/{sid}", json=session_body(sid)).status_code == 401
    bad = {"Authorization": "Bearer nope"}
    assert client.put(f"/v1/sessions/{sid}", json=session_body(sid), headers=bad).status_code == 401


def test_session_upsert_returns_session(client: TestClient) -> None:
    sid = uid()
    r = client.put(f"/v1/sessions/{sid}", json=session_body(sid), headers=AUTH)
    assert r.status_code == 200
    assert r.json()["id"] == sid
    assert r.json()["started_at"].endswith("Z")


def test_session_id_mismatch_is_422(client: TestClient) -> None:
    r = client.put(f"/v1/sessions/{uid()}", json=session_body(uid()), headers=AUTH)
    assert r.status_code == 422


def test_unknown_field_is_rejected(client: TestClient) -> None:
    sid = uid()
    body = session_body(sid)
    body["session"]["extra"] = 1
    assert client.put(f"/v1/sessions/{sid}", json=body, headers=AUTH).status_code == 422


def test_observation_ingest_is_idempotent(client: TestClient, venue: dict[str, Any]) -> None:
    sid = venue["session_id"]
    batch = {"contract_version": 1, "observations": [observation(sid, -45), observation(sid, -44)]}
    first = client.post("/v1/observations", json=batch, headers=AUTH).json()
    second = client.post("/v1/observations", json=batch, headers=AUTH).json()
    assert first == {"accepted": 2, "duplicates": 0}
    assert second == {"accepted": 0, "duplicates": 2}


def test_records_for_unknown_session_are_409(client: TestClient) -> None:
    batch = {"contract_version": 1, "observations": [observation(uid(), -45)]}
    assert client.post("/v1/observations", json=batch, headers=AUTH).status_code == 409


def test_positive_level_is_rejected(client: TestClient, venue: dict[str, Any]) -> None:
    batch = {"contract_version": 1, "observations": [observation(venue["session_id"], 3)]}
    assert client.post("/v1/observations", json=batch, headers=AUTH).status_code == 422


def test_naive_timestamp_is_rejected(client: TestClient, venue: dict[str, Any]) -> None:
    obs = observation(venue["session_id"], -40)
    obs["t"] = "2026-10-24T20:00:00"
    r = client.post("/v1/observations", json={"contract_version": 1, "observations": [obs]}, headers=AUTH)
    assert r.status_code == 422


def test_place_resend_with_new_label_updates(client: TestClient, venue: dict[str, Any]) -> None:
    quiet = dict(venue["quiet"])
    same = client.post("/v1/places", json={"contract_version": 1, "places": [quiet]}, headers=AUTH).json()
    assert same == {"accepted": 0, "duplicates": 1}
    quiet["label"] = "Window corner"
    changed = client.post("/v1/places", json={"contract_version": 1, "places": [quiet]}, headers=AUTH).json()
    assert changed == {"accepted": 1, "duplicates": 0}


def test_crumb_and_feedback_ingest(client: TestClient, venue: dict[str, Any]) -> None:
    sid = venue["session_id"]
    fb = {"id": uid(), "session_id": sid, "place_id": venue["quiet"]["id"], "goal": "rest",
          "verdict": "good", "feel": "calm", "t": "2026-10-24T20:55:00Z"}
    body = {"contract_version": 1, "feedback": [fb, fb]}
    assert client.post("/v1/feedback", json=body, headers=AUTH).json() == {"accepted": 1, "duplicates": 1}
    wrong = {"contract_version": 2, "crumbs": []}
    assert client.post("/v1/crumbs", json=wrong, headers=AUTH).status_code == 422


def test_guidance_absent_is_204(client: TestClient, venue: dict[str, Any]) -> None:
    r = client.get(f"/v1/sessions/{venue['session_id']}/guidance", headers=AUTH)
    assert r.status_code == 204


def test_guidance_status_without_guidance_is_404(client: TestClient, venue: dict[str, Any]) -> None:
    r = client.post(
        f"/v1/sessions/{venue['session_id']}/guidance/status",
        json={"contract_version": 1, "status": "arrived"}, headers=AUTH,
    )
    assert r.status_code == 404
