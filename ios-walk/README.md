# Quiet Compass (iOS)

An experimental "acoustic compass". It captures the iPhone's spatial audio as First Order Ambisonics (FOA: W, X, Y, Z), estimates where the dominant sound comes from, and draws an arrow that stays pointed at the source while the phone turns. When the sound field is too diffuse it shows a question mark instead of an arrow.

The default **Quiet Map** screen starts mapping after permission prompts, shows the map and a direction to the quietest measured spot, and has one **Stop and save** button. **Advanced** contains the four detailed modes:

- **Compass**: the original arrow, calibration toggles and CSV log.
- **Radar**: stand in one spot and turn slowly. Each 15° world-direction wedge collects how much confident sound arrived from that direction over the last ~20 s.
- **Locate**: capture the dominant bearing from 2–3 spots. The app intersects the rays and places the source on a top-down plot in metres.
- **Walk map**: press Record and walk with the phone held camera-forward. ARKit gives the position and the mic gives the level. A live top-down map shows quiet and loud areas, with the 3 quietest measured spots marked. Walks are saved as JSON, can be replayed at 10×, and can be shared.

**Integration check (24 Oct, `main`):** unsigned iPhone build passes with Xcode 26.6; the pure-math self-check passes. This is software verification only; no physical microphone/ARKit run or Dot connection is claimed. The original `ios/` app and the browser agent mode at `/measure` remain available.

**Status (Radar, Locate and Walk map, added 24 Oct):** never run on a phone either. Every app file type-checks with the local Swift 6.1 compiler against the Mac Catalyst SDK (iOS 18 level), in both Swift 6 and Swift 5 language modes. The ARKit code is checked too, because ARKit and its Swift overlay are in that SDK. The pure maths (`SoundField.swift`, `SourceMap.swift`) passes 26 checks in `SelfCheck/main.swift`. The Walk-map blend matches the team server's `sound_field.py` to 6 decimals on a probe case. Unverified on hardware: whether the audio capture keeps running while ARKit has the camera, ARKit's camera-axis mapping (see the debug row "ARKit − CoreMotion heading"), and all real-world accuracy.

**Status (Compass):** written without Xcode, so it has never run on a phone. The Swift source type-checks in Swift 6 language mode against the Mac Catalyst SDK. One iOS 26 property is shimmed for that check. The DOA maths passes synthetic tests: a plane wave comes back at the right azimuth with confidence 1.00, diffuse noise gives 0.03, and two opposite sources give 0.05. The hardware side is unverified: FOA in an audio-only session, the channel order, and the FOA-to-device axes. The app's debug panel shows these on screen, so the first minute on the phone tells you whether the idea works.

## Files

| File | What it does |
|---|---|
| `QuietCompassApp.swift` | App entry point |
| `ContentView.swift` | Arrow dial, readout, level meter, threshold slider, calibration toggles, log/CSV share, debug panel |
| `CompassModel.swift` | Main-actor UI model, plus the analysis pipeline that runs on the audio queue (levels, DOA, publishing at about 15 Hz) |
| `AudioCapture.swift` | Audio-only `AVCaptureSession` that requests FOA. Converts buffers to per-channel Float (interleaved or not; Float32, Int16 or Int32) and describes the format and layout tag |
| `DOA.swift` | Pseudo-intensity DOA: vDSP FFT, 200–4000 Hz band, confidence, smoothing over about 0.5 s, channel-order and axis assumptions |
| `Motion.swift` | CoreMotion attitude (magnetic north if available) and rotation from device frame to world frame. While ARKit runs, its camera orientation replaces CoreMotion's |
| `ModeViews.swift` | Radar dial, Locate screen and plot, Walk-map screen and field map |
| `ARTracker.swift` | Optional ARKit world tracking (`.gravityAndHeading`), with no rendering. It runs only while Locate mode is on or a walk is recording. It publishes the camera x/z about every 0.5 s while tracking is normal, plus the orientation used for the DOA |
| `SourceMap.swift` | Pure maths: radar sectors with forgetting, least-squares ray intersection with uncertainty, ARKit-to-world axis mapping |
| `SoundField.swift` | Pure maths: Swift port of `sound_field.py` (Walk map), plus the walk JSON format |
| `SelfCheck/main.swift` | Self-check for the two pure files. **Not part of the app target**: it has top-level code. `project.yml` excludes `SelfCheck/**` |

