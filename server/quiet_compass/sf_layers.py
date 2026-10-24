"""Real San Francisco layers from DataSF, each labelled by what it actually is.

Evidence labels, from strongest to weakest:

* ``measured``             a sensor measurement (only the SFO community-noise monitors, CNEL).
* ``reference_measured``   a published measurement with a citation (small fixed table below).
* ``proxy``                a permit or closure near a point; says something may be loud, not how loud.
* ``unmeasured_candidate`` a place from a city inventory (POPOS, libraries) that might be calm.
                           Nobody has measured it. Candidates carry ``source="seed"`` like seeded places.

Datasets (verified against the live Socrata API on 2026-10-24, see ``contracts/README.md``):
POPOS ``65ik-7wqd``, libraries ``fhhu-wqa7``, SFO aircraft noise climates ``qxw2-ncq3``, active
entertainment permits ``86e8-rfem``, night noise permits ``e7pr-36bt``, temporary street
closures ``8x25-yybr``. Nothing here returns free text from citizens or exact complaint
coordinates. Network access is injectable (``client``) and results are cached in memory.
"""

from __future__ import annotations

import threading
from collections.abc import Callable, Iterable
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import httpx2 as httpx

from .city import CityDataError, haversine_m, sf_local_naive

BASE = "https://data.sf.gov/resource"
LayerName = Literal["quiet_candidates", "entertainment_permits", "night_noise_permits", "street_closures", "sfo_cnel"]
ALL_LAYERS: tuple[LayerName, ...] = (
    "quiet_candidates", "entertainment_permits", "night_noise_permits", "street_closures", "sfo_cnel",
)

DATASETS: dict[str, str] = {
    "popos": "65ik-7wqd",
    "libraries": "fhhu-wqa7",
    "entertainment": "86e8-rfem",
    "night_noise": "e7pr-36bt",
    "closures": "8x25-yybr",
    "sfo": "qxw2-ncq3",
}

CAVEATS: dict[str, str] = {
    "quiet_candidates": (
        "Unmeasured candidate from a city inventory; nobody has measured its sound. "
        "Check hours and conditions before relying on it"
    ),
    "entertainment_permits": (
        "Active entertainment permit at this address; a proxy for possible amplified sound, not a level"
    ),
    "night_noise_permits": (
        "Night-work permit scheduled today or tomorrow (SF local date); a proxy for temporary noise, not a level"
    ),
    "street_closures": "SFMTA street closure in effect now (event or traffic change); a proxy, not a sound level",
    "sfo_cnel": (
        "Daily CNEL (A-weighted dB, 24 h) from an SFO community noise monitor, published monthly; "
        "measured at the monitor, not at your spot, and not live"
    ),
}

CACHE_TTL = {
    "quiet_candidates": timedelta(hours=24),
    "entertainment_permits": timedelta(hours=6),
    "night_noise_permits": timedelta(minutes=15),
    "street_closures": timedelta(minutes=15),
    "sfo_cnel": timedelta(hours=6),
}
SFO_LOOKBACK_DAYS = 120
SFO_MAX_DISTANCE_M = 5000
SFO_MAX_MONITORS = 2
EXCLUDED_NNP_STATUS = {"DENIED", "WITHDRAWN", "PENDING"}


@dataclass(frozen=True)
class ReferenceLevel:
    """A published measured level. No coordinates: the source gives street names only."""

    id: str
    area: str
    location: str
    level_dba_ldn: int
    duration: str
    measured_on: str
    source: str
    source_url: str
    evidence: str = "reference_measured"


_EIR_URL = "https://sfmea.sfplanning.org/CentralSoMaPlanDEIR_11-iv-e-noise.pdf"
_EIR_2014 = "Central SoMa Plan Draft EIR (Dec 2016), Table IV.E-2, 2014 measurements"
_EIR_PRIOR = "Central SoMa Plan Draft EIR (Dec 2016), Table IV.E-3, earlier measurements"
def _ref(key: str, location: str, level: int, duration: str, date: str, source: str = _EIR_2014) -> ReferenceLevel:
    return ReferenceLevel(f"central-soma-{key}", "Central SoMa", location, level, duration, date, source, _EIR_URL)


