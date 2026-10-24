"""Optional DataSF 311 noise-report layer (dataset vw6y-z8j6).

311 reports are complaints, not measurements. The layer fetches recent `Noise` cases
once, caches them in memory for 15 minutes and filters by distance locally. It returns
counts only: never free text, media links or exact coordinates of a report.
"""

from __future__ import annotations

import math
import threading
from collections import Counter
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

import httpx2 as httpx

ENDPOINT = "https://data.sf.gov/resource/vw6y-z8j6.json"
SF_TZ = ZoneInfo("America/Los_Angeles")
CAVEAT = "311 complaints, not measurements; no reports does not mean quiet"
FIELDS = "service_request_id,service_subtype,requested_datetime,lat,long"
CACHE_TTL = timedelta(minutes=15)
MIN_FETCH_HOURS = 48
EARTH_RADIUS_M = 6_371_000


class CityDataError(RuntimeError):
    """DataSF could not be reached or returned something unusable."""


@dataclass(frozen=True)
class Report:
    subtype: str
    requested_at: datetime
    lat: float
    lon: float


@dataclass(frozen=True)
class CitySummary:
    lat: float
    lon: float
    radius_m: int
    hours: int
    total: int
    by_subtype: dict[str, int]
    newest_age_min: float | None
    caveat: str = CAVEAT


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def sf_local_naive(moment: datetime) -> str:
    """Socrata floating timestamps are San Francisco local time without an offset."""
    return moment.astimezone(SF_TZ).replace(tzinfo=None).isoformat(timespec="seconds")


def parse_report(row: dict[str, object]) -> Report | None:
    try:
        lat = float(str(row["lat"]))
        lon = float(str(row["long"]))
        local = datetime.fromisoformat(str(row["requested_datetime"]))
    except (KeyError, TypeError, ValueError):
        return None
    when = local.replace(tzinfo=SF_TZ) if local.tzinfo is None else local
    subtype = str(row.get("service_subtype") or "unspecified")
    return Report(subtype, when.astimezone(UTC), lat, lon)


def summarize(
    reports: Sequence[Report], lat: float, lon: float, radius_m: int, hours: int, now: datetime
) -> CitySummary:
    since = now - timedelta(hours=hours)
    nearby = [
        r
        for r in reports
        if r.requested_at >= since and haversine_m(lat, lon, r.lat, r.lon) <= radius_m
    ]
    newest = max((r.requested_at for r in nearby), default=None)
    return CitySummary(
        lat=round(lat, 3),
        lon=round(lon, 3),
        radius_m=radius_m,
        hours=hours,
        total=len(nearby),
        by_subtype=dict(Counter(r.subtype for r in nearby).most_common()),
        newest_age_min=round((now - newest).total_seconds() / 60, 1) if newest else None,
    )


class CityNoiseLayer:
    """Fetches and caches recent 311 noise reports for the whole city."""

    def __init__(
        self,
        app_token: str | None = None,
        client: httpx.Client | None = None,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        self._app_token = app_token
        self._client = client or httpx.Client(timeout=httpx.Timeout(20.0))
        self._clock = clock
        self._lock = threading.Lock()
        self._cache: tuple[datetime, int, list[Report]] | None = None

    def _fetch(self, hours: int, now: datetime) -> list[Report]:
        since = sf_local_naive(now - timedelta(hours=hours))
        params = {
            "$select": FIELDS,
            "$where": f"service_name='Noise' AND requested_datetime > '{since}'",
            "$order": "requested_datetime DESC",
            "$limit": "50000",
        }
        headers = {"X-App-Token": self._app_token} if self._app_token else {}
        try:
            response = self._client.get(ENDPOINT, params=params, headers=headers)
            response.raise_for_status()
            rows = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise CityDataError(f"DataSF request failed: {exc}") from exc
        if not isinstance(rows, list):
            raise CityDataError("DataSF returned an unexpected payload")
        return [r for row in rows if isinstance(row, dict) and (r := parse_report(row))]

    def reports(self, hours: int) -> list[Report]:
        now = self._clock()
        window = max(hours, MIN_FETCH_HOURS)
        with self._lock:
            if self._cache is not None:
                fetched_at, cached_window, reports = self._cache
                if now - fetched_at < CACHE_TTL and cached_window >= window:
                    return reports
            reports = self._fetch(window, now)
            self._cache = (now, window, reports)
            return reports

    def nearby(self, lat: float, lon: float, radius_m: int, hours: int) -> CitySummary:
        return summarize(self.reports(hours), lat, lon, radius_m, hours, self._clock())
