"""SQLite tables for the shared sound layer, kept apart from the personal session tables.

`areas` holds coarse places (indoor zones registered by an organizer, or ~100 m outdoor
cells created on first contribution). `contributions` holds short-lived ingestion
records; nothing here identifies a contributor. Released aggregates are computed on read
from these rows (see `shared_layer`), so purging old rows also retires their aggregates.

The tables are created with `CREATE TABLE IF NOT EXISTS` by `SharedStore.migrate_shared`
and do not touch the personal schema's `user_version` migrations in `db.py`.
"""

from __future__ import annotations

import sqlite3
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime

from .contracts import format_utc
from .db import Store, parse_ts
from .shared_contracts import Area, AreaKind

SHARED_SCHEMA = """
CREATE TABLE IF NOT EXISTS areas (
    id TEXT PRIMARY KEY,
    name TEXT,
    lat REAL NOT NULL,
    lon REAL NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('indoor_zone', 'outdoor_cell')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS areas_lat_lon ON areas(lat, lon);
CREATE TABLE IF NOT EXISTS contributions (
    id TEXT PRIMARY KEY,
    area_id TEXT NOT NULL REFERENCES areas(id),
    time_bucket TEXT NOT NULL,
    capture_profile TEXT NOT NULL,
    source TEXT NOT NULL,
    rms_dbfs REAL NOT NULL,
    spread_db REAL NOT NULL,
    peaks_per_min REAL,
    clipping INTEGER NOT NULL,
    duration_s REAL NOT NULL,
    received_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS contributions_cohort ON contributions(area_id, time_bucket, capture_profile);
CREATE INDEX IF NOT EXISTS contributions_bucket ON contributions(time_bucket);
"""


@dataclass(frozen=True)
class ContributionRow:
    id: str
    area_id: str
    time_bucket: datetime
    capture_profile: str
    source: str
    rms_dbfs: float
    spread_db: float
    peaks_per_min: float | None
    clipping: bool
    duration_s: float


@dataclass(frozen=True)
class StoredCohort:
    """Where a stored contribution landed and how many distinct ids share its cohort."""

    area_id: str
    time_bucket: datetime
    size: int


def _area(row: sqlite3.Row) -> Area:
    return Area(
        id=row["id"], name=row["name"], lat=row["lat"], lon=row["lon"],
        kind=row["kind"], created_at=parse_ts(row["created_at"]),
    )


def _contribution(row: sqlite3.Row) -> ContributionRow:
    return ContributionRow(
        id=row["id"], area_id=row["area_id"], time_bucket=parse_ts(row["time_bucket"]),
        capture_profile=row["capture_profile"], source=row["source"], rms_dbfs=row["rms_dbfs"],
        spread_db=row["spread_db"], peaks_per_min=row["peaks_per_min"], clipping=bool(row["clipping"]),
        duration_s=row["duration_s"],
    )


def _cohort_size(conn: sqlite3.Connection, area_id: str, bucket: str, profile: str) -> int:
    row = conn.execute(
        "SELECT COUNT(DISTINCT id) FROM contributions WHERE area_id = ? AND time_bucket = ? AND capture_profile = ?",
        (area_id, bucket, profile),
    ).fetchone()
    return int(row[0])


class SharedStore(Store):
    """Repository for areas and contributions. Shares the SQLite file with `Store`."""

    def migrate_shared(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._read() as conn:
            conn.executescript(SHARED_SCHEMA)

    # --- areas --------------------------------------------------------------------------

    def get_area(self, area_id: str) -> Area | None:
        with self._read() as conn:
            row = conn.execute("SELECT * FROM areas WHERE id = ?", (area_id,)).fetchone()
        return _area(row) if row else None

    def upsert_area(self, area_id: str, name: str | None, lat: float, lon: float, kind: AreaKind) -> Area:
        now = self._now()
        with self._write() as conn:
            conn.execute(
                """
                INSERT INTO areas (id, name, lat, lon, kind, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name, lat = excluded.lat, lon = excluded.lon,
                    kind = excluded.kind, updated_at = excluded.updated_at
                """,
                (area_id, name, lat, lon, kind, now, now),
            )
            row = conn.execute("SELECT * FROM areas WHERE id = ?", (area_id,)).fetchone()
        return _area(row)

    def ensure_cell(self, area_id: str, name: str | None, lat: float, lon: float) -> None:
        """Create an outdoor cell if it does not exist; an existing area is left as is."""
        now = self._now()
        with self._write() as conn:
            conn.execute(
                "INSERT OR IGNORE INTO areas (id, name, lat, lon, kind, created_at, updated_at) "
                "VALUES (?, ?, ?, ?, 'outdoor_cell', ?, ?)",
                (area_id, name, lat, lon, now, now),
            )

    def areas_in_box(self, south: float, north: float, west: float, east: float) -> list[Area]:
        with self._read() as conn:
            rows = conn.execute(
                "SELECT * FROM areas WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
                (south, north, west, east),
            ).fetchall()
        return [_area(r) for r in rows]

    # --- contributions ------------------------------------------------------------------

    def purge_before(self, cutoff: datetime) -> int:
        with self._write() as conn:
            cur = conn.execute("DELETE FROM contributions WHERE time_bucket < ?", (format_utc(cutoff),))
        return cur.rowcount

    def find_contribution(self, contribution_id: str) -> StoredCohort | None:
        with self._read() as conn:
            row = conn.execute(
                "SELECT area_id, time_bucket, capture_profile FROM contributions WHERE id = ?",
                (contribution_id,),
            ).fetchone()
            if row is None:
                return None
            size = _cohort_size(conn, row["area_id"], row["time_bucket"], row["capture_profile"])
        return StoredCohort(row["area_id"], parse_ts(row["time_bucket"]), size)

    def cohort_size(self, area_id: str, bucket: datetime, profile: str) -> int:
        with self._read() as conn:
            return _cohort_size(conn, area_id, format_utc(bucket), profile)

    def insert_contribution(self, row: ContributionRow, max_per_cohort: int) -> StoredCohort | None:
        """Insert unless the cohort is full. Returns the cohort after the insert, or None
        when the rate limit refused it. A duplicate id is ignored (idempotent)."""
        bucket = format_utc(row.time_bucket)
        with self._write() as conn:
            if _cohort_size(conn, row.area_id, bucket, row.capture_profile) >= max_per_cohort:
                return None
            conn.execute(
                """
                INSERT OR IGNORE INTO contributions (id, area_id, time_bucket, capture_profile, source,
                    rms_dbfs, spread_db, peaks_per_min, clipping, duration_s, received_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    row.id, row.area_id, bucket, row.capture_profile, row.source, row.rms_dbfs,
                    row.spread_db, row.peaks_per_min, int(row.clipping), row.duration_s, self._now(),
                ),
            )
            size = _cohort_size(conn, row.area_id, bucket, row.capture_profile)
        return StoredCohort(row.area_id, row.time_bucket, size)

    def contributions_for(self, area_ids: Sequence[str], since: datetime) -> list[ContributionRow]:
        if not area_ids:
            return []
        marks = ",".join("?" * len(area_ids))
        with self._read() as conn:
            rows = conn.execute(
                f"SELECT * FROM contributions WHERE area_id IN ({marks}) AND time_bucket >= ? "
                "ORDER BY time_bucket DESC",
                (*area_ids, format_utc(since)),
            ).fetchall()
        return [_contribution(r) for r in rows]