No assets, no packages.

Run the self-check on any Mac with Swift 6.1 or later, from this folder:
```sh
swiftc -O SoundField.swift SourceMap.swift SelfCheck/main.swift -o /tmp/qc-selfcheck && /tmp/qc-selfcheck
```
It checks: (a) a synthetic source at 45° fills the 45° sector, with a refined bearing of 45.3°, and the radar forgets old data and resets; (b) rays from (0,0) at 45° and from (4,0) at 135° (maths angles) meet at (2,2), a third ray 5° off still lands within 0.6 m, and a ray pointing away is dropped; (c) parallel, anti-parallel and 10°-apart rays are refused, while rays 20° apart are accepted; the ARKit axis mapping; the Walk map (quiet spot at the quiet end, unwalked corner grey, newer readings outweigh old ones); and the JSON keys.

## Build on your Mac (about 5 minutes)

1. In Xcode 26, choose File > New > Project > iOS > App. Set Product Name `QuietCompass`, Interface SwiftUI, Language Swift, and leave Testing and Storage at None.
2. Delete the template's `ContentView.swift` and `QuietCompassApp.swift` (Move to Trash).
(Or use `project.yml` / `setup.sh`, see `START_HERE.md`.)

3. Drag all the `.swift` files from this folder (not the `SelfCheck` folder) into the `QuietCompass` group. Tick "Copy items if needed" and the QuietCompass target.
4. Select the target and open the **Info** tab. Under Custom iOS Target Properties, add:
   - `Privacy - Microphone Usage Description` (`NSMicrophoneUsageDescription`): *Quiet Compass listens to estimate where sound comes from. Audio is not recorded or sent anywhere.*
   - `Privacy - Motion Usage Description` (`NSMotionUsageDescription`): *Quiet Compass uses motion to keep the arrow pointing at the sound source as you turn.*
   - `Privacy - Camera Usage Description` (`NSCameraUsageDescription`): *ARKit uses the camera to track where you stand, so readings can be placed on a map.* **Without this key, the app crashes when Locate mode or Record starts ARKit.**

   In raw plist form:
   ```xml
   <key>NSMicrophoneUsageDescription</key>
   <string>Quiet Compass listens to estimate where sound comes from. Audio is not recorded or sent anywhere.</string>
   <key>NSMotionUsageDescription</key>
   <string>Quiet Compass uses motion to keep the arrow pointing at the sound source as you turn.</string>
   <key>NSCameraUsageDescription</key>
   <string>ARKit uses the camera to track where you stand, so readings can be placed on a map.</string>
   ```
5. In the **General** tab, set Minimum Deployments to iOS 26.0. Spatial audio capture needs an iPhone 16 Pro or later; the target is an iPhone 17 Pro.
6. In **Signing & Capabilities**, choose your Team. If the bundle id clashes, change it.
7. Plug in the iPhone. If Developer Mode is off, turn it on under Settings > Privacy & Security, then Run. Allow the microphone and motion prompts.

The code needs Swift 6.1 or later because it uses `nonisolated` on type declarations; Xcode 26 ships Swift 6.2. The non-UI types are marked `nonisolated` and the model `@MainActor`. That should let the code build with Xcode 26's "Default Actor Isolation" set to either MainActor or nonisolated. Only the nonisolated case was checked here, because the local compiler is Swift 6.1. If the build fails on isolation, set Build Settings > Default Actor Isolation to `nonisolated`.

## First minute: read the debug panel ("What the phone actually delivers")