_PEAK = "10 min, p.m. peak hour"
REFERENCE_LEVELS: tuple[ReferenceLevel, ...] = (
    _ref("4th-bryant", "Fourth Street south of Bryant Street (main street)", 74, "24 h", "2014-05-29"),
    _ref("folsom-mabini", "Folsom Street at Mabini Street (main street)", 78,
         "24 h; likely influenced by fire apparatus", "2014-05-29"),
    _ref("4th-howard", "Fourth and Howard Streets (main street)", 74, _PEAK, "2014-05-19"),
    _ref("5th-folsom-harrison", "Fifth Street between Folsom and Harrison (main street)", 69, _PEAK, "2014-05-19"),
    _ref("harrison-5th-6th", "Harrison Street between Fifth and Sixth (main street)", 72, _PEAK, "2014-05-19"),
    _ref("2nd-bryant", "Second and Bryant Streets (main street, near elevated I-80)", 76, _PEAK, "2014-05-20"),
    _ref("minna-alley", "Minna Street west of Sixth Street (interior alley)", 67, _PEAK, "2014-05-19"),
    _ref("bluxome-alley", "Bluxome Street east of Fifth Street (interior alley)", 66, _PEAK, "2014-05-20"),
    _ref("clementina-alley", "Clementina Street between Fifth and Sixth (interior alley)", 63, "41 h", "2011-09-27",
         _EIR_PRIOR),
)
REFERENCE_NOTE = (
    "Ldn in dBA from a 2016 environmental review (Central SoMa only; main streets averaged 75, alleys 63-67). "
    "Old, area-specific context, not today's level and not comparable to phone dBFS readings"
)


@dataclass(frozen=True)
class LayerPoint:
    layer: str
    kind: str
    label: str
    lat: float
    lon: float
    evidence: str  # unmeasured_candidate | proxy | measured
    caveat: str
    dataset: str
    source: str | None = None  # "seed" for quiet candidates
    detail: str | None = None
    cnel_db: float | None = None
    observed_on: str | None = None
    distance_m: int | None = None


@dataclass(frozen=True)
class LayerSummary:
    lat: float
    lon: float
    radius_m: int
    points: dict[str, list[LayerPoint]]
    unavailable: dict[str, str]


def _num(value: object) -> float | None:
    try:
        return float(str(value))
    except (TypeError, ValueError):
        return None


def _in_sf(lat: float | None, lon: float | None) -> bool:
    return lat is not None and lon is not None and 37.6 <= lat <= 37.85 and -122.55 <= lon <= -122.3


def _point_coords(row: dict[str, Any], key: str = "point") -> tuple[float, float] | None:
    geo = row.get(key)
    coords = geo.get("coordinates") if isinstance(geo, dict) else None
    if isinstance(coords, list) and len(coords) >= 2 and isinstance(coords[0], (int, float)):
        lon, lat = float(coords[0]), float(coords[1])
        return (lat, lon) if _in_sf(lat, lon) else None
    return None


def _parse_local_date(value: object) -> datetime | None:
    try:
        return datetime.fromisoformat(str(value))
    except ValueError:
        return None


def parse_popos(row: dict[str, Any]) -> LayerPoint | None:
    lat, lon = _num(row.get("latitude")), _num(row.get("longitude"))
    name = str(row.get("name") or "").strip()
    if not name or not _in_sf(lat, lon):
        return None
    bits = [str(row[k]) for k in ("type", "hours_type") if row.get(k)]
    if row.get("indoor") is True:
        bits.append("indoor")
    return LayerPoint(
        "quiet_candidates", "popos", name, lat, lon, "unmeasured_candidate",
        CAVEATS["quiet_candidates"], DATASETS["popos"], source="seed", detail="; ".join(bits) or None,
    )


def parse_library(row: dict[str, Any]) -> LayerPoint | None:
    lat, lon = _num(row.get("latitude")), _num(row.get("longitude"))
    name = str(row.get("common_name") or "").strip()
    if not name or "support services" in name.lower() or not _in_sf(lat, lon):
        return None
    return LayerPoint(
        "quiet_candidates", "library", name, lat, lon, "unmeasured_candidate",
        CAVEATS["quiet_candidates"], DATASETS["libraries"], source="seed", detail="public library",
    )


def parse_entertainment(row: dict[str, Any]) -> LayerPoint | None:
    coords = _point_coords(row)
    name = str(row.get("dba_name") or "").strip()
    if coords is None or not name:
        return None
    return LayerPoint(
        "entertainment_permits", "entertainment_permit", name, coords[0], coords[1], "proxy",
        CAVEATS["entertainment_permits"], DATASETS["entertainment"], detail=str(row.get("license_type") or "") or None,
    )


