"""SQLite repository: schema migrations, idempotent ingest and the queries the tools need.

Each operation opens its own short-lived connection (WAL, synchronous=NORMAL,
busy_timeout=5000), so the store is safe to share between the async REST handlers and
the MCP tools, which run in worker threads. Writes run inside `BEGIN IMMEDIATE`.

Timestamps are stored as fixed-width ISO 8601 UTC strings (`...T20:15:03.120Z`), so
string order is time order. Full records are kept as JSON in `body` for lossless reads.
"""

from __future__ import annotations

import sqlite3
from collections.abc import Callable, Iterator, Sequence
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

from .contracts import (
    Crumb,
    Feedback,
    Guidance,
    IngestResult,
    Observation,
    Place,
    Session,
    format_utc,
)

Clock = Callable[[], datetime]

MIGRATIONS: tuple[str, ...] = (
    """
    CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        body TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    CREATE TABLE observations (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES sessions(id),
        t TEXT NOT NULL,
        place_id TEXT,
        body TEXT NOT NULL
    );
    CREATE INDEX observations_session_t ON observations(session_id, t);
    CREATE INDEX observations_place_t ON observations(place_id, t);
    CREATE TABLE crumbs (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES sessions(id),
        seq INTEGER NOT NULL,
        body TEXT NOT NULL
    );
    CREATE INDEX crumbs_session_seq ON crumbs(session_id, seq);
    CREATE TABLE places (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES sessions(id),
        body TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    CREATE INDEX places_session ON places(session_id);
    CREATE TABLE feedback (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES sessions(id),
        place_id TEXT NOT NULL,
        t TEXT NOT NULL,
        body TEXT NOT NULL
    );
    CREATE INDEX feedback_session_t ON feedback(session_id, t);
    CREATE TABLE guidance (
        session_id TEXT PRIMARY KEY REFERENCES sessions(id),
        body TEXT NOT NULL
    );
    CREATE TABLE context_reads (
        session_id TEXT NOT NULL,
        place_id TEXT NOT NULL,
        returned_at TEXT NOT NULL,
        latest_obs_t TEXT,
        latest_level REAL,
        PRIMARY KEY (session_id, place_id)
    );
    """,
)


class UnknownSessionError(LookupError):
    """A record refers to a session that has not been registered with PUT /v1/sessions."""

    def __init__(self, session_ids: Sequence[str]) -> None:
        self.session_ids = sorted(set(session_ids))
        super().__init__(f"unknown session(s): {', '.join(self.session_ids)}")


@dataclass(frozen=True)
class ContextRead:
    returned_at: datetime
    latest_obs_t: datetime | None
    latest_level: float | None


def utc_now() -> datetime:
    return datetime.now(UTC)


