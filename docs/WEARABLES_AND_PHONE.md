# Wearables, phone capture and the private agent

Status: October 24, 2026. Software integration verified locally with synthetic
inputs; a live deployment, real Oura account and physical iPhone are still pending.

## Implemented

- Native SwiftUI app: microphone permissions, mono level/features and optional
  on-device sound classification; ARKit pose and walked breadcrumbs; labelled
  places; durable, ordered uploads; guidance polling and route instructions.
- Capture runs only while the app is in the foreground. Backgrounding stops it.
  A new recording starts a new AR coordinate frame. Interrupted tracking stops
  the session rather than joining unrelated frames. Raw audio/images are not saved.
- The outbox writes before sending, preserves IDs across retries/restarts, and
  refuses to deliver old data to a different server. The token lives in Keychain.
- Apple Health: read-only permission per type, previous local calendar day's
  sleep, steps, resting heart rate and HRV SDNN. Overlapping sleep intervals are
  merged. The user previews the summary and explicitly shares it. Missing data
  remains absent. This includes watches that write these types to Apple Health;
  it does not imply a direct integration with every wearable brand.
- Oura: authorization-code flow with PKCE, a ten-minute single-use link, browser
  binding, encrypted tokens and summaries, rotating refresh tokens, manual and
  fifteen-minute sync. It requests only `daily`; it is not a live heart-rate feed.
  Disconnect deletes local records and attempts remote revocation, reporting a
  failure explicitly. Outstanding authorization links are invalidated.
- MCP `quiet_get_personal_context` exposes only summaries and dates. The existing
  environmental tools read phone observations separately. Private wearable data
  is never placed in the public map.

## Deploy and configure

1. Deploy the repository's `render.yaml` on Render, with one instance and one
   worker. It prepares a persistent SQLite disk and generates separate API and
   encryption keys. Creating this paid service needs account authorization.
2. Set `QC_OURA_CLIENT_ID` and `QC_OURA_CLIENT_SECRET` in the service environment
   after registering your application in the [Oura developer portal](https://cloud.ouraring.com/applications).
   Register the **exact** callback `https://YOUR-ASSIGNED-HOST/oauth/oura/callback`.
3. Render supplies the public URL. On another host, set `QC_PUBLIC_URL` to the
   HTTPS origin and include the host in `QC_ALLOWED_HOSTS`. Set `QC_ENCRYPTION_KEY`
   to 32 random bytes encoded as base64 or 64 hex characters. Back up this key
   separately: replacing it makes stored private records unreadable.
4. Run `xcodegen generate` in `ios/` after copying `Config.example.xcconfig` to
   `Config.xcconfig`. Select an Apple signing team with HealthKit enabled and run
   on an ARKit-capable iPhone running iOS 26. No token should be embedded in the app.
5. In the phone app, save the assigned server URL and `QC_API_TOKEN`. Choose
   **Connect Oura**, authorize in the browser, return and tap **Sync Oura**. Or
   choose Apple Health permissions, preview yesterday's data and share the summary.
6. Add `https://YOUR-ASSIGNED-HOST/mcp` to the personal agent with request header
   `Authorization: Bearer <QC_API_TOKEN>`. Use `server/agent_instructions.md`.
   Start a phone recording, mark a place, measure it for 30 seconds, then ask the
   agent for environmental context and personal context.

Keep Uvicorn access logging disabled: callback URLs contain short-lived grants.
Do not enable HTTP wire/debug logging in production. The Oura revoke URL is
redacted from normal `httpx2` request logs. No real credentials belong in Git,
chat, browser-local storage or public JavaScript bundles.

## Private HTTP endpoints

All `/v1` endpoints require the existing bearer token. One installation belongs
to one participant; the shared token is **not** multi-user authentication.

| Method and path | Purpose |
| --- | --- |
| `POST /v1/wearables/oura/link` | Create a one-use connection URL for the browser |
| `GET /connect/oura?ticket=...` | Consume the link; establish browser cookie and redirect to Oura |
| `GET /oauth/oura/callback` | Verify state, cookie and PKCE; store encrypted tokens |
| `POST /v1/wearables/oura/sync` | Fetch last available daily values, with dates and warnings |
| `GET /v1/wearables/context` | Last shared private summaries and configuration status |
| `PUT /v1/wearables/apple-health` | Save an explicit daily summary, maximum 64 KiB |
| `DELETE /v1/wearables/apple_health` | Delete the shared Health summary |
| `DELETE /v1/wearables/oura` | Delete Oura records and attempt provider revocation |

The health upload format is `contracts/wearable-summary.schema.json`. It is a
separate contract; the existing acoustic observation v1 schema is unchanged.
An empty source is unknown. `captured_at` is retrieval time, while each metric's
`day` is the day it describes. Outages retain the original timestamp rather than
making old data look fresh. Oura scopes can be declined; unavailable metrics stay
absent. No data is used to diagnose stress or automatically infer preferences.

Deleting the Apple Health summary does not revoke OS permission. Revoke access
in the iPhone's Health settings if desired; the app never uploads Health data
without pressing Share. Deletion removes active database records, not old backups.

## Verification evidence

| Check | Result |
| --- | --- |
| Server suite | 100 tests passed after merging the shared sound layer and latest SF sources, including eight wearable tests |
| Server lint | Ruff passed |
| QuietCore package | 55 tests passed: existing DSP/routes plus offline retry, persistence, destination isolation and sleep overlap |
| Real local HTTP round trip | Swift client → Python ingest → MCP context → guidance → phone acknowledgement passed with synthetic data |
| Native app | Compiled for iOS Simulator, arm64 and x86_64 |
| App test | One launch/model smoke test passed on iPhone 17 Pro simulator, iOS 26.5 |
| Real Oura/account scopes | Not tested; credentials and consent needed |
| Physical audio, camera, Apple Watch/Health | Not tested; signed app and a physical device needed |
| Render deployment/restart persistence | Not tested; no service exists yet |

Reproduce server tests with `cd server && pytest -q && ruff check .` and Swift
checks with `swift test --package-path ios/Packages/QuietCore`. With the server's
Python environment activated, run `python scripts/test_phone_server.py` at the
repo root for the HTTP/MCP integration. This creates a temporary database and
local server, uses synthetic values, then terminates the server and deletes data.
The live integration test skips during ordinary Swift test runs.

## Remaining work

- Deploy and register real credentials, then verify data arrival, token renewal,
  disconnect and restart persistence against Oura and a real phone.
- Build the explicit agent runtime that reacts to events and delivers notifications.
  MCP serves calls; Oura polling does not run the conversational agent.
- Persist a personal preference profile across sessions. Current feedback affects
  ranking within the active session; it is not a trained cross-session model.
- Add an explicit opt-in phone flow for the new shared map contribution API.
  Main now serves released acoustic aggregates; private phone and wearable rows
  are not published automatically. The old browser Oura flow remains separate.
- Add account isolation before serving multiple people on one server. Add
  retention controls, verified backup restoration and physical route validation
  before treating this as a production service.
- A killed app starts a new recording. Old uploads are recovered, but AR world
  maps and routes are not restored across launches. FOA spatial modes A/B remain
  library code; the working app selects mode C and does not promise directions
  of individual sound sources.

References: [Oura OAuth and token renewal](https://cloud.ouraring.com/docs/authentication),
[Apple Health authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data),
[Render generated secrets](https://render.com/docs/blueprint-spec).