| Row | Hoped for | If not |
|---|---|---|
| FOA supported | `yes` | `NO` means FOA is not offered in an audio-only session. See *If FOA is not supported* below. |
| Channels | `4` | `1` or `2`: no DOA is possible, and the app says so. |
| Layout tag | `0x00BE0004 HOA_ACN_SN3D\|4 (AmbiX W,Y,Z,X)` | Write down whatever it shows. With `B_Format`, "Auto" switches to W,X,Y,Z. |
| Format | e.g. `LPCM Float32 non-interleaved 4ch` | Anything that isn't LPCM Float32, Int16 or Int32 is dropped. The string tells you what arrived. |
| Per-channel dB | ch0 (W) loudest | If ch0 isn't the loudest, the order is probably not W-first. Try the Channel order picker. |
| Gravity check | about `+1.00` | About `-1` or near 0 while the phone is tilted means the rotation-matrix convention is flipped. Fix it in `Attitude.toWorld`. |
| Phone bearing | matches the Compass app (±10°) | Wave the phone in a figure 8 to calibrate the magnetometer. |

## One-minute calibration test

Set up a Bluetooth or wired speaker playing pink or white noise at a fixed spot about 1.5–2 m away, at roughly phone height, in a quiet room.

1. **Find "front" (20 s).** Hold the phone still and upright in portrait, with the rear camera facing the speaker. Read **FOA azimuth** in the debug panel. Then turn so the speaker is on your left (expect about +90°) and behind you (expect about 180°).
   - Front reads about 0° and left about +90°: the "Rear camera" preset is right.
   - Front reads ±90° instead: try the **Top edge** preset, or **Swap X and Y**.
   - Left reads −90°: turn on **Negate Y**. Front reads 180°: turn on **Negate X**.
2. **Rotation test (30 s).** Start **Auto 5 Hz** logging. Turn slowly through 360° on the spot, holding the phone the same way throughout. The on-screen arrow should keep pointing at the speaker, and `azimuth_world_deg` in the CSV should stay roughly constant. Stop logging and share the CSV.
3. **Should fail gracefully (30 s).** Add a second speaker on the opposite side playing different noise, or walk into a reverberant corridor. Confidence should drop and the app should abstain (question mark) once confidence falls below the slider value. If the arrow still points confidently at nothing, the confidence measure isn't working on real hardware.

Suggested go/no-go for 15:00, using the rotation-test CSV: at least 80% of non-abstained rows within ±30° of the median `azimuth_world_deg`, the app abstaining in the two-speaker or corridor case, and less than about 1 s for the arrow to settle after the speaker moves.

## Walk map: 2-minute test (top priority)

Play noise from a speaker at one end of a room or corridor at least 8 m long. Leave the far end quiet.

1. Open **Walk map** and press **Record**. Allow the camera prompt. Within a few seconds the line under the button should read **ARKit: tracking normal** in green. If it stays orange ("tracking limited"), point the camera at a textured scene and move slowly. Samples are skipped while tracking is limited.
2. Walk slowly (about 0.5 m/s) from the speaker to the far end and back along a different line, holding the phone camera-forward. The app records one sample every 2 s. The map should fill in along your path: red near the speaker, green at the far end. Areas more than 3 m from your path stay grey.
3. Press **Stop**. "Saved N samples" appears and the walk is added to **Saved walks**. Press ▶ to replay it at 10×. Press the share icon to export the JSON.
   If the level freezes or the debug panel's **Audio event** shows an interruption once ARKit starts, turn on **Level from ARKit mic**. ARKit then captures the mono mic itself (`providesAudioData`). The level is fine for this mode, but there is no direction.
4. Pass: the quietest spot (circle 1) is at the far end, not at the speaker and not in a grey area. The level range in the legend spans at least about 6 (relative dBFS).

