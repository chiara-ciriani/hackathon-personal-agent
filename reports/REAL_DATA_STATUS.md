# Real data only — verification

Verified on October 24, 2026 (America/Los_Angeles).

- Integrated `origin/main` through `f996784` in `codex/real-data-only`; preserved the existing local MCP contribution-window changes. The pre-pull two-file stash remains as a recovery copy.
- Removed generated city scores, spatial interpolation, fake observation submissions, timed contributions, venue noise biases, invented floor plans, scripted event conversations and example Oura metrics.
- Purple means a dated measurement exists at that point. Gray means no sound measurement. Reports, permits and candidate places remain gray context; no quiet/loud classification is inferred from them.
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
| Permits and closures | 784 | Context only |
| Shared device API | 0 | Direct request returned an empty published aggregate list; local Worker preview reported unavailable and correctly displayed no readings |

## Checks

- `node --test tests/*.test.mjs`: 24 passed, including provenance filtering, stale/malformed/empty input, authorization failures, true zero values and source-layer failure isolation.
- TypeScript check: passed.
- Sites production build: passed.
- Browser: real counts, grayscale unknown places, dated measurement legend and Fort Mason no-measurement details verified.
- Screenshot: `real-data-map.png`.

No private Oura account data was fabricated or connected as part of this change. Oura still requires its existing authorization flow; absent metrics are gray dashes.

## Publication

- Site publication succeeded: https://quiet-compass-oura-martin.martin-puli.chatgpt.site
- Published source commit: `b3ce2251b3229283acab1e700bb5f2cc46001c02` (Sites source repository).
- Existing private access preserved.
