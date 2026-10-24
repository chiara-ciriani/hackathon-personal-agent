"""NoiseCapture (Noise-Planet) crowdsourced points aggregated into coarse San Francisco cells.

Source: ``https://data.noise-planet.org/dump/United States.zip`` (one GeoJSON trio per county, ODbL).
Checked on 2026-10-24: the zip is 1.02 GB, last modified 2025-07-14, and holds
``United States_California_San Francisco.{points,tracks,areas}.geojson``. The index is served over
https only (plain http returns an unrelated page). Evidence label: ``measured_crowdsourced``, quality
``measured_crowdsourced_uncalibrated``: phone microphones, mostly without calibration, no sound audit.

Pipeline (offline, run by hand; nothing here is fetched at request time):

1. keep points inside the SF bounding box with GPS accuracy <= 15 m and a plausible LAeq (30-120 dB;
   0.0 is a sentinel in the dump);
2. drop whole tracks without a track record or with a ``gain_calibration`` outside +-15 dB (the data
   paper reports implausible calibrations: 40 dB, 60 dB, 100 dB). The published ``noise_level`` is used
   as is; the gain is NOT applied because the dump does not say whether it is already included;
3. one second is not an independent sample: points are first averaged (energy mean) per
   (track, ~100 m cell, 5-minute window) and windows with fewer than 5 seconds are dropped;
4. cells publish only with >= 3 distinct tracks and >= 5 windows, so one walk never makes a cell.
"""

from __future__ import annotations

import json
import math
import statistics
import struct
import zlib
from collections import defaultdict
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any
from zoneinfo import ZoneInfo

SF_BBOX = (37.70, 37.83, -122.52, -122.35)  # lat_min, lat_max, lon_min, lon_max
ZIP_URL = "https://data.noise-planet.org/dump/United%20States.zip"
SF_ENTRIES = {
    kind: f"United States_California_San Francisco.{kind}.geojson" for kind in ("points", "tracks", "areas")
}
MAX_ACCURACY_M = 15.0
MIN_DB, MAX_DB = 30.0, 120.0
MAX_ABS_GAIN_DB = 15.0
WINDOW_S = 300
MIN_SECONDS_PER_WINDOW = 5
MIN_TRACKS_PER_CELL = 3
MIN_WINDOWS_PER_CELL = 5
MIN_WINDOWS_PER_PERIOD = 3
CELL_M = 100.0
_REF_LAT = 37.77
_DLAT = CELL_M / 111_320.0
_DLON = CELL_M / (111_320.0 * math.cos(math.radians(_REF_LAT)))
SF_TZ = ZoneInfo("America/Los_Angeles")
PERIODS = {"day": range(7, 19), "evening": range(19, 23)}  # everything else is night
ATTRIBUTION = "Contains information from NoiseCapture / Noise-Planet community, ODbL 1.0 (https://noise-planet.org/noisecapture_data.html)"
CAVEAT = (
    "Crowdsourced phone measurements (NoiseCapture), mostly uncalibrated: levels can be off by several dB. "
    "Not live, collected 2017-2025 by volunteers walking around, so it reflects where people walked and when. "
    "Not comparable with this app's relative dBFS readings"
)
QUALITY = "measured_crowdsourced_uncalibrated"


def _energy_mean(levels: Iterable[float]) -> float:
    vals = list(levels)
    return 10 * math.log10(sum(10 ** (v / 10) for v in vals) / len(vals))


def cell_of(lat: float, lon: float) -> tuple[int, int]:
    return math.floor((lat - SF_BBOX[0]) / _DLAT), math.floor((lon - SF_BBOX[2]) / _DLON)


def cell_center(ix: int, iy: int) -> tuple[float, float]:
    return SF_BBOX[0] + (ix + 0.5) * _DLAT, SF_BBOX[2] + (iy + 0.5) * _DLON


def period_of(epoch_ms: int) -> str:
    hour = datetime.fromtimestamp(epoch_ms / 1000, UTC).astimezone(SF_TZ).hour
    return next((name for name, hours in PERIODS.items() if hour in hours), "night")


