# Team status: who is doing what

Last updated: October 24, 2026, 16:00 PT. Update this file whenever you start or finish something, so two people don't build the same thing.

## In progress right now

| Area | Who | What | Files |
| --- | --- | --- | --- |
| Background capture and noise alerts | Ana | Plan written; check with Ana before touching it | `docs/BACKGROUND_CAPTURE_AND_NOISE_ALERTS.md` |
| Web map and venue view | Ana and Martin | Map-first redesign, DataSF layers, `/venue` 3D view | `apps/quiet-compass/**` |

## Done and on `main`

| Area | Status | Where |
| --- | --- | --- |
| Contracts | Phone ↔ server schema, HTTP API and MCP tool reference | `contracts/` |
| Server: personal memory | Ingest API, the `quiet_*` MCP tools, scoring, guidance; tests pass | `server/quiet_compass/{api,db,scoring,mcp_server}.py` |
| Server: shared sound layer | `query_sound_map`, `find_suitable_places`, `submit_observation`; `POST /v1/contributions`, `PUT /v1/areas/{id}`, public `GET /v1/map/aggregates`; release threshold, ~100 m cells, 5-minute buckets, 24 h retention | `server/quiet_compass/shared_*.py` |
| Server: SF city layers | 311 noise and labelled DataSF layers (`quiet_sf_layers`) | `server/quiet_compass/{city,sf_layers}.py` |
| Server: wearables | Apple Health summaries from the phone, Oura OAuth, kept private | `server/quiet_compass/{wearables,wearable_api}.py`, `docs/WEARABLES_AND_PHONE.md` |
| iOS core | Audio features, direction of arrival (experimental), route back, `PhoneSync`, contracts | `ios/Packages/QuietCore` |
| iOS additions (Chiara) | Capture-mode picker (A/C), Simulator mocks, minimap, arrival check + feedback, Diagnostics with the hour-0 spike tests, opt-in shared summaries to `/v1/contributions`. Not compiled yet. VERIFY on device: FOA API names and channel layout, 48 kHz in measurement mode, classifier 1.5 s window, spike 3 dB threshold, contribution status against the live server. TODO: mode B (zones), world rotation for direction in mode A | `ios/QuietCompass/{UI,Mocks,Sync}`, `App/Companion*`, `Audio/SpikeRunner.swift`, `ios/README.md` |
| iOS app (Martin) | Mic capture and features, ARKit breadcrumbs, places, durable outbox, guidance polling, Health sharing | `ios/QuietCompass/App`, `Health` |
| Hosting config | Render blueprint | `render.yaml`, `docs/AGENT_LEARNING_AND_HOSTING.md` |

## Live services

| Service | URL | Notes |
| --- | --- | --- |
| Server (REST + MCP) | https://quiet-compass-server.onrender.com (`/healthz`, `/mcp`, `/v1/...`) | Render free plan, auto-deploys from `main`. Sleeps when idle (first request is slow; open `/healthz` before demoing). Data is wiped on restart/redeploy. `QC_API_TOKEN` is in the Render dashboard; ask Chiara, never commit it. |
| Map | https://quiet-compass-navy.vercel.app | Vercel (Chiara's account), auto-deploys from `main`. Built with `next build` via `apps/quiet-compass/vercel.json`; the Cloudflare/Sites build is unchanged. The server's `QC_MAP_ALLOWED_ORIGINS` allows this URL plus localhost:5173/3000 |

## Next up (unclaimed — put your name here before starting)

1. ~~Deploy the server for free.~~ Done (see Live services). Option A: a teammate's laptop + `cloudflared tunnel --url http://localhost:8000` (free, no sleep, URL changes on restart). Option B: Render free plan without the disk (stable URL, sleeps when idle, data wiped on restart). The current `render.yaml` uses a paid disk.
2. **Connect the agent.** Add `https://<host>/mcp` as a custom connector in the Claude app. Check whether it can send `Authorization: Bearer`; if not, set `QC_MCP_PATH_SECRET` and use `/mcp/<secret>`. Paste `server/agent_instructions.md` into the project instructions and connect a calendar.
3. **Point the web map at real data.** Read `GET /v1/map/aggregates` instead of synthetic scores. The MCP panel checks server capabilities and documents the 15-minute contribution window. Set `QC_SHARED_API_TOKEN` on the deployed server; `QC_SERVER_URL` overrides the web app's default Render address.
4. **First iOS build on a Mac.** `cd ios && xcodegen generate`, fix compile errors, run in the Simulator, then run the hour-0 spike tests on the iPhone 16 Pro and record the chosen capture mode here.
5. **End-to-end run.** "I need ten minutes of quiet and to be back before the presentations." Label any seeded or synthetic data as such.

## Decisions so far

- Levels are relative dBFS from one capture profile; never label them dBA, and never merge capture profiles.
- The shared layer releases a cohort only after `QC_RELEASE_MIN_CONTRIBUTIONS` contributions (2 by default; set it to 1 for this setup).
- Shared reads require a consented contribution and a 15-minute access receipt. External agents use `/mcp/shared` with `QC_SHARED_API_TOKEN`; the personal `/mcp` and `QC_API_TOKEN` remain private. Set `QC_MAP_ALLOWED_ORIGINS` to allowed browser origins.
- Background capture is levels-only and owned by Ana; the AR route still needs the phone held camera-forward.
- Work lands on `main` via small commits; pull and rebase before pushing, and never force-push.
