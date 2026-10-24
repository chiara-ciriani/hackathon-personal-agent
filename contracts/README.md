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
| `quiet_sf_layers(lat, lon, radius_m?, include?, include_references?)` | Optional (same flag as above): real SF layers near a point, each labelled with an `EvidenceLabel` | read-only, open world |

The MCP tools act on the **active session**: the one named by `QC_ACTIVE_SESSION_ID` if set, otherwise the most recently updated session.

## SF city layers (`quiet_sf_layers`)

Enabled with `QC_CITY_LAYER_ENABLED=1`, together with the 311 tool. Result shape: `SfLayersResult` in the schema. Every record says what it is:

| `evidence` | Layer (`layer`) | DataSF dataset | Meaning |
| --- | --- | --- | --- |
| `unmeasured_candidate` (`source: "seed"`) | `quiet_candidates` | POPOS `65ik-7wqd`, public libraries `fhhu-wqa7` (names containing Library or Branch) | Might be calm; nobody measured it. Check hours. Candidates are served as geo points, not stored as session `Place` rows (those need AR positions), and `quiet_find_space` still ignores unmeasured places |
| `proxy` | `entertainment_permits` | Active entertainment permits `86e8-rfem` (status Active) | Possible amplified sound; not a level |
| `proxy` | `night_noise_permits` | Night noise permits `e7pr-36bt` (today or tomorrow in SF time; DENIED, WITHDRAWN, PENDING and end dates after 2100 are dropped) | Temporary noise; not a level |
| `proxy` | `street_closures` | Temporary street closures `8x25-yybr` (status Permitted and in effect now) | Event or traffic change; not a level |
| `measured` | `sfo_cnel` | SFO aircraft noise climates `qxw2-ncq3` (`location = 'San Francisco'`, 6 monitors) | Daily CNEL in A-weighted dB at the monitor, published monthly (so weeks old), not at the point |
| `reference_measured` | `references` (with `include_references`) | Central SoMa Plan Draft EIR, Dec 2016, Tables IV.E-2 and IV.E-3 ([PDF](https://sfmea.sfplanning.org/CentralSoMaPlanDEIR_11-iv-e-noise.pdf)) | Ldn dBA: main streets 66-78 (avg 75), alleys 63-67. Old and area-specific, no coordinates |

Rules: only `measured` and `reference_measured` carry dB values, and they must never be compared with the phone's relative dBFS. A layer that cannot be fetched is listed in `unavailable` and is unknown, not quiet. Parks are not included: Recreation and Parks Properties (`wkn6-jn8k`) has no tabular data and RPD Parks (`3nje-yn2u`) is legacy polygons.