def good_tracks(tracks: Iterable[dict[str, Any]]) -> set[int]:
    """Track ids with a recorded calibration gain inside +-15 dB."""
    ok: set[int] = set()
    for feature in tracks:
        props = feature.get("properties") or {}
        gain = props.get("gain_calibration")
        if isinstance(gain, (int, float)) and abs(gain) <= MAX_ABS_GAIN_DB and props.get("pk_track") is not None:
            ok.add(int(props["pk_track"]))
    return ok


@dataclass
class IngestStats:
    points_seen: int = 0
    dropped_outside_bbox: int = 0
    dropped_accuracy: int = 0
    dropped_level: int = 0
    dropped_track: int = 0
    points_kept: int = 0
    windows: int = 0
    windows_dropped_short: int = 0
    cells_published: int = 0
    cells_dropped_thin: int = 0


def aggregate(
    points: Iterable[dict[str, Any]], tracks: Iterable[dict[str, Any]]
) -> tuple[dict[str, Any], IngestStats]:
    """Return a GeoJSON FeatureCollection of cells (centre points) and the filter statistics."""
    stats = IngestStats()
    ok_tracks = good_tracks(tracks)
    seconds: dict[tuple[tuple[int, int], int, int], list[float]] = defaultdict(list)
    window_time: dict[tuple[tuple[int, int], int, int], int] = {}
    for feature in points:
        stats.points_seen += 1
        props = feature.get("properties") or {}
        coords = (feature.get("geometry") or {}).get("coordinates") or []
        if len(coords) < 2:
            stats.dropped_outside_bbox += 1
            continue
        lon, lat = float(coords[0]), float(coords[1])
        if not (SF_BBOX[0] <= lat <= SF_BBOX[1] and SF_BBOX[2] <= lon <= SF_BBOX[3]):
            stats.dropped_outside_bbox += 1
            continue
        acc = props.get("accuracy")
        if not isinstance(acc, (int, float)) or acc > MAX_ACCURACY_M:
            stats.dropped_accuracy += 1
            continue
        level, epoch = props.get("noise_level"), props.get("time_epoch")
        if not isinstance(level, (int, float)) or not MIN_DB <= level <= MAX_DB or not isinstance(epoch, int):
            stats.dropped_level += 1
            continue
        track = props.get("pk_track")
        if track not in ok_tracks:
            stats.dropped_track += 1
            continue
        stats.points_kept += 1
        key = (cell_of(lat, lon), int(track), epoch // (WINDOW_S * 1000))
        seconds[key].append(float(level))
        window_time.setdefault(key, epoch)

    cells: dict[tuple[int, int], list[tuple[int, int, float, int]]] = defaultdict(list)  # track, epoch, dB, seconds
    for key, levels in seconds.items():
        if len(levels) < MIN_SECONDS_PER_WINDOW:
            stats.windows_dropped_short += 1
            continue
        stats.windows += 1
        cells[key[0]].append((key[1], window_time[key], _energy_mean(levels), len(levels)))

    features: list[dict[str, Any]] = []
    for cell, windows in sorted(cells.items()):
        n_tracks = len({w[0] for w in windows})
        if n_tracks < MIN_TRACKS_PER_CELL or len(windows) < MIN_WINDOWS_PER_CELL:
            stats.cells_dropped_thin += 1
            continue
        lat, lon = cell_center(*cell)
        levels = [w[2] for w in windows]
        by_period: dict[str, dict[str, float | int]] = {}
        for name in ("day", "evening", "night"):
            sel = [w[2] for w in windows if period_of(w[1]) == name]
            if len(sel) >= MIN_WINDOWS_PER_PERIOD:
                by_period[name] = {"laeq_db": round(_energy_mean(sel), 1), "windows": len(sel)}
        first, last = min(w[1] for w in windows), max(w[1] for w in windows)
        features.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [round(lon, 6), round(lat, 6)]},
            "properties": {
                "evidence": "measured_crowdsourced", "quality": QUALITY, "cell_m": int(CELL_M),
                "laeq_db": round(_energy_mean(levels), 1), "median_window_db": round(statistics.median(levels), 1),
                "windows": len(windows), "tracks": n_tracks, "seconds": sum(w[3] for w in windows),
                "periods": by_period,
                "first_date": datetime.fromtimestamp(first / 1000, SF_TZ).date().isoformat(),
                "last_date": datetime.fromtimestamp(last / 1000, SF_TZ).date().isoformat(),
            },
        })
        stats.cells_published += 1
    collection = {
        "type": "FeatureCollection", "attribution": ATTRIBUTION, "caveat": CAVEAT,
        "source": ZIP_URL, "features": features,
    }
    return collection, stats


