# Quiet Compass

A personal agent that remembers how the places you walked through sounded, learns which ones are comfortable for you, and helps you get back to one when you need less noise, without losing track of what you came to do.

It was built for an SF hackathon on personal agents for everyday life. The first use case is noise-sensitive people (for example, autistic attendees) at a busy event.

## How it works

1. **The iPhone app measures.** It turns microphone audio into relative loudness features on the phone, tagged with where you are. ARKit records the path you walked.
2. **The memory service remembers.** It stores those features (never audio) and ranks places for a goal (talk, rest or work) and a time budget.
3. **The agent decides.** The Claude app, connected through a custom MCP connector, reads your calendar and the sound memory, suggests a place, and asks the phone to guide you back along the path you walked.

```
apps/quiet-compass/  Next.js web app: SF noise map (live 311 reports plus labelled DataSF layers; violet demo scores are synthetic) and Oura integration
ios/                 SwiftUI app (QuietCompass) + QuietCore Swift package (DSP, route logic, contracts)
server/              FastAPI ingest API + MCP server (FastMCP) + scoring + optional SF 311 city layer
contracts/           JSON Schema shared by phone and server, plus the HTTP API and MCP tool reference
docs/                Implementation plan and product brief
```

## Quick start

**Server**

```bash
cd server
python -m venv .venv && source .venv/bin/activate
pip install -e '.[dev]'
cp .env.example .env            # set QC_API_TOKEN
uvicorn quiet_compass.app:create_app --factory --reload
pytest -q
```

**iOS app** (needs Xcode 26 and an iPhone 16 Pro for spatial audio)

```bash
brew install xcodegen
cd ios
cp Config.example.xcconfig Config.xcconfig   # server URL and token
xcodegen generate && open QuietCompass.xcodeproj
```

The Simulator runs the app with mock audio and a scripted walk. Real capture and AR tracking need a device.

**Agent.** Deploy the server (see `server/README.md`), add `https://<your-app>/mcp` as a custom connector in the Claude app, and paste `server/agent_instructions.md` into the project instructions.

## Team workflow

- Work on short-lived branches and open PRs into `main`. CI runs the server lint and tests and the QuietCore tests.
- Contracts change only by agreement across tracks. Update the schema and both model files in the same PR.
- See [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for the hour-by-hour plan, the cut line and the demo script.

## Principles

Measure, remember, recommend and verify; predict only when there is enough evidence. Levels are relative and always shown with their age. An unmeasured place is never called quiet.
