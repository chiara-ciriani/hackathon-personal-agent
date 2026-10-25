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
| `GET /v1/sessions/{session_id}/sound_field` | none | `200` floor-plane grid of the session's readings (see "Sound field"), `404` unknown session |
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
| `quiet_get_sound_map()` | Up to 3 quiet spots on the walked floor (x/z, relative level, confidence, age, distance), readings count and covered area | read-only |
| `quiet_city_noise_reports(lat, lon, radius_m, hours)` | Optional: SF 311 noise report counts by subtype | read-only, open world |
| `quiet_sf_layers(lat, lon, radius_m?, include?, include_references?)` | Optional (same flag as above): real SF layers near a point, each labelled with an `EvidenceLabel` | read-only, open world |

## Sound field

`server/quiet_compass/sound_field.py` turns every positioned reading of a session into a grid of
0.5 m cells on the AR floor plane (x/z metres). A reading without its own position borrows its
crumb's, then its place's. Each cell blends nearby readings with a Gaussian weight on distance
(σ 1.5 m) times exp(−age/20 min), so newer readings win; `confidence = 1 − exp(−Σw)`. Cells
more than 3 m from every reading have `level_db: null` (unknown, never quiet). Quiet spots are
the quietest cells within 1 m of a real reading. `GET /v1/venue/sound_field` serves the active
session's grid to the venue page without a token only when `QC_PUBLIC_VENUE_FIELD=1` (it reveals
where the user walked); otherwise it answers 404.

The MCP tools act on the **active session**: the one named by `QC_ACTIVE_SESSION_ID` if set, otherwise the most recently updated session.

## SF city layers (`quiet_sf_layers`)

Enabled with `QC_CITY_LAYER_ENABLED=1`, together with the 311 tool. Result shape: `SfLayersResult` in the schema. Every record says what it is:

