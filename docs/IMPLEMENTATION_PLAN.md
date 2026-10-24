# Quiet Compass: technical implementation plan

The repo has three parts. A native SwiftUI app turns microphone audio into per-place sound features on the phone. A small Python service stores those features. A remote MCP server lets the personal agent query them alongside the user's calendar. Everything below the capture layer works the same whichever sensors pass the hour-0 tests, so the product still works without spatial audio.

The product brief (in Spanish) is in [`product-spec-es.md`](product-spec-es.md). The shared data formats are in [`../contracts`](../contracts).

## Architecture

```
iPhone app (Swift)                 Memory service (Python)            Agent
┌─────────────────────┐            ┌──────────────────────┐          ┌──────────────────┐
│ Capture             │            │ MCP server  /mcp     │◄────────►│ Claude app       │
│ FOA or mono + ARKit │            │ (tools, JSON)        │ tool     │ (custom          │
├─────────────────────┤            ├──────────────────────┤ calls    │  connector)      │
│ On-device features  │            │ Memory + scoring     │          └────────▲─────────┘
│ level, spread, ...  │            │ (SQLite, filter +    │                   │
├─────────────────────┤ 5 s aggr.  │  score)              │          ┌────────┴─────────┐
│ Local store + UI    │──────────► ├──────────────────────┤          │ Calendar         │
│ SQLite, minimap,    │ ◄──────────│ Ingest API  /v1      │          │ connector        │
│ route back          │ guidance   │ (bearer token)       │          └──────────────────┘
└─────────────────────┘ poll       └──────────────────────┘
```

Only feature summaries leave the phone; no audio, transcripts or images are stored anywhere. The agent never touches the sensors. Its one write is asking the phone to show a route back to a place.

## Hour-0 feasibility spike

Run these four tests in the app's Diagnostics screen and record the results before building on them.

1. **FOA alone.** `AVCaptureSession` with the built-in mic, `multichannelAudioMode = .firstOrderAmbisonics` and one `AVCaptureAudioDataOutput` using `kAudioChannelLayoutTag_HOA_ACN_SN3D | 4`. Pass: 4-channel buffers arrive at 48 kHz.
2. **FOA + ARKit.** Start an `ARSession` with `providesAudioData = false`, then the FOA session. Pass: both stay healthy, tracking stays `.normal`, and there is no `Required sensor failed` error.
3. **Gain control.** Use `.record` + `.measurement`. Play a steady tone from a speaker and have someone talk loudly near the phone. Pass: the tone's band level does not dip. Run it in both FOA mode and default mode.
4. **Connector auth (server track).** Check whether the Claude app's custom connector settings can send a fixed `Authorization` header. If not, set `QC_MCP_PATH_SECRET` (demo only).

| Mode | When to pick it | Position source | Direction of arrival |
| --- | --- | --- | --- |
| A: Spatial + AR | Steps 1 and 2 pass | ARKit world tracking | Yes, rotated into the room frame |
| B: Spatial + zones | Step 1 passes, step 2 fails | User-labelled zones | Yes, relative to the phone |
| C: AR + levels | Step 1 fails | ARKit world tracking | No |

## Audio features (per second, aggregated to 5 s)

| Feature | Computation | Label |
| --- | --- | --- |
| Level | 10·log10(mean(w²)+1e-12), 125 ms frames power-averaged to 1 s | `level_dbfs_rel` (relative dBFS, never dBA) |
| Weighted level | Same, after an A-weighting biquad cascade | `level_aw_dbfs_rel` |
| Variability | L10 − L90 of 125 ms frames, rolling 30 s | `spread_db` |
| Peaks | Onsets above rolling median + 10 dB, per minute, rolling 60 s | `peaks_per_min` |
| Spectrum | Octave bands 250 Hz–8 kHz (lower bands are unreliable on phone mics) | `bands_db[6]` |
| Speech share | Mean `speech` confidence from the built-in sound classifier | `speech_share` |
| Sound classes | `SNClassifySoundRequest(.version1)`, top 3 | `classes` |

A spot counts as measured after 30 s; readings under 15 s are marked low confidence. Comparisons are only made within one device profile.

**Direction of arrival (experimental).** The estimator computes the pseudo-intensity vector I = Re{W*·[X, Y, Z]} and the diffuseness ψ = 1 − ‖⟨I⟩‖/⟨½(|W|²+|X|²+|Y|²+|Z|²)⟩. It uses only 500 Hz–4 kHz, and only onset bins that pass a direct-path test. It abstains when confidence is low or bands disagree, and otherwise reports 8 coarse sectors. Calibrate the axes with a speaker 2 m away (front, right, up). In a busy hall, "no clear direction" is the expected answer.