JSON shape (`Documents/walks/<walk_id>.json`):
`{"walk_id","device","started_at","samples":[{"t","x","z","level_dbfs","tracking"}]}`.
`x` and `z` are **raw ARKit world coordinates** in metres from where the AR session started. With `.gravityAndHeading`, ARKit's camera looks along its own −z, world **−z is true north and +x is east**. So the map draws +x to the right and +z downward (north up). `t` is seconds since `started_at`. `level_dbfs` is the W channel's mean square over the preceding 2 s, or channel 0 when FOA is unavailable. It is relative and uncalibrated. `tracking` is always `"normal"` for stored samples. The map blend is the server's `sound_field.py`: 0.5 m cells, Gaussian σ 1.5 m × exp(−age/20 min), grey beyond 3 m, confidence 1 − exp(−Σw), up to 3 quiet spots within 1 m of a sample, at least 2 m apart, with confidence ≥ 0.5.

## Radar: 2-minute test

1. Put a speaker playing noise at a fixed spot about 2 m away. Open **Radar** and press **Reset**.
2. Stand in one place and turn slowly through 360° over about 30 s, holding the phone the same way throughout. By default the dial is heading-up: the red **N** turns with you.
3. Pass: one coloured wedge grows toward the speaker and **stays pointing at it as you turn**. The black line (dominant direction) and "Loudest from …°" stay within about ±15° throughout. Wedges you never heard from stay grey. "North up" freezes the dial for a screenshot.

How it works: for every 2048-sample analysis window whose own confidence is ≥ the slider, the window's 200–4000 Hz W-channel energy (and its level in relative dBFS) is added to the 15° sector of its world bearing, with exponential forgetting (τ = 20 s). Windows more than 60° above or below the horizon are ignored. A wedge's length and colour show its accumulated energy relative to the loudest wedge (0 to −30, relative dBFS). A sector with less than 0.25 s of confident audio is "not heard yet". Changing between CoreMotion and ARKit frames (Locate mode on or off) resets the radar, because the two norths differ.

## Locate: 2-minute test

1. Speaker playing noise at a fixed spot. Open **Locate** and turn on **Locate mode**. ARKit starts, and the origin "start" is where you are now. Wait for "tracking normal".
2. Stand 3–4 m from the speaker. Hold still for 2 s and press **Capture bearing here**. Walk 3–4 m sideways, so the rays cross at a good angle, and capture again. Optionally capture a third spot.
3. Pass: the red dot lands within about 1–2 m of the speaker, and the summary reads like "6.2 m NE of start, ±1.5 m". **Save as source** adds it to the list and clears the captures for the next source.

Details: a capture stores the position, the bearing of the dominant source over the last ~2 s (radar with τ = 2 s), the confidence, the level and the time. The estimate is the confidence-weighted least-squares intersection of the rays. Rays the solution would lie behind are dropped. If no pair of rays is ≥ 15° apart, the app refuses. "±" is the larger of the 1σ radius from assumed bearing errors (8° at confidence 1, growing as 1/confidence) and the RMS miss of the rays. If ARKit fails or is unsupported, the position picker falls back to **Type x/y**: metres east and north of your chosen origin. Or use **Walked line**: the first capture is at (0,0), and each next capture is "N m toward bearing B" from the previous one. "phone" fills in the bearing you are facing. Do not turn Locate mode off between captures: a new AR session has a new origin.

**Frames.** CoreMotion's frame uses *magnetic* north. ARKit's `.gravityAndHeading` uses *true* north (about 13° apart in San Francisco). So while ARKit runs, the app uses ARKit's camera orientation both for positions and for rotating the device-frame DOA into the world (`ARFrameMath` in `SourceMap.swift`, and `MotionTracker.setARAttitude`). Then bearings and positions share one frame. The mapping assumes Apple's documented camera space: +x from the front camera toward the bottom edge, +y toward the right edge in portrait, +z out of the screen. Check it with the debug row **ARKit − CoreMotion heading**: it should read roughly the local declination (+13° in SF). About ±90° or 180° means the mapping is wrong. If ARKit stops delivering frames for 0.3 s, DOA falls back to CoreMotion automatically. **Audio and ARKit:** ARKit runs the camera through its own capture session (`providesAudioData = false`, so it leaves the mic alone). If the audio session is interrupted anyway, the debug panel's **Audio event** row says so and **Restart audio** tries again.