| `evidence` | Layer (`layer`) | DataSF dataset | Meaning |
| --- | --- | --- | --- |
| `unmeasured_candidate` (`source: "seed"`) | `quiet_candidates` | POPOS `65ik-7wqd`, public libraries `fhhu-wqa7` (names containing Library or Branch), Recreation and Parks Properties `gtr9-ntp6` (255 rows with lat/long; types Neighborhood Park or Playground, Mini Park, Regional Park, Civic Plaza or Square, Parkway, Community Garden; `kind: "park"`) | Might be calm; nobody measured it. Check hours; parks and playgrounds can be loud. Candidates are served as geo points, not stored as session `Place` rows (those need AR positions), and `quiet_find_space` still ignores unmeasured places |
| `proxy` | `entertainment_permits` | Active entertainment permits `86e8-rfem` (status Active) | Possible amplified sound; not a level |
| `proxy` | `night_noise_permits` | Night noise permits `e7pr-36bt` (today or tomorrow in SF time; DENIED, WITHDRAWN, PENDING and end dates after 2100 are dropped) | Temporary noise; not a level |
| `proxy` | `street_closures` | Temporary street closures `8x25-yybr` (status Permitted and in effect now) | Event or traffic change; not a level |
| `proxy` | `street_work_permits` | Active street-use permits `x8nh-xzn6` (types Excavation, ExcStreet, Boring, StrtImprov, SideSewer; valid today in SF time; NightNoise left out because `e7pr-36bt` covers it) | Possible daytime construction noise; permits span weeks, so work may not be happening now; not a level |
| `proxy` | `cad_noise_calls` | Law enforcement dispatched calls, closed `2zdj-bwza` (`call_type_final_desc = 'NOISE NUISANCE'`, last 24 hours (closed calls publish about a day late), `intersection_point` exactly as published, `sensitive_call` rows and duplicate `cad_number` dropped) | Counts of complaints per masked intersection (`count`, `observed_on` = latest call); not measurements and they depend on who calls |
| `measured` | `sfo_cnel` | SFO aircraft noise climates `qxw2-ncq3` (`location = 'San Francisco'`, 6 monitors) | Daily CNEL in A-weighted dB at the monitor, published monthly (so weeks old), not at the point |
| `measured` | `sfo_events` | SFO noise exceedance events `tiju-qyvs` (30 `location_id` monitors; only the 6 with `location = 'San Francisco'` in `qxw2-ncq3` are placed, joined by `location_id`; `max_level` is text and parsed; last 365 days) | Per monitor: `count`, `median_level_db`, `max_level_db` (dBA) and `observed_on` (latest event). Only events above that monitor's day/night threshold are published, so it describes loud aircraft events, not typical noise. Monitors without events in the window are omitted. **The portal declares no license** for this dataset (checked 2026-10-24). Data ended 2026-08-31 at check time |
| `measured_crowdsourced` | `noisecapture` | NoiseCapture / Noise-Planet dump, `https://data.noise-planet.org/dump/United States.zip` (ODbL; county files `United States_California_San Francisco.{points,tracks}.geojson`), aggregated offline by `server/quiet_compass/noisecapture.py` into `server/quiet_compass/data/noisecapture_sf_cells.json` | ~100 m cells, `quality: "measured_crowdsourced_uncalibrated"`, `median_level_db` (median 5-minute LAeq), `laeq_db` (energy mean), `count` (5-minute windows). Filters: GPS accuracy <= 15 m, 30-120 dB, track `gain_calibration` within +-15 dB, >= 5 s per window, cells need >= 3 tracks and >= 5 windows. Sparse (20 cells), 2017-2025, not live. Attribute NoiseCapture / Noise-Planet (ODbL) |
| `reference_measured` | `references` (with `include_references`) | Central SoMa Plan Draft EIR, Dec 2016, Tables IV.E-2 and IV.E-3 ([PDF](https://sfmea.sfplanning.org/CentralSoMaPlanDEIR_11-iv-e-noise.pdf)) | Ldn dBA: main streets 66-78 (avg 75), alleys 63-67. Old and area-specific, no coordinates |

Rules: only `measured`, `measured_crowdsourced` and `reference_measured` carry dB values (`proxy` and `unmeasured_candidate` never do), and they must never be compared with the phone's relative dBFS. A layer that cannot be fetched is listed in `unavailable` and is unknown, not quiet. Parks come from `gtr9-ntp6` (the older `wkn6-jn8k` has no tabular data and `3nje-yn2u` is legacy polygons); the playgrounds/courts facilities dataset `ib5c-xgwu` (2678 facilities) was not integrated. Label sets stay separate: `measured` / `measured_crowdsourced` / `proxy` / `unmeasured_candidate` (plus `reference_measured` and the web-only synthetic walkthrough).

## Shared sound layer

A separate, coarse layer of consented summaries that other agents and the web map can read. Its payload has its own `schema_version: "0.1"` inside the v1 HTTP envelope. Definitions: `SharedContribution`, `ContributionUpload`, `ContributionResult`, `AreaUpsert`, `Area`, `AreaAggregate`, `SoundMapResponse`.

`SharedContribution` fields (the iOS model mirrors these names exactly): `id` (client UUID), `schema_version`, `area_id`, `area_name?`, `lat?`/`lon?` (3 decimals, together or neither), `time_bucket` (5-minute UTC floor), `duration_seconds`, `measurement {kind: "relative_uncalibrated", rms_dbfs <= 0, frame_level_spread_db >= 0, peaks_per_min?, calibrated: false}`, `quality {capture_profile, clipping_detected}`, `source` (`device` or `simulated`). It never carries audio, transcripts, routes, identity, preferences or health data.

| Method and path | Auth | Body | Response |
| --- | --- | --- | --- |
| `POST /v1/contributions` | owner/shared bearer | `ContributionUpload` with `share_consent: true` | `200 ContributionResult` (`accepted`, `withheld` or `rejected` with `reason`); `422` on schema errors |
| `PUT /v1/areas/{area_id}` | bearer | `AreaUpsert` | `200 Area` |
| `GET /v1/map/aggregates?lat&lon&radius_m=500&since_minutes=60` | owner/shared bearer + `X-QC-Access-Receipt` | none | `200 SoundMapResponse`; 428 if contribution required |

Server rules: lat/lon are re-rounded and buckets re-floored; unknown `area_id` with coordinates becomes `cell:<lat>,<lon>`, without coordinates it is rejected; implausible values (`rms_dbfs < -120`, spread `> 60`, duration outside 5-600 s, future or expired buckets) are rejected; at most 3 contributions per area, bucket and capture profile; duplicate ids are idempotent; clipping is stored and counted. A cohort (area, bucket, capture profile) is released only with at least `QC_RELEASE_MIN_CONTRIBUTIONS` contributions (default 2). Capture profiles are never merged. Contributions are deleted after `QC_CONTRIBUTION_RETENTION_HOURS` (default 24).

Shared reads require a contribution receipt. Submit a recent device summary with explicit
`share_consent: true` (default false). A plausible, unclipped measurement with a normalized
bucket from the last 15 minutes returns `access_receipt` and `access_expires_at`, including
when status is `withheld`. One receipt allows unlimited queries for 15 minutes from first
acceptance. Retries and identical normalized payloads under a different UUID never extend
the deadline or increment the cohort. Reusing an ID with different data is rejected.
Simulated, clipped, old and rejected measurements do not grant access. Receipt state is
persistent and checked by REST and MCP. Never put receipts or API keys in browser bundles.

External agents use `/mcp/shared` with `QC_SHARED_API_TOKEN`, which must differ from the
owner's `QC_API_TOKEN`. Only the three shared tools exist there. `/mcp` remains private;
its shared reads obey the same policy. `GET /v1/exchange/status` exposes only public
capability metadata (`contribution-window-v1`, 900-second window, endpoint enabled, tools).
This policy changes the previously public shared read; existing clients must migrate.

| MCP tool | Purpose | Annotations |
| --- | --- | --- |
| `query_sound_map(lat, lon, radius_m=500, since_minutes=60)` | Released aggregates near a point plus an `unknown_coverage` note | read-only |
| `find_suitable_places(goal, lat, lon, max_walk_minutes=10, return_by?, max_age_minutes=30)` | Candidates ranked within a capture-profile cohort, with supporting observations, age, uncertainty and a straight-line walk estimate; or `{no_fit, reason}` | read-only |
| `submit_observation(<SharedContribution fields>, share_consent=true)` | Same as `POST /v1/contributions` | idempotent, not destructive |

The web map's MCP panel (`apps/quiet-compass/app/page.tsx`) shows an earlier proposal of these tools with different inputs (`bounds`, `zone_id`, `acoustic_summary`). The tool names match; the parameters above are the implemented ones.

The web map can read the same released shared aggregates through `GET /v1/map/view`.
This fixed San Francisco view covers 5 km around 37.77, -122.43 and the last 24 hours.
It accepts a valid contribution receipt as its bearer capability and includes only real-device
cohorts. The existing release threshold still applies. Browser measurement completion passes
this capability through the web relay into a Secure, HttpOnly, SameSite=Strict cookie scoped
to `/api/map`. The browser map receives GeoJSON, never the receipt or an account API key.
The server checks the original 15-minute expiry on every read; retries do not renew it.
Disconnecting phone sensors does not revoke an already-earned contribution receipt.
Private native room walks are excluded. Direct REST and MCP queries keep their existing auth.

Both shared query tools take `access_receipt` (the value from submission). Missing, invalid or expired receipts return an MCP tool error containing `contribution_required`. Private tools and independent external city data are unaffected. Device provenance is caller-asserted, not hardware-attested.
