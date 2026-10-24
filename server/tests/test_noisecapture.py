"""NoiseCapture aggregation: quality filters, independence of samples, thin-cell suppression, ranged zip read."""

from __future__ import annotations

import json
import zipfile
from datetime import datetime
from io import BytesIO
from typing import Any
from zoneinfo import ZoneInfo

import httpx2 as httpx
import pytest

from quiet_compass.noisecapture import (
    aggregate,
    build_from_remote,
    cell_center,
    cell_of,
    good_tracks,
    period_of,
    read_zip_entry,
)

SF = ZoneInfo("America/Los_Angeles")
LAT, LON = 37.7579, -122.4183


def epoch(hour: int, minute: int = 0, second: int = 0, day: int = 7) -> int:
    return int(datetime(2021, 3, day, hour, minute, second, tzinfo=SF).timestamp() * 1000)


def pt(track: int, ms: int, level: float, acc: float = 5.0, lat: float = LAT, lon: float = LON) -> dict[str, Any]:
    return {"type": "Feature", "geometry": {"type": "Point", "coordinates": [lon, lat, 0.0]},
            "properties": {"pk_track": track, "time_epoch": ms, "noise_level": level, "accuracy": acc}}


def trk(track: int, gain: float | None = 0.0) -> dict[str, Any]:
    return {"type": "Feature", "geometry": None, "properties": {"pk_track": track, "gain_calibration": gain}}


def walk(track: int, hour: int, level: float = 60.0, seconds: int = 10, day: int = 7) -> list[dict[str, Any]]:
    return [pt(track, epoch(hour, 0, s, day), level) for s in range(seconds)]


def test_track_gain_filter() -> None:
    ok = good_tracks([trk(1, 0.0), trk(2, 14.9), trk(3, 40.0), trk(4, -20.0), trk(5, None), trk(6, 100.0)])
    assert ok == {1, 2}


def test_cell_grid_is_about_100_m_and_centred() -> None:
    ix, iy = cell_of(LAT, LON)
    lat_c, lon_c = cell_center(ix, iy)
    assert abs(lat_c - LAT) < 0.0006 and abs(lon_c - LON) < 0.0007
    assert cell_of(lat_c, lon_c) == (ix, iy)
    assert cell_of(LAT + 0.0011, LON) != (ix, iy)


def test_period_uses_sf_local_time() -> None:
    assert period_of(epoch(9)) == "day" and period_of(epoch(20)) == "evening"
    assert period_of(epoch(2)) == "night" and period_of(epoch(23)) == "night"


def test_filters_independence_and_publication_rules() -> None:
    pts: list[dict[str, Any]] = []
    for track, day in ((1, 1), (2, 2), (3, 3)):  # three tracks, two 5-minute windows each = 6 windows
        pts += walk(track, 10, 60.0, day=day) + [pt(track, epoch(10, 7, s, day), 60.0) for s in range(10)]
    pts += walk(1, 11, 60.0, day=4)  # a 7th window, track 1 again
    # everything below must be dropped
    pts += [pt(1, epoch(10, 30, s), 60.0, acc=16.0) for s in range(10)]            # GPS > 15 m
    pts += [pt(1, epoch(10, 40, s), 0.0) for s in range(10)]                        # 0.0 sentinel
    pts += [pt(1, epoch(10, 50, s), 60.0, lat=37.9) for s in range(10)]             # outside the city box
    pts += [pt(9, epoch(10, 5, s), 60.0) for s in range(10)]                        # track gain 40
    pts += [pt(8, epoch(10, 5, s), 60.0) for s in range(10)]                        # track not in tracks file
    pts += [pt(1, epoch(12, 0, s), 90.0) for s in range(3)]                         # window with < 5 seconds
    collection, stats = aggregate(pts, [trk(1), trk(2), trk(3), trk(9, 40.0)])
    assert stats.dropped_accuracy == 10 and stats.dropped_level == 10 and stats.dropped_outside_bbox == 10
    assert stats.dropped_track == 20 and stats.windows_dropped_short == 1
    assert stats.windows == 7 and stats.cells_published == 1
    (feature,) = collection["features"]
    props = feature["properties"]
    # 70 one-second points are NOT 70 samples: the cell has 7 five-minute windows from 3 tracks
    assert (props["windows"], props["tracks"], props["seconds"]) == (7, 3, 70)
    assert props["laeq_db"] == 60.0 and props["median_window_db"] == 60.0
    assert props["evidence"] == "measured_crowdsourced" and props["quality"] == "measured_crowdsourced_uncalibrated"
    assert props["periods"]["day"]["windows"] == 7 and "night" not in props["periods"]
    assert props["first_date"] == "2021-03-01" and props["last_date"] == "2021-03-04"
    assert "ODbL" in collection["attribution"] and "uncalibrated" in collection["caveat"]