def parse_ts(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _key(value: UUID | str) -> str:
    return str(UUID(str(value)))


class Store:
    """Repository over one SQLite file. Cheap to construct; call `migrate()` once."""

    def __init__(self, path: Path | str, clock: Clock = utc_now) -> None:
        self.path = Path(path)
        self.clock = clock

    # --- connection management --------------------------------------------------------

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, timeout=5, isolation_level=None)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA busy_timeout=5000")
        conn.execute("PRAGMA synchronous=NORMAL")
        conn.execute("PRAGMA foreign_keys=ON")
        return conn

    @contextmanager
    def _read(self) -> Iterator[sqlite3.Connection]:
        conn = self._connect()
        try:
            yield conn
        finally:
            conn.close()

    @contextmanager
    def _write(self) -> Iterator[sqlite3.Connection]:
        conn = self._connect()
        try:
            conn.execute("BEGIN IMMEDIATE")
            try:
                yield conn
            except BaseException:
                conn.execute("ROLLBACK")
                raise
            conn.execute("COMMIT")
        finally:
            conn.close()

    def migrate(self) -> int:
        """Create or upgrade the schema; returns the resulting schema version."""
        self.path.parent.mkdir(parents=True, exist_ok=True)
        conn = self._connect()
        try:
            conn.execute("PRAGMA journal_mode=WAL")
            version = conn.execute("PRAGMA user_version").fetchone()[0]
            for index, script in enumerate(MIGRATIONS[version:], start=version + 1):
                conn.executescript(f"BEGIN IMMEDIATE;\n{script}\nPRAGMA user_version={index};\nCOMMIT;")
            return len(MIGRATIONS)
        finally:
            conn.close()

    def _now(self) -> str:
        return format_utc(self.clock())

    def _touch(self, conn: sqlite3.Connection, session_ids: set[str]) -> None:
        now = self._now()
        conn.executemany(
            "UPDATE sessions SET updated_at = ? WHERE id = ?", [(now, s) for s in session_ids]
        )

    def _require_sessions(self, conn: sqlite3.Connection, session_ids: set[str]) -> None:
        known = {
            row[0]
            for row in conn.execute(
                f"SELECT id FROM sessions WHERE id IN ({','.join('?' * len(session_ids))})",
                tuple(session_ids),
            )
        }
        if missing := session_ids - known:
            raise UnknownSessionError(list(missing))

    # --- ingest -----------------------------------------------------------------------

    def upsert_session(self, session: Session) -> Session:
        now = self._now()
        with self._write() as conn:
            conn.execute(
                """
                INSERT INTO sessions (id, body, created_at, updated_at) VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET body = excluded.body, updated_at = excluded.updated_at
                """,
                (_key(session.id), session.model_dump_json(), now, now),
            )
        return session

    def _insert_new(
        self,
        table: str,
        columns: Sequence[str],
        rows: Sequence[tuple[object, ...]],
        session_ids: set[str],
    ) -> IngestResult:
        if not rows:
            return IngestResult(accepted=0, duplicates=0)
        placeholders = ",".join("?" * len(columns))
        sql = f"INSERT OR IGNORE INTO {table} ({','.join(columns)}) VALUES ({placeholders})"
        with self._write() as conn:
            self._require_sessions(conn, session_ids)
            before = conn.total_changes
            conn.executemany(sql, rows)
            accepted = conn.total_changes - before
            if accepted:
                self._touch(conn, session_ids)
        return IngestResult(accepted=accepted, duplicates=len(rows) - accepted)

    def add_observations(self, observations: Sequence[Observation]) -> IngestResult:
        rows = [
            (
                _key(o.id),
                _key(o.session_id),
                format_utc(o.t),
                _key(o.place_id) if o.place_id else None,
                o.model_dump_json(),
            )
            for o in observations
        ]
        sessions = {_key(o.session_id) for o in observations}
        return self._insert_new(
            "observations", ("id", "session_id", "t", "place_id", "body"), rows, sessions
        )

    def add_crumbs(self, crumbs: Sequence[Crumb]) -> IngestResult:
        rows = [(_key(c.id), _key(c.session_id), c.seq, c.model_dump_json()) for c in crumbs]
        sessions = {_key(c.session_id) for c in crumbs}
        return self._insert_new("crumbs", ("id", "session_id", "seq", "body"), rows, sessions)

    def add_feedback(self, feedback: Sequence[Feedback]) -> IngestResult:
        rows = [
            (_key(f.id), _key(f.session_id), _key(f.place_id), format_utc(f.t), f.model_dump_json())
            for f in feedback
        ]
        sessions = {_key(f.session_id) for f in feedback}
        return self._insert_new(
            "feedback", ("id", "session_id", "place_id", "t", "body"), rows, sessions
        )

    def upsert_places(self, places: Sequence[Place]) -> IngestResult:
        """Insert new places; an existing id with changed fields is updated (counted as
        accepted), an identical resend is a duplicate. A place never moves sessions."""
        if not places:
            return IngestResult(accepted=0, duplicates=0)
        sessions = {_key(p.session_id) for p in places}
        now = self._now()
        accepted = 0
        with self._write() as conn:
            self._require_sessions(conn, sessions)
            for place in places:
                body = place.model_dump_json()
                cur = conn.execute(
                    """
                    INSERT INTO places (id, session_id, body, updated_at) VALUES (?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET body = excluded.body, updated_at = excluded.updated_at
                    WHERE places.body != excluded.body AND places.session_id = excluded.session_id
                    """,
                    (_key(place.id), _key(place.session_id), body, now),
                )
                accepted += cur.rowcount
            if accepted:
                self._touch(conn, sessions)
        return IngestResult(accepted=accepted, duplicates=len(places) - accepted)

    # --- guidance ---------------------------------------------------------------------

    def get_guidance(self, session_id: UUID | str) -> Guidance | None:
        with self._read() as conn:
            row = conn.execute(
                "SELECT body FROM guidance WHERE session_id = ?", (_key(session_id),)
            ).fetchone()
        return Guidance.model_validate_json(row["body"]) if row else None

    def start_guidance(self, place: Place, reason: str | None) -> Guidance:
        """Make `place` the active guidance target. Repeating the same call is a no-op."""
        current = self.get_guidance(place.session_id)
        if (
            current is not None
            and current.status == "active"
            and current.target_place_id == place.id
            and current.reason == reason
            and current.target_label == place.label
        ):
            return current
        guidance = Guidance(
            session_id=place.session_id,
            target_place_id=place.id,
            target_label=place.label,
            status="active",
            reason=reason,
            updated_at=self.clock(),
        )
        self._save_guidance(guidance)
        return guidance

    def set_guidance_status(self, session_id: UUID | str, status: str) -> Guidance | None:
        current = self.get_guidance(session_id)
        if current is None:
            return None
        if current.status == status:
            return current
        updated = current.model_copy(update={"status": status, "updated_at": self.clock()})
        self._save_guidance(updated)
        return updated

    def _save_guidance(self, guidance: Guidance) -> None:
        with self._write() as conn:
            conn.execute(
                """
                INSERT INTO guidance (session_id, body) VALUES (?, ?)
                ON CONFLICT(session_id) DO UPDATE SET body = excluded.body
                """,
                (_key(guidance.session_id), guidance.model_dump_json()),
            )
            self._touch(conn, {_key(guidance.session_id)})

    # --- queries ----------------------------------------------------------------------

    def get_session(self, session_id: UUID | str) -> Session | None:
        with self._read() as conn:
            row = conn.execute(
                "SELECT body FROM sessions WHERE id = ?", (_key(session_id),)
            ).fetchone()
        return Session.model_validate_json(row["body"]) if row else None

    def latest_session(self) -> Session | None:
        with self._read() as conn:
            row = conn.execute(
                "SELECT body FROM sessions ORDER BY updated_at DESC, created_at DESC LIMIT 1"
            ).fetchone()
        return Session.model_validate_json(row["body"]) if row else None

    def observations(self, session_id: UUID | str) -> list[Observation]:
        with self._read() as conn:
            rows = conn.execute(
                "SELECT body FROM observations WHERE session_id = ? ORDER BY t",
                (_key(session_id),),
            ).fetchall()
        return [Observation.model_validate_json(r["body"]) for r in rows]

    def crumbs(self, session_id: UUID | str) -> list[Crumb]:
        with self._read() as conn:
            rows = conn.execute(
                "SELECT body FROM crumbs WHERE session_id = ? ORDER BY seq",
                (_key(session_id),),
            ).fetchall()
        return [Crumb.model_validate_json(r["body"]) for r in rows]

    def places(self, session_id: UUID | str) -> list[Place]:
        with self._read() as conn:
            rows = conn.execute(
                "SELECT body FROM places WHERE session_id = ?", (_key(session_id),)
            ).fetchall()
        places = [Place.model_validate_json(r["body"]) for r in rows]
        return sorted(places, key=lambda p: (p.created_at, p.label))

    def feedback(self, session_id: UUID | str) -> list[Feedback]:
        with self._read() as conn:
            rows = conn.execute(
                "SELECT body FROM feedback WHERE session_id = ? ORDER BY t",
                (_key(session_id),),
            ).fetchall()
        return [Feedback.model_validate_json(r["body"]) for r in rows]

    # --- per-place read tracking for changes_since_last_call --------------------------

    def last_context_read(self, session_id: UUID | str, place_id: UUID | str) -> ContextRead | None:
        with self._read() as conn:
            row = conn.execute(
                "SELECT * FROM context_reads WHERE session_id = ? AND place_id = ?",
                (_key(session_id), _key(place_id)),
            ).fetchone()
        if row is None:
            return None
        return ContextRead(
            returned_at=parse_ts(row["returned_at"]),
            latest_obs_t=parse_ts(row["latest_obs_t"]) if row["latest_obs_t"] else None,
            latest_level=row["latest_level"],
        )

    def record_context_read(
        self,
        session_id: UUID | str,
        place_id: UUID | str,
        latest_obs_t: datetime | None,
        latest_level: float | None,
    ) -> None:
        with self._write() as conn:
            conn.execute(
                """
                INSERT INTO context_reads (session_id, place_id, returned_at, latest_obs_t, latest_level)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(session_id, place_id) DO UPDATE SET
                    returned_at = excluded.returned_at,
                    latest_obs_t = excluded.latest_obs_t,
                    latest_level = excluded.latest_level
                """,
                (
                    _key(session_id),
                    _key(place_id),
                    self._now(),
                    format_utc(latest_obs_t) if latest_obs_t else None,
                    latest_level,
                ),
            )