## API names: confirmed or assumed

**Confirmed in Apple documentation (developer.apple.com doc pages, read Oct 2026):**
- `AVCaptureDeviceInput.isMultichannelAudioModeSupported(_:)`, `AVCaptureDeviceInput.multichannelAudioMode`, `AVCaptureMultichannelAudioMode.firstOrderAmbisonics` (iOS 18+).
- `AVCaptureAudioDataOutput.spatialAudioChannelLayoutTag: AudioChannelLayoutTag` (iOS 26+). Apple's doc says that in FOA mode it must be `kAudioChannelLayoutTag_Stereo` or `(kAudioChannelLayoutTag_HOA_ACN_SN3D | 4)`, otherwise the session throws `NSInvalidArgumentException` at start. A single output may be FOA-only, and up to two outputs (FOA plus stereo) are allowed.
- WWDC25 session 251 transcript: FOA is "4 channels of the ambisonic layout HOA - ACN - SN3D", an omni component plus X/Y/Z dipoles (front-back, left-right, up-down).
- `kAudioChannelLayoutTag_HOA_ACN_SN3D` (CoreAudioTypes), `vDSP.DiscreteFourierTransform(count:direction:transformType:ofType:)` and `transform(real:imaginary:)`, `vDSP.window(ofType:usingSequence:count:isHalfWindow:)`, `CMSampleBuffer.withAudioBufferList`, `CMFormatDescription.audioStreamBasicDescription`, `CMAudioFormatDescriptionGetChannelLayout`, `CMMotionManager.availableAttitudeReferenceFrames()`, `CMDeviceMotion.heading`.

**Assumed and not verified:**
1. Channel order is ACN, so channel indices 0..3 = W, Y, Z, X ("AmbiX"). This follows from the HOA_ACN_SN3D name; Apple doesn't spell out the indices. The Channel order picker can override it.
2. Axes follow the usual ambisonic convention: +X front, +Y left, +Z up.
3. Where "front" is on the phone. The default assumes the rear camera, with up being the top edge. Nothing found from Apple says this. It may even follow the capture connection's orientation. The calibration toggles exist because of this.
4. FOA works in an audio-only session with no camera input.
5. CoreMotion rotation convention `v_device = R · v_reference`. This is common usage; the Gravity check row verifies it on the device.
6. The dev.to post was only partly right: it names `spatialAudioChannelLayoutTag` but shows no code. The Apple doc page above is the source used.

Apple's sample project ("Capturing Spatial Audio in your iOS app", downloadable from the doc page) was not downloaded here. If something looks wrong, check its capture setup against `AudioCapture.configureAndRun()`.

## If FOA is not supported in an audio-only session

FOA may require a video input in the session. Add the back camera before checking support, in `AudioCapture.configureAndRun()`, after `session.beginConfiguration()`:

```swift
if let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
   let camInput = try? AVCaptureDeviceInput(device: cam), session.canAddInput(camInput) {
    session.addInput(camInput)
}
```

That also needs `NSCameraUsageDescription`. No video output is required just to get audio buffers.

## How the estimate works (one paragraph)

The app runs 2048-sample Hann windows with 50% hop. An FFT is taken of W, X, Y and Z. For each bin from 200 to 4000 Hz it computes `I = Re{conj(W)·[X,Y,Z]}`. It applies the calibration toggles, maps from the FOA frame to the device frame to the world frame, then exponentially smooths the summed vector and the summed magnitudes (τ = 0.5 s). Bearing is `atan2(-y, x)` in CoreMotion's north/west/up frame. Confidence is `|Σ I| / Σ |I|`. The arrow's screen rotation is the source bearing minus the phone's bearing. The phone's bearing is taken from the top edge when the phone lies flat and from the rear camera when it is held up. The level is the RMS of channel 0 (W) in dBFS: relative and uncalibrated, not SPL or dBA.
