# Contracts (v1)

`quiet-compass.schema.json` is the single source of truth for everything the phone and the server exchange. The Python models live in `server/quiet_compass/contracts.py` and the Swift models in `ios/Packages/QuietCore/Sources/QuietCore/Contracts.swift`. Both are written by hand to mirror the schema.

Rules:

- **Timestamps** are ISO 8601 UTC with a `Z` suffix. **Ids** are client-generated UUIDs.
- **Writes are idempotent.** The server ignores a record whose `id` it has already stored, so the phone can retry an outbox batch safely.
- **Levels are relative dBFS from one device profile.** They are never labelled dBA or SPL, and the server only compares observations that share a `device_profile`.
- **Positions** are floor-plane metres in the AR session's gravity-aligned frame. Yaw is arbitrary, so positions mean nothing across sessions.
- **Changing a contract.** Agree it across all three tracks, update the schema and both model files in one commit, and bump `contract_version` if the change breaks existing clients.

## HTTP API (phone ↔ server)

Every request carries `Authorization: Bearer $QC_API_TOKEN`. Bodies are JSON.

| Method and path | Body | Response |
| --- | --- | --- |
| `PUT /v1/sessions/{session_id}` | `SessionUpsert` | `200` with the session |
| `POST /v1/observations` | `ObservationBatch` | `200 IngestResult` |
| `POST /v1/crumbs` | `CrumbBatch` | `200 IngestResult` |
| `POST /v1/places` | `PlaceBatch` | `200 IngestResult`; resending an `id` with a new label or tags updates it |
| `POST /v1/feedback` | `FeedbackBatch` | `200 IngestResult` |
| `GET /v1/sessions/{session_id}/guidance` | none | `200 Guidance`, or `204` when nothing is active |
| `POST /v1/sessions/{session_id}/guidance/status` | `GuidanceStatusUpdate` | `200 Guidance` |
| `GET /healthz` | none | `200 {"ok": true}` (no auth) |

The phone polls guidance every 2 s while the map screen is open, and every 10 s otherwise.

## MCP tools (agent ↔ server)

These are served at `/mcp` (Streamable HTTP, stateless, JSON responses).

| Tool | Purpose | Annotations |
| --- | --- | --- |
| `quiet_get_context(place_id?, response_format)` | Recent sound around the user, or one place's history and its changes since the last call | read-only |
| `quiet_find_space(goal, duration_minutes, return_by, needs?)` | Up to 3 ranked places with evidence, or `{no_fit, closest, relax}` | read-only |
| `quiet_start_guidance(place_id, reason?)` | Upserts the active guidance row the phone polls | idempotent, not destructive |
| `quiet_record_feedback(place_id, goal, verdict, feel?)` | Stores an explicit rating | not destructive |
| `quiet_city_noise_reports(lat, lon, radius_m, hours)` | Optional: SF 311 noise report counts by subtype | read-only, open world |

The MCP tools act on the **active session**: the one named by `QC_ACTIVE_SESSION_ID` if set, otherwise the most recently updated session.
