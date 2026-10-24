# Real data only — verification

Verified on October 24, 2026 (America/Los_Angeles).

- Integrated `origin/main` through `6bda8e0` in `codex/real-data-only`; preserved the existing local MCP contribution-window changes. The pre-pull two-file stash remains as a recovery copy.
- Removed generated city scores, spatial interpolation, fake observation submissions, timed contributions, venue noise biases, invented floor plans, scripted event conversations and example Oura metrics.
- Preserved main’s violet report-density fields, base map, controls and tabbed MCP setup. Only real 311 complaints and police noise-nuisance call counts feed the fields; no invented scores or samples. Dark points are dated measurements; unknown areas and unmeasured venues stay gray. Report density is not a sound level.
- Refresh reads DataSF directly. Device data uses the existing public read API through the Site; authentication failures yield an explicit unavailable/access-required state without borrowing owner credentials.
- Device records require `source=device`, `has_synthetic=false`, valid coordinates, a real value, capture profile and a timestamp within 24 hours. Mixed/synthetic records are excluded. Profiles are not merged.

## Observed source results

Direct source verification and browser checks returned:

| Source | Records | Limits |
| --- | ---: | --- |
| SFO daily monitors | 6 | Latest observed date: 2026-08-31; daily CNEL, not live |
| SFO exceedance summaries | 4 | Last year; maxima above station thresholds, not typical level |
| NoiseCapture | 20 | Archived uncalibrated phone cells, 2017–2025 |
| Parks, POPOS and libraries | 350 | Unmeasured candidate locations |
| 311 | 100 | Latest published complaints, not measurements |
| Police noise nuisance calls | 740 | Masked intersections; last 30 days |
| Permits, street work and closures | 4791 | Context only; includes main’s new street-work source |
| Shared device API | 0 | Direct request returned an empty published aggregate list; local Worker preview reported unavailable and correctly displayed no readings |

## Checks

- `node --test tests/*.test.mjs`: 25 passed, including provenance filtering, stale/malformed/empty input, authorization failures, true zero values and source-layer failure isolation.
- TypeScript check: passed.
- Sites production build: passed.
- Browser: main’s violet fields, real source counts, neutral unknown places, density legend and restored tabbed MCP setup verified.
- Screenshot: `real-data-main-style.png`.

No private Oura account data was fabricated or connected as part of this change. Oura still requires its existing authorization flow; absent metrics are gray dashes.

## Main integration

- Merged `origin/main` at `6bda8e0`, including the street-work source and current shared-access changes.
- Kept real-data validation, explicit unavailable states and direct browser fetching of public datasets.
- The local preview cannot reach shared device/MCP services; it displays unavailable without fabricated contributions. Public DataSF layers loaded successfully.