## Tracking and route memory

- ARKit world tracking with `worldAlignment = .gravity` (indoor compasses are unreliable), a 30 fps format, and no plane detection, light estimation or scene reconstruction.
- The phone is held camera-forward with the screen kept awake. Nothing is tracked from a pocket.
- A breadcrumb is dropped every 1 m. The route back is the recorded path reversed and simplified to turn keypoints (Ramer–Douglas–Peucker), as the Clew navigation app does. The phone computes the route; the server stores only the target place.
- After 30 s of lost tracking, the app closes the path segment and asks for a zone label.

## Recommendation logic

`quiet_find_space` filters out places that lack a required tag, have no observation, or cannot fit before `return_by`. The time check is 2 × distance ÷ 0.8 m/s plus the requested stay. It then scores each remaining place:

```
S = w·F_measured + (1 − w)·F_prior − λ·d,   w = exp(−age_min / 15),   λ = 0.1 per 10 m
```

`F_measured` is the minimum of three 0–1 fits (level, spread and peaks) against the user's band for that goal. A high speech share lowers it for work and rest, and a recent "chaotic" rating caps it. When the best S is below 0.4, the tool returns `{no_fit, closest, relax}` instead of picking a place anyway.

## Build plan (10 hours, three tracks)

| Track | Owns |
| --- | --- |
| Audio | Spike steps 1 and 3, features, sound classes, direction of arrival (stretch) |
| AR and UI | Spike step 2, crumbs, places, route back, minimap, arrival check, feedback, outbox, guidance polling |
| Server and agent | Spike step 4, ingest, scoring, MCP tools, deployment, connector, agent instructions, demo script |
| Fourth person (optional) | Fixtures and traces, tests, MCP Inspector checks, slides, city layer |

1. **0:00–0:30:** contracts frozen (already in `contracts/`).
2. **0:30–1:00:** spike tests. Gate: capture mode and connector auth chosen.
3. **1:00–3:00:** capture, features and the outbox on device (mocks in the Simulator). Server ingest is deployed with a seeded session. Gate: walking three spots produces rows on the server.
4. **3:00–5:00:** minimap, route back, arrival check and feedback. Scoring, `quiet_find_space` and `quiet_get_context`. Gate: route back works and the seeded spots rank sensibly.
5. **5:00–6:00:** the remaining tools, the connector and the agent instructions. Gate: the demo request works end to end.
6. **6:00–8:00:** bench tests and tuning. Gate: hide the direction arrow if it is unstable.
7. **8:00–10:00:** freeze features, rehearse the demo twice on real measurements, and write the limits slide.

**Cut line.** The minimum demo is mono levels → three marked places → reverse-path minimap → `quiet_get_context`, `quiet_find_space`, `quiet_start_guidance` → the agent end to end. If you fall behind, drop features in this order: city layer, saved world maps, AR arrows, direction arrow, learned personal bands, then sound classes.

## Demo (3 minutes)

1. Start a session and explain what is measured: loudness features only, never audio.
2. Walk three spots with different sound and mark them.
3. Ask the agent: "I need ten minutes of quiet and to be back before the demos."
4. The agent checks the calendar (or uses the time the user gives), calls the tools and explains its choice: measurement, age and route.
5. The phone shows the route back. Arrive, run the 30 s check, and give feedback.
6. Change the noise at that spot and show that the new measurement changes the recommendation.

If the calendar, a schedule file or a noise source was prepared for the demo, say so on stage.

## Risks and fallbacks

| Risk | Early signal | Fallback |
| --- | --- | --- |
| FOA and ARKit can't run together | Spike step 2 fails | Mode B or mode C |
| Automatic gain distorts levels | The tone dips while someone talks | `.measurement` mode; compare within one profile |
| FOA axes differ from assumptions | Arrow off by 90° or mirrored | Fit the 3×3 calibration |
| Tracking lost in a crowd | Limited for more than 30 s | Null positions, new segment, zone label |
| Connector rejects a fixed header | Spike step 4 fails | `QC_MCP_PATH_SECRET` for the demo |
| Connector lists tools but never calls them | No requests reach the server | An MCP-capable CLI client or a small Messages API client |
| Battery and heat | More than 15% drain per 30 min | 1 Hz poses, no mesh, sessions only on demand |