def test_thin_cells_are_not_published_and_energy_mean_is_used() -> None:
    thin = walk(1, 10) + walk(2, 10, day=8)  # two tracks only
    collection, stats = aggregate(thin, [trk(1), trk(2)])
    assert collection["features"] == [] and stats.cells_dropped_thin == 1
    loud_quiet = [p for t in (1, 2, 3) for p in walk(t, 10, 50.0, day=t)] + [
        p for t in (1, 2, 3) for p in walk(t, 14, 70.0, day=t)
    ]
    out, _ = aggregate(loud_quiet, [trk(1), trk(2), trk(3)])
    props = out["features"][0]["properties"]
    assert props["laeq_db"] == pytest.approx(67.0, abs=0.1)  # energy mean of 50 and 70 dB, not 60
    assert props["median_window_db"] == 60.0


def _zip_bytes() -> tuple[bytes, dict[str, bytes]]:
    pts = [p for t in (1, 2, 3) for p in walk(t, 10, 55.0, day=t) + walk(t, 15, 55.0, day=t)]
    members = {
        "United States_California_San Francisco.points.geojson": json.dumps({"features": pts}).encode(),
        "United States_California_San Francisco.tracks.geojson": json.dumps(
            {"features": [trk(1), trk(2), trk(3)]}).encode(),
        "United States_Alabama_Autauga.points.geojson": b"{}",
    }
    buf = BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in members.items():
            z.writestr(name, data)
    return buf.getvalue(), members


def _range_client(blob: bytes, honour_range: bool = True) -> tuple[httpx.Client, list[str]]:
    log: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        header = request.headers.get("range")
        log.append(header or "")
        if not header or not honour_range:
            return httpx.Response(200, content=blob)
        start, end = (int(x) for x in header.removeprefix("bytes=").split("-"))
        return httpx.Response(206, content=blob[start : end + 1])

    return httpx.Client(transport=httpx.MockTransport(handler)), log


def test_ranged_zip_read_gets_only_the_requested_members() -> None:
    blob, members = _zip_bytes()
    client, log = _range_client(blob)
    name = "United States_California_San Francisco.tracks.geojson"
    assert read_zip_entry(client, "https://example.test/us.zip", len(blob), name) == members[name]
    assert all(h.startswith("bytes=") for h in log)
    with pytest.raises(KeyError):
        read_zip_entry(client, "https://example.test/us.zip", len(blob), "missing.geojson")
    collection, stats = build_from_remote(client, len(blob), "https://example.test/us.zip")
    assert stats.cells_published == 1 and collection["features"][0]["properties"]["tracks"] == 3


def test_ranged_zip_read_fails_loudly_if_server_ignores_range() -> None:
    blob, _ = _zip_bytes()
    client, _ = _range_client(blob, honour_range=False)
    with pytest.raises(RuntimeError, match="Range"):
        read_zip_entry(client, "https://example.test/us.zip", len(blob), "x")

