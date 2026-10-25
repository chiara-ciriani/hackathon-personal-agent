# Demo runbook

Build ends 18:30 PT. Demo is about 3 minutes. Everything below runs from `main`.

## The story in one line

At an event, an autistic person can be overloaded by sound before they can explain it. Quiet Compass maps the room's noise as you walk, and when it gets loud, the edge of the screen lights up toward the quietest spot you measured. No reading, no choosing, no chat in the hard moment.

## Checklist before demoing

Do these at 18:00, then **stop pushing to `main` around 18:15**: every push redeploys Render, which wipes its data.

| Check | How | Expected |
| --- | --- | --- |
| Render server is on latest `main` | `curl https://quiet-compass-server.onrender.com/v1/exchange/status` | JSON with `"native_protocol": "phone-walk-v1"` (a 404 means an old deploy) |
| Render is awake | `curl https://quiet-compass-server.onrender.com/healthz` | `{"ok":true}` (the first request after idle is slow) |
| Phone relay is up | open `https://quiet-compass-navy.vercel.app/measure` | page loads |
| QC Walk Map is rebuilt from latest `main` | `git pull && cd ios-walk && ./setup.sh`, then Run on the iPhone 17 Pro | Quiet Map screen; the edge glow is in this build |
| Agent is connected | custom connector `https://quiet-compass-server.onrender.com/mcp/shared` with `QC_SHARED_API_TOKEN` (ask Chiara); paste `server/agent_instructions.md` as instructions | the agent lists `connect_phone` |
| Phone setup | brightness up, Do Not Disturb on, auto-lock off (the app already keeps the screen on) | |

## Script

| Time | Who | What happens |
| --- | --- | --- |
| 0:00 | Speaker | The problem: loud events overload autistic and noise-sensitive people, and in that moment asking for help or reading a map is hard. |
| 0:30 | Walker | Open QC Walk Map and walk slowly around the room, phone up, camera forward. The map fills in: green is quiet, orange is loud, grey is not walked yet. |
| 1:00 | Helper | Make one corner loud (clap, music). The walker stands there: it turns orange. |
| 1:15 | Walker | The screen edge lights up on the side to turn to. Turn until the whole border breathes and the phone taps once, then walk there. The card says "You're at the quietest spot you've measured". |
| 1:45 | Speaker | The agent: it uses the sounds this person said bother them and the places they rated in this session. Ask it once ("I need somewhere quiet"). It links the phone, asks for a 60 s walk, and sends one calm instruction; the same edge glow points to its pick. |
| 2:30 | Speaker | Real data: `data/captures/2026-10-24-iphone17pro-walk/` is our first walk today on an iPhone 17 Pro. What's next: the alert plus one gesture (the iPhone's Action Button) starts the guidance with no chat at all. |

## If something fails

| Failure | Fallback |
| --- | --- |
| ARKit tracking is poor (dark room, blank wall) | Move slowly, point at furniture. If it stays bad, show `data/captures/2026-10-24-iphone17pro-walk/timeline.gif` |
| Render is down or on an old deploy | Skip the agent part; the local map and edge glow need no server |
| The agent does not reply in time | Show the local edge glow only and describe the agent step in words |
| Nothing turns orange | The glow only shows when the spot you stand on is in the loudest third of what you walked; make the loud corner louder, or stand closer |

## What not to say

- Levels are relative dBFS from one phone, never dB or dBA.
- It does not detect crises or diagnose anything. It helps find a calmer spot with less effort.
- Positions are metres inside the room from the phone's AR session, not GPS.
