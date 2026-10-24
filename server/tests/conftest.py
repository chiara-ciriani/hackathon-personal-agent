from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import pytest
from starlette.testclient import TestClient

from quiet_compass.app import create_app
from quiet_compass.contracts import format_utc
from quiet_compass.db import Store
from quiet_compass.settings import Settings

TOKEN = "test-token-0123456789"
AUTH = {"Authorization": f"Bearer {TOKEN}"}
NOW = datetime(2026, 10, 24, 21, 0, tzinfo=UTC)


class Clock:
    def __init__(self, now: datetime = NOW) -> None:
        self.now = now

    def __call__(self) -> datetime:
        return self.now


def ts(minutes_ago: float = 0.0) -> str:
    return format_utc(NOW - timedelta(minutes=minutes_ago))


def uid() -> str:
    return str(uuid.uuid4())


def session_body(session_id: str) -> dict[str, Any]:
    return {
        "contract_version": 1,
        "session": {
            "id": session_id,
            "name": "Test hall",
            "started_at": ts(60),
            "device_profile": {
                "model": "iPhone17,1",
                "os_version": "26.1",
                "capture_mode": "C",
                "audio_session_mode": "measurement",
                "sample_rate_hz": 48000,
                "app_version": "0.1",
            },
        },
    }


def observation(session_id: str, level: float, minutes_ago: float = 1, place_id: str | None = None,
                spread: float = 4, peaks: float = 1, speech: float | None = 0.1) -> dict[str, Any]:
    return {
        "id": uid(), "session_id": session_id, "t": ts(minutes_ago), "duration_s": 5,
        "place_id": place_id, "level_dbfs_rel": level, "spread_db": spread,
        "peaks_per_min": peaks, "speech_share": speech, "tracking": "normal",
    }


def place(session_id: str, label: str, x: float, tags: list[str], crumb_id: str | None = None) -> dict[str, Any]:
    return {
        "id": uid(), "session_id": session_id, "label": label, "position": {"x": x, "z": 0},
        "crumb_id": crumb_id, "tags": tags, "source": "user", "created_at": ts(30),
    }


@pytest.fixture
def clock() -> Clock:
    return Clock()


@pytest.fixture
def client(tmp_path: Path, clock: Clock) -> Iterator[TestClient]:
    settings = Settings(api_token=TOKEN, db_path=tmp_path / "qc.db")
    app = create_app(settings, Store(settings.db_path, clock=clock))
    with TestClient(app, base_url="http://localhost") as test_client:
        test_client.app_clock = clock  # type: ignore[attr-defined]
        yield test_client


@pytest.fixture
def venue(client: TestClient) -> dict[str, Any]:
    """A session with crumbs along x, three places and their observations."""
    sid = uid()
    assert client.put(f"/v1/sessions/{sid}", json=session_body(sid), headers=AUTH).status_code == 200
    crumbs = [
        {"id": uid(), "session_id": sid, "seq": i, "position": {"x": float(i), "z": 0.0},
         "heading_rad": 0.0, "t": ts(30 - i), "tracking": "normal"}
        for i in range(26)
    ]
    client.post("/v1/crumbs", json={"contract_version": 1, "crumbs": crumbs}, headers=AUTH)
    quiet = place(sid, "Quiet corner by the windows", 0, ["seating"], crumbs[0]["id"])
    hall = place(sid, "Side hallway", 12, ["step_free"], crumbs[12]["id"])
    bar = place(sid, "Coffee bar", 24, ["seating"], crumbs[24]["id"])
    client.post("/v1/places", json={"contract_version": 1, "places": [quiet, hall, bar]}, headers=AUTH)
    obs = []
    for minutes in (20, 10, 4):
        obs.append(observation(sid, -48, minutes, quiet["id"], spread=4, peaks=1, speech=0.1))
        obs.append(observation(sid, -40, minutes, hall["id"], spread=7, peaks=3, speech=0.2))
        obs.append(observation(sid, -30, minutes, bar["id"], spread=12, peaks=8, speech=0.8))
    obs.append(observation(sid, -31, 0.1, None, spread=11, peaks=7, speech=0.7))
    client.post("/v1/observations", json={"contract_version": 1, "observations": obs}, headers=AUTH)
    return {"session_id": sid, "quiet": quiet, "hall": hall, "bar": bar, "crumbs": crumbs}
