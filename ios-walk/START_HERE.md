# QC Walk Map on the iPhone in 10 minutes

This is the standalone walk-map app in `ios-walk/` (shown as **QC Walk Map** on the home screen). It needs no server. The team app in `ios/` is a different app (shown as **Quiet Compass**) and needs a server connection before "Start measuring" works.

You need a Mac with **Xcode 26** and an **iPhone 16 Pro or newer** (spatial audio + LiDAR) with a USB-C cable.

## On the Mac

1. Pull `main` and open Terminal in the `ios-walk` folder.
2. Run:

   ```bash
   chmod +x setup.sh && ./setup.sh
   ```

   It installs XcodeGen with Homebrew if needed, creates `QuietCompassWalk.xcodeproj` and opens it.
3. In Xcode, select the **QuietCompassWalk** target → **Signing & Capabilities** → **Team**: pick your Apple ID (a free one works; add it under Xcode → Settings → Accounts). If Xcode says the bundle id is taken, change `com.hackathon.quietcompass.walk` to anything unique.
4. Plug in the iPhone, choose it at the top of the window, press **Run** (⌘R).

## On the iPhone (first time only)

5. **Developer Mode:** Settings → Privacy & Security → Developer Mode → On. The phone restarts; confirm after it boots.
6. If the app does not open: Settings → General → VPN & Device Management → your Apple ID → **Trust**.
7. Allow **Microphone**, **Camera** and **Motion** when the app asks.

## Use it

- **Walk map:** press Record and walk slowly with the phone held up, camera forward. The map fills in as you go; grey means not walked yet. Stop saves the walk; Replay plays it back; Share exports the JSON.
- **Radar:** stand still and turn slowly; the loud wedge should point at the noise source.
- **Compass:** the arrow points at the dominant noise source.
- The debug panel shows whether the phone delivers 4-channel spatial audio. If it says 1–2 channels, the walk map still works; radar and compass do not.

## Show a recorded walk on a laptop

Export the walk JSON (Share) and AirDrop it to the laptop with this repo, then from the repo root:

```bash
uv run --project server --with pillow python tools/walk_map.py walk.json
```

It writes `map.png` and `replay.gif` next to the file, computed with the team server's sound-field code.

## If the build fails

- **Concurrency errors:** Build Settings → Swift Compiler → Language → Default Actor Isolation → `nonisolated`, then build again.
- **"No such module ARKit" or device not supported:** run on a real iPhone, not the Simulator.
- Anything else: copy the first red error from Xcode's Issue navigator and send it over.