# --- ranged read of single zip members (the archive is 1 GB; SF is ~9 MB of it) ------------------------


def _range(client: Any, url: str, start: int, end: int) -> bytes:
    response = client.get(url, headers={"Range": f"bytes={start}-{end}"})
    if response.status_code != 206:
        raise RuntimeError(f"server ignored the Range request (HTTP {response.status_code})")
    return bytes(response.content)


def read_zip_entry(client: Any, url: str, size: int, name: str) -> bytes:
    """Read one member of a remote zip with HTTP Range requests (deflate or stored, no zip64 members)."""
    tail = _range(client, url, max(0, size - 70_000), size - 1)
    eocd = tail.rfind(b"PK\x05\x06")
    if eocd < 0:
        raise RuntimeError("zip end of central directory not found in the last 70 KB")
    total, cd_size, cd_off = struct.unpack("<HII", tail[eocd + 10 : eocd + 20])
    if cd_off == 0xFFFFFFFF or total == 0xFFFF:
        zip64 = tail.rfind(b"PK\x06\x07", 0, eocd)
        if zip64 < 0:
            raise RuntimeError("zip64 locator not found")
        (rec_off,) = struct.unpack("<Q", tail[zip64 + 8 : zip64 + 16])
        rec = _range(client, url, rec_off, rec_off + 55)
        cd_size, cd_off = struct.unpack("<QQ", rec[40:56])
    directory = _range(client, url, cd_off, cd_off + cd_size - 1)
    pos = 0
    while directory[pos : pos + 4] == b"PK\x01\x02":
        (method,) = struct.unpack("<H", directory[pos + 10 : pos + 12])
        comp, uncomp, nlen, elen, clen = struct.unpack("<IIHHH", directory[pos + 20 : pos + 34])
        (offset,) = struct.unpack("<I", directory[pos + 42 : pos + 46])
        entry = directory[pos + 46 : pos + 46 + nlen].decode()
        if entry == name:
            head = _range(client, url, offset, offset + 29)
            local_n, local_e = struct.unpack("<HH", head[26:30])
            start = offset + 30 + local_n + local_e
            raw = _range(client, url, start, start + comp - 1)
            data = zlib.decompress(raw, -15) if method == 8 else raw
            if len(data) != uncomp:
                raise RuntimeError(f"{name}: expected {uncomp} bytes, got {len(data)}")
            return data
        pos += 46 + nlen + elen + clen
    raise KeyError(name)


def features_of(data: bytes) -> list[dict[str, Any]]:
    body = json.loads(data)
    feats = body.get("features") if isinstance(body, dict) else None
    return [f for f in feats if isinstance(f, dict)] if isinstance(feats, list) else []


def build_from_remote(client: Any, size: int, url: str = ZIP_URL) -> tuple[dict[str, Any], IngestStats]:
    points = features_of(read_zip_entry(client, url, size, SF_ENTRIES["points"]))
    tracks = features_of(read_zip_entry(client, url, size, SF_ENTRIES["tracks"]))
    return aggregate(points, tracks)


def main() -> None:  # pragma: no cover - manual, network
    import argparse
    from dataclasses import asdict

    import httpx2 as httpx

    parser = argparse.ArgumentParser(description="Aggregate NoiseCapture points for San Francisco")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    with httpx.Client(timeout=httpx.Timeout(300.0), follow_redirects=True) as client:
        head = client.head(ZIP_URL)
        size = int(head.headers["content-length"])
        collection, stats = build_from_remote(client, size)
    collection["retrieved"] = datetime.now(UTC).date().isoformat()
    collection["last_modified"] = head.headers.get("last-modified")
    collection["filters"] = {
        "max_accuracy_m": MAX_ACCURACY_M, "level_db": [MIN_DB, MAX_DB], "max_abs_gain_db": MAX_ABS_GAIN_DB,
        "window_s": WINDOW_S, "min_tracks": MIN_TRACKS_PER_CELL, "min_windows": MIN_WINDOWS_PER_CELL,
    }
    collection["stats"] = asdict(stats)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(collection, fh, separators=(",", ":"))
    print(asdict(stats))


if __name__ == "__main__":  # pragma: no cover
    main()
