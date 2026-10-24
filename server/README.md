# Quiet Compass memory service

The Python service exposes authenticated ingestion at `/v1` and MCP tools at
`/mcp`, backed by SQLite. The implementation uses Starlette and the MCP Python SDK.
The web map and its Oura connection remain separate in `apps/quiet-compass`.

## Run locally

From this directory, use Python 3.12 or later:

```sh
python3.12 -m venv .venv
. .venv/bin/activate
pip install -e '.[dev]'
cp .env.example .env
# Edit .env and replace QC_API_TOKEN with a long random value.
uvicorn quiet_compass.app:create_app --factory --env-file .env --reload
```

`--env-file` loads the configuration; copying `.env` alone does not load it.
`GET /healthz` is public and returns `{"ok":true}`. Every `/v1` operation and the
default `/mcp` endpoint require `Authorization: Bearer <QC_API_TOKEN>`.

```sh
ruff check .
pytest -q
```

The HTTP payloads and tool parameters are in [the contract](../contracts/README.md).
No observations are created automatically. An empty service reports that there
is no recording session. Fixtures in `tests/` are synthetic test data.

## Host the demo on Render

The root [render.yaml](../render.yaml) prepares one Python web service in Oregon,
one worker process, a generated API token and a 1 GB persistent disk. The database
lives at `/var/data/quiet_compass.db`. Importing the Blueprint creates paid
resources; check the current [Render prices](https://render.com/pricing) before
creating the service. No cloud resources are created by committing this file.

1. In Render, create a Blueprint from this GitHub repository and branch `main`.
2. Review the service and disk, then create them. The Blueprint starts Uvicorn on
   Render's assigned port and checks `/healthz`.
3. Copy the assigned HTTPS base URL. Use the actual URL from Render, not the
   example name in these documents. `RENDER_EXTERNAL_HOSTNAME` is automatically
   added to the MCP host allowlist; custom domains go in `QC_ALLOWED_HOSTS`.
4. Retrieve the generated `QC_API_TOKEN` from the service's environment settings.
   Configure it in the phone and the agent connector, never in Git or a chat.
5. Register a recording session from the phone. Set `QC_ACTIVE_SESSION_ID` to that
   session's UUID for the demo. Without it, tools select the last updated session.
6. Confirm that a valid connector can list tools, an unauthorized call fails,
   and saved observations are still present after a restart.

Subsequent backend commits deploy after linked CI checks pass. A disk-backed
service has a brief interruption during deployment and cannot share its disk
across replicas. Keep one instance. The free service has no persistent disk and
does not fit this SQLite setup. The disk survives restarts; deletion of the
service/disk is a separate operation. Before destructive operations, export a
consistent SQLite backup using the SQLite backup API and verify restoration.

This is a **single-user demo backend**. Its shared token can access every session
in its database. An active-session setting selects context; it does not enforce
user isolation. Do not connect unrelated participants to the same instance as
though it provided private accounts. Multi-user hosting needs authenticated
ownership on every record and query, followed by a database migration plan.

## Connect the agent and phone

For Claude, add the actual `https://<assigned-host>/mcp` URL as a custom connector
and set a fixed request header `Authorization: Bearer <QC_API_TOKEN>`. Enable the
connector in the conversation and use [agent_instructions.md](agent_instructions.md).
This server implements bearer authentication, not an OAuth authorization server.
Keep `QC_MCP_PATH_SECRET` unset for this deployment.

In `ios/Config.xcconfig`, set `QC_SERVER_URL` and the same token. The example
configuration explains the `https:/$()/host` escaping required by xcconfig.
Starting guidance records a target; it does not prove the phone received or
displayed it. Verify that behavior on a connected device.

## Wearables, learning and proactive help

Oura authorization currently belongs to the Sites browser session. The Python
server has no Oura token store or wearable tool. Apple Health integration and a
background agent runner are also pending. Do not expose browser cookies as MCP
credentials. See [the implementation boundaries and next steps](../docs/AGENT_LEARNING_AND_HOSTING.md).

## Hosting references

Reviewed October 24, 2026:

- [Render web services and ports](https://render.com/docs/web-services)
- [Blueprint fields and deployment triggers](https://render.com/docs/blueprint-spec)
- [Persistent disks and their limitations](https://render.com/docs/disks)
- [Assigned host environment variable](https://render.com/docs/environment-variables)
- [Claude custom connectors and request headers](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)

## Shared sound layer

Alongside the personal `quiet_*` tools, the service keeps a shared layer of
consented acoustic summaries (`SharedContribution` in
[the contract](../contracts/README.md#shared-sound-layer)). Code lives in
`quiet_compass/shared_*.py`; its tables (`areas`, `contributions`) share the
SQLite file but are separate from the personal session tables.

| Interface | Auth | Purpose |
| --- | --- | --- |
| `POST /v1/contributions` | bearer | Submit one summary; returns `ContributionResult` |
| `PUT /v1/areas/{area_id}` | bearer | Register an indoor zone or named area |
| `GET /v1/map/aggregates?lat&lon&radius_m&since_minutes` | public, CORS | Released aggregates for the web map |
| MCP `query_sound_map`, `find_suitable_places`, `submit_observation` | bearer | Agent access to the same layer |

Policy, enforced on the server:

- Coordinates are re-rounded to 3 decimals (~100 m) and times floored to 5-minute
  UTC buckets. An unknown `area_id` with coordinates becomes the outdoor cell
  `cell:<lat>,<lon>`; an unknown `area_id` without coordinates is rejected.
- Rejected: `rms_dbfs` above 0 or below -120, spread above 60 dB, duration outside
  5-600 s, buckets in the future or older than the retention window, and more than
  3 contributions per area, bucket and capture profile. Clipped readings are stored
  and counted in `clipped_count`. Resending an `id` is idempotent.
- An (area, bucket, capture profile) aggregate is released only once it has
  `QC_RELEASE_MIN_CONTRIBUTIONS` distinct contributions (default 2; a one-phone
  demo can set 1). Until then the result is `withheld`. Capture profiles are never
  merged, and `find_suitable_places` ranks quietness only within one profile.
- Contributions older than `QC_CONTRIBUTION_RETENTION_HOURS` (default 24) are
  deleted on every write. Aggregates are computed on read, so they expire too.

**Why the map read is public.** The web map shows exactly the released aggregates
to anyone who opens it, so requiring the API token there would only push the token
into browser code. `GET /v1/map/aggregates` therefore needs no token and sends CORS
headers for `QC_MAP_ALLOWED_ORIGINS` (default `*`; set the map's origin in
production). It never returns withheld cohorts, contribution ids or personal
session data. Every write still requires the bearer token.

These are design defaults, not an anonymity guarantee: coarse place-time data can
still reveal patterns, and the shared token means any holder can contribute.
Label seeded or replayed data with `source: "synthetic_demo"`.