def parse_night_noise(row: dict[str, Any], today: datetime) -> LayerPoint | None:
    coords = _point_coords(row)
    status = str(row.get("nnp") or "").strip().upper()
    start, end = _parse_local_date(row.get("start_date")), _parse_local_date(row.get("end_date"))
    if coords is None or start is None or end is None or status in EXCLUDED_NNP_STATUS:
        return None
    if end.year > 2100 or not (start.date() <= (today + timedelta(days=1)).date() and end.date() >= today.date()):
        return None  # source has bogus far-future end dates; keep only a plausible overlap with today/tomorrow
    hours = str(row.get("start_end_time_each_day") or "").strip()
    work = str(row.get("type_of_work") or "").strip()
    detail = "; ".join(x for x in (work, f"{start.date()} to {end.date()}", hours) if x)
    return LayerPoint(
        "night_noise_permits", "night_noise_permit", str(row.get("address") or "Night work permit").strip(),
        coords[0], coords[1], "proxy", CAVEATS["night_noise_permits"], DATASETS["night_noise"], detail=detail,
    )


def parse_closure(row: dict[str, Any]) -> LayerPoint | None:
    shape = row.get("shape")
    coords = shape.get("coordinates") if isinstance(shape, dict) else None
    if not isinstance(coords, list) or not coords:
        return None
    mid = coords[len(coords) // 2]
    try:
        lon, lat = float(mid[0]), float(mid[1])
    except (TypeError, ValueError, IndexError):
        return None
    if not _in_sf(lat, lon):
        return None
    street = str(row.get("loc_desc") or row.get("street") or "Street closure").strip()
    detail = "; ".join(str(row[k]) for k in ("type", "veh_imp") if row.get(k))
    return LayerPoint(
        "street_closures", "street_closure", street, lat, lon, "proxy",
        CAVEATS["street_closures"], DATASETS["closures"], detail=detail or None,
    )


def latest_sfo_monitors(rows: Iterable[dict[str, Any]]) -> list[LayerPoint]:
    """Newest daily row per SF monitor; rows without a numeric total CNEL are skipped."""
    latest: dict[str, dict[str, Any]] = {}
    for row in rows:
        loc_id = str(row.get("location_id") or "")
        date = str(row.get("date") or "")
        if loc_id and _num(row.get("total_cnel")) is not None and date > str(latest.get(loc_id, {}).get("date", "")):
            latest[loc_id] = row
    out: list[LayerPoint] = []
    for loc_id, row in sorted(latest.items()):
        lat, lon, cnel = _num(row.get("latitude")), _num(row.get("longitude")), _num(row.get("total_cnel"))
        if not _in_sf(lat, lon) or cnel is None:
            continue
        parts = [f"SFO monitor {loc_id}"]
        for key, name in (("aircraft_cnel", "aircraft"), ("community_cnel", "community")):
            value = _num(row.get(key))
            if value is not None:
                parts.append(f"{name} CNEL {value:g}")
        out.append(LayerPoint(
            "sfo_cnel", "sfo_monitor", f"SFO noise monitor {loc_id}", lat, lon, "measured",
            CAVEATS["sfo_cnel"], DATASETS["sfo"], detail="; ".join(parts[1:]) or None, cnel_db=cnel,
            observed_on=str(row["date"])[:10],
        ))
    return out


class SfLayers:
    """Fetches and caches the DataSF layers. Each layer fails independently."""

    def __init__(
        self,
        app_token: str | None = None,
        client: httpx.Client | None = None,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        self._app_token = app_token
        self._client = client or httpx.Client(timeout=httpx.Timeout(20.0), follow_redirects=True)
        self._clock = clock
        self._lock = threading.Lock()
        self._cache: dict[str, tuple[datetime, list[LayerPoint]]] = {}

    def _get(self, dataset: str, params: dict[str, str]) -> list[dict[str, Any]]:
        headers = {"X-App-Token": self._app_token} if self._app_token else {}
        try:
            response = self._client.get(f"{BASE}/{DATASETS[dataset]}.json", params=params, headers=headers)
            response.raise_for_status()
            rows = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise CityDataError(f"DataSF {DATASETS[dataset]} request failed: {exc}") from exc
        if not isinstance(rows, list):
            raise CityDataError(f"DataSF {DATASETS[dataset]} returned an unexpected payload")
        return [r for r in rows if isinstance(r, dict)]

    def _load(self, layer: str) -> list[LayerPoint]:
        now = self._clock()
        today_local = datetime.fromisoformat(sf_local_naive(now))
        if layer == "quiet_candidates":
            popos = self._get("popos", {
                "$select": "name,latitude,longitude,type,hours_type,indoor", "$limit": "500",
            })
            libs = self._get("libraries", {
                "$select": "common_name,latitude,longitude",
                "$where": "common_name like '%Library%' OR common_name like '%Branch%'", "$limit": "200",
            })
            return [p for p in [*map(parse_popos, popos), *map(parse_library, libs)] if p]
        if layer == "entertainment_permits":
            rows = self._get("entertainment", {
                "$select": "dba_name,license_type,point",
                "$where": "permit_status='Active' AND point IS NOT NULL", "$limit": "2000",
            })
            return [p for r in rows if (p := parse_entertainment(r))]
        if layer == "night_noise_permits":
            today = today_local.date().isoformat()
            tomorrow = (today_local + timedelta(days=1)).date().isoformat()
            rows = self._get("night_noise", {
                "$select": "nnp,type_of_work,start_date,end_date,start_end_time_each_day,address,point",
                "$where": (
                    f"start_date <= '{tomorrow}T23:59:59' AND end_date >= '{today}T00:00:00' AND point IS NOT NULL"
                ),
                "$limit": "1000",
            })
            return [p for r in rows if (p := parse_night_noise(r, today_local))]
        if layer == "street_closures":
            utc = now.astimezone(UTC).replace(tzinfo=None).isoformat(timespec="seconds")
            rows = self._get("closures", {
                "$select": "type,loc_desc,street,veh_imp,shape",
                "$where": f"status='Permitted' AND start_utc <= '{utc}' AND end_utc >= '{utc}'", "$limit": "1000",
            })
            return [p for r in rows if (p := parse_closure(r))]
        if layer == "sfo_cnel":
            since = (now - timedelta(days=SFO_LOOKBACK_DAYS)).astimezone(UTC).date().isoformat()
            rows = self._get("sfo", {
                "$select": "date,location_id,latitude,longitude,aircraft_cnel,community_cnel,total_cnel",
                "$where": f"location='San Francisco' AND date >= '{since}'", "$order": "date DESC", "$limit": "2000",
            })
            return latest_sfo_monitors(rows)
        raise ValueError(f"unknown layer {layer!r}")

    def layer(self, name: str) -> list[LayerPoint]:
        now = self._clock()
        with self._lock:
            cached = self._cache.get(name)
            if cached is not None and now - cached[0] < CACHE_TTL[name]:
                return cached[1]
            points = self._load(name)
            self._cache[name] = (now, points)
            return points

    def around(
        self, lat: float, lon: float, radius_m: int, layers: Iterable[str] = ALL_LAYERS, limit: int = 15
    ) -> LayerSummary:
        out: dict[str, list[LayerPoint]] = {}
        unavailable: dict[str, str] = {}
        for name in layers:
            try:
                points = self.layer(name)
            except CityDataError as exc:
                unavailable[name] = str(exc)
                continue
            ranked = sorted(
                (_with_distance(p, haversine_m(lat, lon, p.lat, p.lon)) for p in points),
                key=lambda p: p.distance_m or 0,
            )
            if name == "sfo_cnel":  # sparse sensors: nearest few, with their distance
                ranked = [p for p in ranked if (p.distance_m or 0) <= SFO_MAX_DISTANCE_M][:SFO_MAX_MONITORS]
            else:
                ranked = [p for p in ranked if (p.distance_m or 0) <= radius_m][:limit]
            out[name] = ranked
        return LayerSummary(round(lat, 4), round(lon, 4), radius_m, out, unavailable)


def _with_distance(p: LayerPoint, meters: float) -> LayerPoint:
    return replace(p, distance_m=round(meters))


__all__ = [
    "ALL_LAYERS", "CAVEATS", "DATASETS", "REFERENCE_LEVELS", "REFERENCE_NOTE",
    "LayerPoint", "LayerSummary", "ReferenceLevel", "SfLayers", "latest_sfo_monitors",
]
