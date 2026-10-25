# Agent → phone → recommendation

The mobile page is `/measure`. It is a sensor connection, not a manual measuring/export form.

## Native room analysis from the same link

Install the current `ios-walk/` build, then open the agent's phone link on the iPhone.
Choose **Open iPhone app** and approve **Allow agent analysis** in QC Walk Map.
The app gets a short-lived phone capability, never an owner/shared API key. Requests
use the fixed Vercel relay; app links cannot choose an arbitrary server.

1. Agent: `connect_phone`, then wait for `phone_measurement_status.client == "native"`.
2. Agent: `request_phone_measurement(phone_session_id, mode="walk", duration_seconds=60)`.
   The user walks with the camera forward; only acoustic levels and ARKit positions are sent.
3. Agent: poll status every five seconds. A complete job returns `walk.analysis` (energy-mean,
   median, range and variation), current level, quiet spots and an optional experimental FOA
   bearing. Incomplete, clipped or unavailable data must not become a quiet recommendation.
4. Agent: `send_phone_recommendation(..., action="move", spot_index=0)` only for a returned
   spot at least 3 dB quieter. The app displays advice and a straight-line direction in the
   same AR session. Direction pauses when tracking is unavailable; it is not a safe route.
5. Disconnect, backgrounding, expiry or connection failure turns off the sensors.

Native maps stay private to the pairing and grant no shared-query receipt. Local maps,
replay, export, compass and radar remain available; advanced controls are disabled during
agent capture to avoid mixing profiles or coordinate systems. Physical ARKit/FOA validation
and a real Dot connection remain pending. Loading the page installs neither the app nor Dot.

## Browser sound measurement

## User flow

1. The authenticated agent calls `connect_phone` and shows the returned `connect_url`.
   The user opens that link on their own phone.
2. On the phone, the user explicitly approves microphone use, approximate location and
   automatic sharing of acoustic summaries for this connection (at most 15 minutes).
   The phone gets browser permissions and keeps the audio context alive for iOS.
3. The agent calls `request_phone_measurement(phone_session_id)`. The phone polls for commands,
   takes exactly 30 seconds of samples, computes a summary locally, and submits it automatically.
4. The agent polls `phone_measurement_status(phone_session_id)` at intervals of at least five
   seconds. A completed job contains the real phone-reported summary and
   `contribution_result.access_receipt` / `access_expires_at`.
5. The agent calls `find_suitable_places` with that receipt, the phone's coarse location,
   the user's goal, walk limit and return deadline. It explains evidence and uncertainty.
6. It calls `send_phone_recommendation` to display its advice on the connected phone.
   `action` is `move`, `stay` or `unknown`. A move must cite a recent released
   destination from the same capture profile, with only real, unclipped observations,
   a level at least 3 dB below the current reading, and a feasible return time if supplied.
   This 3 dB margin is a product heuristic, not a health threshold or guarantee of comfort.
   Missing comparable data must produce an honest unknown result, not a guessed destination.
   Queued advice is not proof the user read it.
7. Leaving/hiding the page, disconnecting, loss of the microphone or expiry closes the sensors.
   The agent cannot reactivate them without a new authorized connection.

Browser mode needs no native installation. Both modes avoid per-reading copy/paste and API-key entry.
Do not open a user's connection link on an agent computer and call that a phone measurement.

## Deployment

- Deploy the latest `main` on both Vercel and Render.
- Keep `QC_SHARED_API_TOKEN` configured on Render for external MCP clients.
- `QC_PHONE_PAGE_URL` defaults to `https://quiet-compass-navy.vercel.app/measure`.
  Override it when hosting the phone page elsewhere.
- The web server uses `QC_SERVER_URL` (default: the existing Render server).
- `GET /v1/exchange/status` must include
  `phone_measurement.protocol = "phone-bridge-v1"` and, for the app,
  `phone_measurement.native_protocol = "phone-walk-v1"`.
- Clients use the existing authenticated `/mcp/shared`. This change does **not**
  add ChatGPT/Dot OAuth or install a plugin in the user's account. That connection
  remains a separate prerequisite; do not report Dot connected merely because this page loads.
