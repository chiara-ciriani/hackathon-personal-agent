# Background capture and noise alerts

**Status:** plan, not implemented. Waiting on pending iOS app changes before any code lands.
**Owner:** Ana Undurraga. Check with her before starting any of this, so two people don't build it twice.
**Date:** 2026-10-24

## Goal

Keep measuring sound levels while Quiet Compass is open **or in the background**, and alert the person when it has been too loud for too long.

## How it fits the existing plan

- The capture code already exists: `MonoFeatureSource` (AVAudioEngine, 48 kHz mono) and `FOAFeatureSource` (spatial), both feeding `LevelFeatureExtractor` and `ObservationAggregator` in `QuietCore`.
- `docs/IMPLEMENTATION_PLAN.md` says the phone is held camera-forward and "nothing is tracked from a pocket". That stays true for the AR route. Background capture is a **separate levels-only mode**: no ARKit, no route, no direction of arrival. It adds to the AR session; it doesn't change it.
- `docs/product-spec-es.md` §12 asks for an explicit session, a visible mic indicator, a pause control and no constant alerts. Everything below follows that.
- `docs/AGENT_LEARNING_AND_HOSTING.md` describes a proactive-help executor (rate limits, notification delivery, pause) that isn't built yet. These local alerts are the on-device half of it and need no server.

## Capture

**Foreground.** Already works through `CaptureFactory`.

**Background.**

1. Add `UIBackgroundModes: [audio]` to the Info.plist properties in `ios/project.yml`. Check that `NSMicrophoneUsageDescription` explains background measurement.
2. The session must **start in the foreground** (an explicit "Start session" tap). iOS keeps an active recording session running after the app is backgrounded or the phone is locked, but won't let an app start the mic from the background.
3. In the background, use `MonoFeatureSource` only. ARKit doesn't run in the background. Whether the spatial `AVCaptureSession` survives backgrounding is **unverified**; test it on a device before relying on it.
4. Handle `AVAudioSession.interruptionNotification` (calls, Siri, other apps taking the mic) and restart capture when the interruption ends. Handle `routeChangeNotification` too, since a plugged-in USB mic changes the route.
5. To save battery, turn off `SoundClassifier` in the background and end sessions automatically after a set time (proposed: 60 min, configurable).
6. iOS shows the mic indicator the whole time. That's intended.

**Limits that can't be worked around:** a force-quit app stops capturing, and there's no capture without the indicator.

## Deciding "too noisy"

Levels are relative, uncalibrated dBFS (`level_dbfs_rel`, never dBA). A fixed dB threshold doesn't make sense, so the threshold is relative to the person.

- **Baseline:** at session start the person marks "this is comfortable" (one 5 s observation), or picks a sensitivity on a slider. `threshold = baseline + offset`. Proposed default offset: +10 dB on `level_aw_dbfs_rel`.
- **Trigger:** the 5 s level stays above the threshold for **30 s** (6 consecutive observations), **or** `peaks_per_min` goes above a limit (abrupt sounds matter, not just loudness).
- **Hysteresis:** re-arm only after the level falls below `threshold − 5 dB`.
- **Cooldown:** at most one alert every **10 min**. Pause and "snooze 30 min" controls.
- Thresholds are compared within one device profile only (same phone, same capture mode), as the contracts require.

All numbers are starting points to tune on a device.

## Alerting

| App state | Alert |
| --- | --- |
| Foreground | In-app banner plus haptic |
| Background or locked | Local notification (`UNUserNotificationCenter`), allowed because the app is still running. Ask for permission at session start, not at launch. |
| Optional | A Live Activity (ActivityKit) on the lock screen and Dynamic Island showing the current level and session time left |

The alert should point somewhere: "It's been loud for a while. The courtyard was quieter 6 min ago." Get the suggestion from the server (`find_suitable_places` / `quiet_find_space`) when online, and fall back to a plain alert offline.

## Code changes (when the app is ready)

- `ios/project.yml`: background mode, usage strings.
- `AudioSessionConfigurator`: interruption and route-change handling.
- New `NoiseAlertMonitor`: consumes the 5 s observations and applies baseline, trigger, hysteresis and cooldown. Keep the decision logic in `QuietCore` (Foundation only) so it gets unit tests next to `AudioAggregatorTests`.
- New thin notifier in the app target: `UNUserNotificationCenter`, plus ActivityKit if we do the Live Activity.
- Settings: sensitivity, session length, alerts on/off.

## Open questions

- Does the FOA `AVCaptureSession` keep running in the background? Test on an iPhone 16 Pro.
- Battery cost per hour of mono capture with the classifier off. Measure it.
- Alerts only for the person, or can the agent also use them (e.g. a server event when a session crosses the threshold)? Ties into the unbuilt proactive executor.
- Hardware calibration (external USB-C measurement mic or per-model offset) would allow absolute thresholds later. Out of scope here.

App Store review scrutinizes background recording. For the hackathon the app is installed from Xcode, so review doesn't apply.
