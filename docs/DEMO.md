# Demo runbook

Build ends 18:30 PT. The pitch with the live demo is about 2:40. Everything below runs from `main`.

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

## Pitch (about 2:40)

Roles: the speaker never touches the phone. The walker holds the phone, mirrored to the projector (iPhone on USB-C → QuickTime → New Movie Recording → pick the iPhone). Two teammates stand at one side, 5 m or more from the quiet side, chatting quietly.

| Time | On stage | Speaker |
| --- | --- | --- |
| 0:00 | Walker stands still on the quiet side | *There are about five and a half million autistic adults in the US. Four in ten of them live with decreased sound tolerance: everyday sounds most people don't even notice become hard to bear.* [pause] *79% of autistic people say they feel socially isolated. And half of autistic people and their families say they sometimes just don't go out. Events like this one are full of noise nobody planned.* |
| 0:35 | Speaker turns to the audience | *So: where's the quietest spot in this room right now?* [pause] *Nobody knows. Let's find out.* |
| 0:45 | Walker walks slowly on the quiet side; the map fills green | *This is Quiet Compass. As he walks, the phone maps the sound of the room. The microphones measure the level, the camera and motion sensors know where he is. Green is calm; grey is where we haven't been yet.* |
| 1:10 | The two teammates get loud (laughing, talking, a clap); the walker moves toward them; the map turns orange | *Now he walks into a busy corner...* |
| 1:25 | Walker stops in the group; the screen edge lights up on one side | *Look at the edge of the screen. No text, no map to read. It just glows on the side to turn.* |
| 1:40 | Walker turns until the whole border breathes and the phone taps; walks away following the glow; the card reads "You're at the quietest spot you've measured" | *When he faces the right way, the whole border breathes and the phone taps once. He's walking to the quietest spot we actually measured, here, a minute ago.* |
| 2:00 | | *The map is the senses. The agent is the part that knows you. It learns from what you tell it: which sounds bother you, chatter or sudden claps, and which places helped. It decides when to step in and sends one calm instruction; the phone does the pointing. It's built on MCP, so any personal agent can plug in.* |
| 2:25 | | *Everything you saw is real: our first walk this afternoon, on an iPhone 17 Pro, is in our repo. For the demo we hold the phone up so you can see it; day to day, it listens from your pocket and taps you when it's time to move. Quiet Compass: a calmer place, one less decision.* |

Notes:

- The teammates should be loud, not shouting: laughing and talking is enough, and it doesn't hurt anyone noise-sensitive in the audience.
- Do not link the 79% and 50% to noise. In the survey, people stay home because they worry how others will react. The speaker only says events are noisy; the audience makes the connection.
- Say "decreased sound tolerance", not "pain" or "severe hyperacusis". The 5.4 million is a CDC modelled estimate, not a count.
- We found no figure for how many autistic people leave or skip events. Do not invent one.
- Likely questions: *Why not motion sensors alone?* They drift; the camera corrects them. *Is it real dB?* Relative to this phone; we compare readings with each other. *Privacy?* No audio or images leave the phone, just 5-second summaries.

### Sources for the numbers

| Claim | Source |
| --- | --- |
| 1 in 31 eight-year-olds in the US identified with autism (32.2 per 1,000, 16 sites, 2022) | [CDC MMWR, 2025](https://www.cdc.gov/mmwr/volumes/74/ss/ss7402a1.htm) |
| About 5.4 million US adults autistic (2.21%, modelled estimate for 2017) | [CDC, Dietz et al. 2020](https://archive.cdc.gov/www_cdc_gov/autism/publications/adults-living-with-autism-spectrum-disorder.html) |
| Decreased sound tolerance in 41% of autistic people now, 61% at some point (meta-analysis of 67 studies) | [Williams, Suzman & Woynaroski, Ear and Hearing 2021](https://pmc.ncbi.nlm.nih.gov/articles/PMC8349927) |
| 79% of autistic people feel socially isolated; 50% of autistic people and families sometimes don't go out, worried how people will react (7,532 respondents, UK) | [National Autistic Society, Too Much Information, 2016](https://media.autism.org.uk/m/6814f29f7ae09813/original/TMI_Campaign_Report_FINAL_290316-1-1.pdf) |
| 94.4% of an autistic adult sample reported extreme sensory processing (small sample, questionnaire; use only if asked) | [Crane, Goddard & Pring, Autism 2009](https://research.gold.ac.uk/id/eprint/2537) |

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
