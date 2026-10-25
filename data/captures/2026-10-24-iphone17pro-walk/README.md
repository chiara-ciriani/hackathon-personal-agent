# First real walk: iPhone 17 Pro, 2026-10-24

A 126 s walk around the hackathon room with the Quiet Compass app, sent live to the team server.

There is no audio here: the app never uploads it. Each observation is the phone's own 5 s summary.

| File | What it is |
| --- | --- |
| `capture.json` | `session` (device profile), 61 `crumbs` (ARKit path), 26 `observations` (levels, bands, speech share, sound classes), exported from the server database |
| `map.png` | Sound field built from these observations by `server/quiet_compass/sound_field.py` |
| `timeline.gif` | Replay: path, field filling in, and the level of each reading over time |
| `timeline_final.png` | Last frame of the replay |

Positions are ARKit metres on the floor plane (`x` east, `z` south, origin where the walk started), not GPS.
Levels are dBFS relative to this phone's capture profile, not dB SPL. The single loud reading (-32 dBFS)
is what makes the orange zone; the rest sits between -50 and -59 dBFS.
