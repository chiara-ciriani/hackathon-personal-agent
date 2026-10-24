"""Render a walk exported from the iPhone app into a top-down noise map and an animation of it filling in.

Uses the team server's sound_field.build_field, so the picture is what the server would compute.
Input: {"walk_id", "device", "started_at", "samples": [{"t", "x", "z", "level_dbfs", "tracking"}]}
with raw ARKit metres. ARKit's camera looks along -z, so forward is drawn up.

Run from the repo root: uv run --project server --with pillow python tools/walk_map.py walk.json [--out out_dir]
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

from PIL import Image, ImageDraw

REPO_SERVER = Path(__file__).resolve().parents[1] / "server"
sys.path.insert(0, str(REPO_SERVER))
from quiet_compass.sound_field import Sample, build_field  # noqa: E402

PX_PER_M = 40
QUIET, LOUD, UNKNOWN, INK, BG = (31, 122, 109), (200, 117, 43), (205, 212, 211), (20, 32, 31), (238, 242, 242)


def load(path: Path) -> list[dict]:
    walk = json.loads(path.read_text())
    rows = [s for s in walk["samples"] if s.get("tracking", "normal") == "normal" and s.get("level_dbfs") is not None]
    if not rows:
        raise SystemExit(f"{path}: no samples with normal tracking and a level")
    for s in rows:
        s["_t"] = datetime.fromisoformat(s["t"].replace("Z", "+00:00"))
    return sorted(rows, key=lambda s: s["_t"])


def render(rows: list[dict], upto: int, bounds: tuple[float, float, float, float]) -> Image.Image:
    shown = rows[:upto]
    now = shown[-1]["_t"]
    samples = [Sample(s["x"], s["z"], s["level_dbfs"], (now - s["_t"]).total_seconds() / 60) for s in shown]
    path = [(s["x"], s["z"]) for s in shown]
    field = build_field(samples, path, path[-1])
    x0, z0, x1, z1 = bounds
    img = Image.new("RGB", (int((x1 - x0) * PX_PER_M), int((z1 - z0) * PX_PER_M)), BG)
    d = ImageDraw.Draw(img)
    to_px = lambda x, z: ((x - x0) * PX_PER_M, (z - z0) * PX_PER_M)  # noqa: E731
    lo, hi = field.level_range_db
    half = field.cell_m / 2
    for c in field.cells:
        if c.level_db is None:
            colour = UNKNOWN
        else:
            t = (c.level_db - lo) / (hi - lo) if hi > lo else 0.5
            colour = tuple(int(q + (lo_ - q) * t) for q, lo_ in zip(QUIET, LOUD, strict=True))
            colour = tuple(int(BG[i] + (colour[i] - BG[i]) * (0.3 + 0.7 * c.confidence)) for i in range(3))
        (ax, az), (bx, bz) = to_px(c.x - half, c.z - half), to_px(c.x + half, c.z + half)
        d.rectangle([ax, az, bx, bz], fill=colour)
    d.line([to_px(x, z) for x, z in path], fill=INK, width=2)
    for i, s in enumerate(field.quiet_spots, 1):
        cx, cz = to_px(s.x, s.z)
        d.ellipse([cx - 12, cz - 12, cx + 12, cz + 12], outline=INK, width=3)
        d.text((cx - 3, cz - 6), str(i), fill=INK)
    ux, uz = to_px(*path[-1])
    d.ellipse([ux - 7, uz - 7, ux + 7, uz + 7], fill=QUIET, outline=INK)
    d.text((6, 6), f"{len(shown)} readings, {lo:.0f} to {hi:.0f} dBFS (relative); grey = not measured", fill=INK)
    return img


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("walk", type=Path)
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--frames", type=int, default=40, help="animation frames")
    args = ap.parse_args()
    rows = load(args.walk)
    out = args.out or args.walk.with_suffix("")
    out.mkdir(parents=True, exist_ok=True)
    pad = 3.5
    xs, zs = [s["x"] for s in rows], [s["z"] for s in rows]
    bounds = (min(xs) - pad, min(zs) - pad, max(xs) + pad, max(zs) + pad)
    final = render(rows, len(rows), bounds)
    final.save(out / "map.png")
    steps = sorted({max(1, round(len(rows) * k / args.frames)) for k in range(1, args.frames + 1)})
    frames = [render(rows, n, bounds) for n in steps]
    frames[0].save(out / "replay.gif", save_all=True, append_images=frames[1:] + [final] * 8, duration=120, loop=0)
    print(f"{len(rows)} readings -> {out / 'map.png'} and {out / 'replay.gif'}")


if __name__ == "__main__":
    main()
