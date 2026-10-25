# QC Walk Map on the iPhone in 10 minutes

This is the standalone walk-map app in `ios-walk/` (shown as **QC Walk Map** on the home screen). Local mode needs no server. For agent mode open the agent’s phone link, choose **Open iPhone app**, and approve **Allow agent analysis**. Deploy both the relay and server from current main. The team app in `ios/` is a different app (shown as **Quiet Compass**) and needs a server connection before "Start measuring" works.

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

- **Quiet Map:** after the permissions prompts, mapping starts when the app opens. Walk slowly with the phone held up, camera forward. The map fills in as you go; grey means not measured. The card points toward the quietest measured spot. **Stop and save** saves the walk. Replay and export are under **Advanced → Walk map**.
- **Advanced → Radar:** stand still and turn slowly; the loud wedge should point at the noise source.
- **Advanced → Compass:** the arrow points at the dominant noise source.
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

## Community sharing, version 1.1 build 2

Tap **Measure and share** on the main screen and confirm sharing. Allow microphone and
location access. Stand still for 30 seconds. The app pauses room mapping, keeps audio
on the phone, and uploads only a numeric sound summary with coordinates rounded to
about 100 m. An agent link is not required. Sharing stops when the app goes into the
background. A failed upload can retry the same summary without duplicating it.

Tap **Open community map** after upload to open the website with 15 minutes of map
access. Other contributors can see released readings there; the website refreshes
shared phone readings every 30 seconds while visible. The existing release rule needs
two matching contributions in one area, five-minute bucket and capture profile.
A first summary can therefore remain hidden. Measure again to add a second real
summary. No audio, private walk, or room positions enter the community map.

Deploy the server and web app from the same commit, then rebuild and install this app.
Existing installed apps do not update from a Git push. This version adds the iOS
location permission description and uses the existing website origin in AgentProtocol.