- Render's existing free service has ephemeral storage. A restart/redeploy may invalidate
  phone links and acoustic history; ask the agent for a new link, never silently reauthorize.

## Data and permission boundaries

Both sides hold separate random 256-bit capabilities. Only their hashes are stored.
The agent session handle cannot be used as a browser capability, and the browser never receives
the shared MCP credential or accesses private routes. The browser capability travels in a URL
fragment initially, is immediately removed from the page URL, and stays only in memory.
Phone endpoints accept it as an Authorization header through a fixed-destination web relay.

Connections expire after 900 seconds. Explicit phone-side consent is required before the
server accepts a command/result. Browser requests expire after 90 seconds; native requests expire after their duration plus 60 seconds. Concurrent requests reuse
the pending job; only one poll claims it. Retries retain the same request ID and payload, so a
lost network response cannot generate another contribution or renew its receipt.
A disconnected or stale phone is never reported as a completed measurement.

AudioWorklet processes PCM in 125 ms frames without transferring or storing the audio.
The summary contains energy-mean RMS dBFS, percentile-90 minus percentile-10 spread, rising
onsets above the running median + 10 dB normalized per minute, and sample-peak clipping.
There is no calibrated SPL/dBA, speech transcription, Oura reading, direction or indoor route.
GPS must be fresh and report accuracy within 100 m; coordinates are rounded before transmission.
Actual browser audio-processing settings and a random connection discriminator form the profile,
preventing incompatible phones or sessions from being compared. Processing cannot always be
disabled on phone browsers, so readings remain explicitly relative and uncalibrated.

The server accepts only typed summaries matching an issued request. It does not provide
cryptographic hardware attestation: source is `phone_reported_summary`. Never describe test
fixtures or this software validation as proof of a real iPhone/Dot run.

## Verification

- `node --test tests/*.test.mjs` in `apps/quiet-compass`: DSP math, incomplete/missing/clipped
  input, coarse coordinates, relay limits, waiting for agent commands, cancellation and late
  permission cleanup with isolated API doubles.
- `pytest server/tests/test_phone_bridge.py`: real MCP/REST request pipeline using synthetic
  fixtures, role isolation, consent, duplicate requests/results, restart, revocation,
  expiry, unknown destinations and delivery of evidence-backed advice.
- `VERCEL=1 pnpm exec next build` and the repository's Sites/Vinext build.
- Physical phone microphone, browser permission behavior and the actual Dot connection still
  require an authorized live device test.

## End-to-end software test

`npx e2e@latest init` was run for the existing web app. The SDK is pinned to
`e2e@0.21.2` and `@e2e-dev/web@0.15.2`, which satisfy the dependency age policy;
no security exceptions are configured. Install with `pnpm install` in the web app.

Run an isolated local server (from the repository root, with the server environment active):

```sh
QC_API_TOKEN=local-e2e-owner-only QC_SHARED_API_TOKEN=local-e2e-shared-only \
QC_DB_PATH=/tmp/quiet-compass-e2e.db QC_PHONE_PAGE_URL=http://localhost:5180/measure \
PYTHONPATH=server python -m uvicorn quiet_compass.app:create_app --factory --host 127.0.0.1 --port 8810
```

In `apps/quiet-compass`, start the web and then run the test in another terminal:

```sh
VERCEL=1 QC_SERVER_URL=http://127.0.0.1:8810 pnpm exec next dev --hostname 127.0.0.1 --port 5180
APP_URL=http://localhost:5180 E2E_TELEMETRY_DISABLED=1 pnpm test:e2e
```

Use localhost for the browser URL so Next's canonical request URL and the browser Origin
match. The same-origin check remains enforced. The suite refuses remote targets and checks
mobile-width linking, explicit approval, MCP → relay → native summary → acoustic analysis →
measured destination → advice → disconnect. Its native sensor input is a synthetic fixture.
Swift's AgentCheck validates the actual native encoder against the same payload contract.
This does not verify physical microphone/ARKit accuracy, OS permission prompts or actual Dot auth.
