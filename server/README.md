# Quiet Compass memory service

The Python service exposes authenticated ingestion at `/v1` and MCP tools at
`/mcp`, backed by SQLite. The implementation uses Starlette and the MCP Python SDK.
The web map's older browser-cookie Oura connection remains separate in
`apps/quiet-compass`; the native app uses this server's private wearable connection.

## Run locally

From this directory, use Python 3.12 or later:

```sh
python3.12 -m venv .venv
. .venv/bin/activate
pip install -e '.[dev]'
cp .env.example .env
# Edit .env and replace QC_API_TOKEN with a long random value.
uvicorn quiet_compass.app:create_app --factory --env-file .env --reload --no-access-log
```

`--env-file` loads the configuration; copying `.env` alone does not load it.
`GET /healthz` is public and returns `{"ok":true}`. Private `/v1` operations and the default `/mcp` endpoint require
`Authorization: Bearer <QC_API_TOKEN>`. The shared exchange has a separate
credential and contribution receipts; see below. Its capability status is public.

```sh
ruff check .
pytest -q
```

The HTTP payloads and tool parameters are in [the contract](../contracts/README.md).
No observations are created automatically. An empty service reports that there
is no recording session. Fixtures in `tests/` are synthetic test data.

## Host on Render

The root [render.yaml](../render.yaml) prepares one Python web service in Oregon,
one worker process, separate generated owner/shared API tokens and a 1 GB persistent disk. The database
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
   session's UUID for this setup. Without it, tools select the last updated session.
6. Confirm that a valid connector can list tools, an unauthorized call fails,
   and saved observations are still present after a restart.

Subsequent backend commits deploy after linked CI checks pass. A disk-backed
service has a brief interruption during deployment and cannot share its disk
across replicas. Keep one instance. The free service has no persistent disk and
does not fit this SQLite setup. The disk survives restarts; deletion of the
service/disk is a separate operation. Before destructive operations, export a
consistent SQLite backup using the SQLite backup API and verify restoration.

This is a **single-user backend**. Its owner token (`QC_API_TOKEN`) can access every session
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

Enter the server URL and the same API token in the native app's Connection section.
The token is stored in Keychain, not in the application bundle.
Starting guidance records a target; it does not prove the phone received or
displayed it. Verify that behavior on a connected device.

## Wearables, learning and proactive help

The server now supports Oura OAuth with PKCE, encrypted token storage, rotating
refresh tokens, periodic sync and disconnection. It accepts explicitly shared
Apple Health summaries and exposes `quiet_get_personal_context` through MCP.
Set `QC_ENCRYPTION_KEY` for private storage; Oura additionally requires
`QC_OURA_CLIENT_ID`, `QC_OURA_CLIENT_SECRET` and a public URL. Keep one worker.
See [setup, endpoints and verification](../docs/WEARABLES_AND_PHONE.md).

The autonomous agent runner and learning a profile across sessions are still
pending. Oura's polling task only updates data; it does not invoke a model or
send notifications. Do not expose browser cookies as MCP credentials.

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
`quiet_compass/shared_*.py`; its tables (`areas`, `contributions`, `contribution_access`) share the
SQLite file but are separate from the personal session tables.

| Interface | Auth | Purpose |
| --- | --- | --- |
| `POST /v1/contributions` | owner or shared bearer | Submit one summary with `share_consent: true`; returns `ContributionResult` |
| `PUT /v1/areas/{area_id}` | owner bearer only | Register an indoor zone or named area |
| `GET /v1/map/aggregates?lat&lon&radius_m&since_minutes` | owner/shared bearer + `X-QC-Access-Receipt` | Released aggregates; missing/expired receipt returns 428 |
| `/mcp/shared` | shared bearer only | Three shared tools; both read tools require `access_receipt` |
| `GET /v1/exchange/status` | public | Protocol and availability only; no measurements or credentials |

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
  walkthrough can set 1). Until then the result is `withheld`. Capture profiles are never
  merged, and `find_suitable_places` ranks quietness only within one profile.
- Contributions older than `QC_CONTRIBUTION_RETENTION_HOURS` (default 24, minimum 0.5 to preserve a full access window) are
  deleted on every write. Aggregates are computed on read, so they expire too.

**Contribution before queries.** A recent, plausible device measurement with explicit
`share_consent: true` and no clipping returns a random `access_receipt` valid for
15 minutes from its first acceptance, including when `status` is `withheld`.
A measurement's normalized 5-minute bucket must fall within the last 15 minutes.
Pass the receipt as a tool argument or the REST `X-QC-Access-Receipt` header.
Reads never consume it. After expiry, submit a new measurement. Simulated, old,
clipped, rejected, or legacy uncredited rows do not unlock queries. Exact duplicate
summaries (even with a new UUID) return the original receipt and deadline and do
not increase the cohort count. Reusing an ID with different data is rejected.
Receipt creation and insertion are one SQLite transaction and survive restarts.

**External agent setup.** Set `QC_SHARED_API_TOKEN` to a separate random value of
at least 16 characters (the Render Blueprint generates it). Configure external
agents at `https://YOUR-SERVER/mcp/shared` with
`Authorization: Bearer <QC_SHARED_API_TOKEN>`. Never give them `QC_API_TOKEN` or
the private path secret. The shared endpoint exposes only three tools, no personal
health, session memory or guidance. It returns 503 until configured. Keep the
owner connector at `/mcp` for the personal agent. Its shared queries also require
a receipt; private `quiet_*` tools do not.

**Web setup.** Set `QC_SERVER_URL=https://YOUR-SERVER` in the web app's server
runtime. The current default is `https://quiet-compass-server.onrender.com`; override it
for another installation. The MCP panel checks public capability metadata and shows the connector
address and copyable setup. It never embeds either API token, proxies shared reads,
or claims that an agent is connected just because the server responds. A real
agent needs an HTTP MCP client that can send the shared bearer header. The page's
illustrative map and existing external city data remain separately labelled;
opening the page grants no server receipt.

This replaces the formerly public map read. Update shared clients to send consent
on submission and the receipt on reads. Configure `QC_MAP_ALLOWED_ORIGINS` for
allowed browser origins; CORS never replaces authorization. Keep receipts out of
URLs, logs and public responses. See [agent_instructions.md](agent_instructions.md)
for the exact contribution/query sequence.

These are design defaults, not an anonymity guarantee: coarse place-time data can
still reveal patterns, and the shared token means any holder can contribute.
Label seeded or replayed data with `source: "simulated"`.

The server checks payloads and replay, not hardware authenticity. `source: device`
is asserted by the caller, and a shared credential/receipt can be copied by its
holder. This is not per-agent identity, sensor attestation or Sybil resistance.
Identical normalized readings in the same cell, bucket and capture profile are
conservatively treated as one contribution. Trusted device provenance and
individual agent credentials are separate future work.
