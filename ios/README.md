# Quiet Compass iOS app

SwiftUI app for iPhone (iOS 26, Swift 6 strict concurrency). It measures relative loudness on the phone,
records the walked path with ARKit, uploads feature summaries to the private server, and shows the way back
when the agent starts guidance. Audio and camera images are never stored or sent.

## Prerequisites

- Xcode 26 and XcodeGen (`brew install xcodegen`)
- An ARKit-capable iPhone on iOS 26 for real capture (iPhone 16 Pro for spatial audio). The Simulator runs with mocks.
- An Apple developer team with HealthKit enabled (the app reads optional Apple Health summaries).

## Build

```bash
cd ios
cp Config.example.xcconfig Config.xcconfig   # server URL; set DEVELOPMENT_TEAM for device builds
xcodegen generate && open QuietCompass.xcodeproj
```

Signing: select your team on the QuietCompass target (or set `DEVELOPMENT_TEAM` in `Config.xcconfig`).
The server token is entered in the app and kept in the Keychain; it is never in the bundle.

**Device vs Simulator.** On a device the app uses the microphone (`MonoFeatureSource` for mode C,
`FOAFeatureSource` for mode A) and ARKit (`PathTracker`). In the Simulator, `#if targetEnvironment(simulator)`
swaps in `MockFeatureSource` (synthesized quiet / loud-with-speech / medium scenes) and `MockPathTracker`
(a scripted walk around a 10 × 6 m rectangle with 35 s pauses at the corners), and contributions are labelled
`source: "simulated"`.

## Layout and data flow

```
QuietCompass/
  App/       QuietCompassApp + CompassView (entry point), CompassModel (session, capture, outbox, guidance,
             wearables), PathTracker (ARKit), Credentials (Keychain),
             CompanionFeatures + CompassModel+Companion (capture mode, level in words, dwell, minimap data,
             shared contributions, feedback, diagnostics), DeviceProfileBuilder, LevelDescription
  Audio/     capture sources, audio session, classifier, SpikeRunner (hour-0 tests)
  Health/    HealthReader (Apple Health preview)
  Mocks/     MockFeatureSource, MockPathTracker
  Sync/      SharedContribution (opt-in shared-layer summary)
  UI/        MinimapView, ArrivalCheckView + FeedbackSheet, DiagnosticsView, CompanionSections, Theme
Packages/QuietCore   contracts, DSP, aggregation, routes, PhoneServer/PhoneOutbox (no UIKit/AVFoundation)
```

1. A `FeatureSource` yields 1 s `FeatureFrame`s. `CompassModel` feeds them with the latest pose to
   `ObservationAggregator`, which emits a 5 s `Observation`.
2. Poses (2 Hz) go to `BreadcrumbRecorder`; a crumb is dropped every metre.
3. Sessions, observations, crumbs, places, feedback and guidance status are written to `PhoneOutbox`
   (one file per request, written before sending) and flushed to the server in order; nothing is deleted
   until the server accepts it.
4. Every 3 s while recording, `CompassModel` polls `GET /v1/sessions/{id}/guidance`. The route is computed on
   the phone from its own crumbs (`RouteBack`); the minimap draws it. "I've arrived" runs a 30 s check,
   asks for feedback (goal / verdict / feel) and posts status `arrived`.

## Capture modes

| Mode | Audio | Position | Pick when |
| --- | --- | --- | --- |
| A | FOA (4 mics) | ARKit | Diagnostics: both spatial checks pass |
| C | Mono | ARKit | Default; works on most phones |
| B | FOA | Named zones | Not selectable yet (needs zone-based places) |

Choose the mode in the Capture section before starting. Diagnostics runs the three spike tests
(spatial audio alone, spatial audio with tracking, automatic gain check), pings `/healthz` and shows
pending uploads and the session id.

## Shared contribution (opt-in)

Off by default. With **Share anonymous sound summaries** on, each 30 s stay at a marked place produces one
`SharedContribution` (median of that window's observations, `area_id = place:<uuid>`, 5-minute UTC time
bucket, lat/lon null indoors, no audio, route or identity) posted to `POST /v1/contributions`. The returned
status (accepted / withheld / rejected) is shown under the toggle. Contributions bypass the outbox so a
rejected one never blocks measurement uploads; failures are retried up to three times while the app runs.

## Event-morning checklist

- [ ] `Config.xcconfig` points at the deployed server; `xcodegen generate` run after the last pull
- [ ] App installed on the device; microphone, camera and (optional) Health permissions granted
- [ ] Server saved in the app; "Server connected" shown; Diagnostics → Check the server says up
- [ ] Spike tests run once in the venue; capture mode chosen from the results
- [ ] Phone charged; Low Power Mode off; screen auto-lock is not relied on (keep the app open)
- [ ] One test walk: mark a place, stay 30 s, see it measured in "Your spots" and 0 uploads pending
- [ ] Ask the agent for guidance once and follow it to "I've arrived"
- [ ] Decide whether sharing is on, and say so when presenting
