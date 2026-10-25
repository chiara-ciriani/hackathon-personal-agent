# Quiet Compass

A personal agent that remembers how the places you walked through sounded, learns which ones are comfortable for you, and helps you get back to one when you need less noise, without losing track of what you came to do.

It was built for an SF hackathon on personal agents for everyday life. The first use case is noise-sensitive people (for example, autistic attendees) at a busy event.

## How it works

1. **The iPhone app measures.** It turns microphone audio into relative loudness features on the phone, tagged with where you are. ARKit records the path you walked.
2. **The memory service remembers.** It stores those features (never audio) and ranks places for a goal (talk, rest or work) and a time budget.
3. **The agent decides.** The Claude app, connected through a custom MCP connector, reads your calendar and the sound memory, suggests a place, and asks the phone to guide you back along the path you walked.

```
apps/quiet-compass/  Next.js web app: SF noise map, Oura integration and agent-controlled phone mode at /measure
ios/                 SwiftUI app (QuietCompass) + QuietCore Swift package (DSP, route logic, contracts)
ios-walk/            Alex’s standalone QC Walk Map app: local walk map, radar, compass and replay
server/              Starlette ingest API + MCP Python SDK + scoring + optional SF 311 city layer
contracts/           JSON Schema shared by phone and server, plus the HTTP API and MCP tool reference
docs/                Implementation plan and product brief
```

## Choose a mode

- **Quiet Compass app (`ios/`):** measures while walking, uploads private summaries and
  the walked route, and receives guidance from the connected agent. The existing app stays available.
- **QC Walk Map (`ios-walk/`):** Alex’s standalone app from `feat/sound-field`, now included
  in `main`. Walk, see the local sound map, save and replay walks, and export summaries.
  It works locally without a server, or opens the `/measure` link to accept agent-requested sound analyses and return recommendations after approval.
  Start with [the iPhone setup](ios-walk/START_HERE.md).
- **Agent mode (`/measure`):** open the link supplied by the connected agent on your phone,
  approve microphone/location/sharing once, and keep the page visible. The agent requests
  measurements, receives summaries and sends recommendations back to the phone.
  See [the phone loop](docs/AGENT_PHONE_LOOP.md).

The private MCP also includes `quiet_get_sound_map`, which uses positioned observations
uploaded by the connected Quiet Compass app. Unmeasured floor cells remain unknown.
Local exports stay local. Agent mode shares private acoustic/spatial summaries after approval. Connecting Dot remains a separate deployment step.

## Quick start

**Server**

```bash
cd server
python -m venv .venv && source .venv/bin/activate
pip install -e '.[dev]'
cp .env.example .env            # set QC_API_TOKEN
uvicorn quiet_compass.app:create_app --factory --env-file .env --reload
pytest -q
```

**iOS app** (Xcode 26; an ARKit-capable iPhone with iOS 26 for live capture)

```bash
brew install xcodegen
cd ios
cp Config.example.xcconfig Config.xcconfig   # signing team for a physical phone
xcodegen generate && open QuietCompass.xcodeproj
```

Enter the server URL and token inside the app. The token is stored in Keychain.
The app defaults to mono sound features plus ARKit (mode C). It queues uploads
offline and polls for guidance. The Simulator uses explicitly simulated audio and
a scripted walk; live sensors need a device.

**Wearables.** The phone previews Apple Health daily summaries before sharing.
Oura connects directly to the Python server, which encrypts credentials, refreshes
access and syncs every 15 minutes. The agent reads `quiet_get_personal_context`.
Setup and remaining validation: [wearable integration](docs/WEARABLES_AND_PHONE.md).

**Agent.** Deploy the server (see `server/README.md`), add `https://<your-app>/mcp` as a custom connector in the Claude app, and paste `server/agent_instructions.md` into the project instructions.

**Hosting.** The [Render Blueprint](render.yaml) prepares the Python API/MCP with
a persistent SQLite disk for a single-user. The web map stays on Sites and
audio processing stays on the iPhone. Importing the Blueprint provisions paid
resources; this repository configuration is not evidence of a live deployment.
See [the deployment guide](server/README.md) and
[capture, personal learning and hosting boundaries](docs/AGENT_LEARNING_AND_HOSTING.md).

## Team workflow

- Work on short-lived branches and open PRs into `main`. CI runs server and web tests, QuietCore integration tests and the walk-map math checks.
- Contracts change only by agreement across tracks. Update the schema and both model files in the same PR.
- See [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for the hour-by-hour plan, the cut line and the walkthrough script.

## Principles

Measure, remember, recommend and verify; predict only when there is enough evidence. Levels are relative and always shown with their age. An unmeasured place is never called quiet.
