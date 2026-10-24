"""The desktop renderer accepts the JSON contract exported by QC Walk Map."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest
from PIL import Image

SCRIPT = Path(__file__).resolve().parents[2] / "tools" / "walk_map.py"
spec = importlib.util.spec_from_file_location("walk_map", SCRIPT)
walk_map = importlib.util.module_from_spec(spec)
spec.loader.exec_module(walk_map)


def export(tmp_path, samples):
    target = tmp_path / "walk.json"
    target.write_text(json.dumps({
        "walk_id": "software-test", "device": "synthetic-fixture",
        "started_at": "2026-10-24T17:00:00Z", "samples": samples,
    }))
    return target


def sample(t=2, **overrides):
    return {"t": t, "x": 0.5, "z": -1.25, "level_dbfs": -42.5, "tracking": "normal", **overrides}


def test_native_elapsed_seconds_are_sorted_and_aged_from_walk_start(tmp_path):
    rows = walk_map.load(export(tmp_path, [sample(62), sample(2)]))
    assert rows[0]["_t"].isoformat() == "2026-10-24T17:00:02+00:00"
    assert (rows[1]["_t"] - rows[0]["_t"]).total_seconds() == 60


def test_legacy_timestamps_and_limited_tracking(tmp_path):
    rows = walk_map.load(export(tmp_path, [sample("2026-10-24T17:00:02Z"), sample(tracking="limited")]))
    assert len(rows) == 1
    assert rows[0]["_t"].second == 2


@pytest.mark.parametrize("row", [sample(-1), sample(True), sample(float("nan")), sample(x=float("inf"))])
def test_invalid_samples_fail_before_grid_generation(tmp_path, row):
    with pytest.raises(SystemExit, match="invalid walk sample"):
        walk_map.load(export(tmp_path, [row]))


@pytest.mark.parametrize("samples", [[sample()], [sample(), sample(4, x=2), sample(6, x=4)]])
def test_cli_renders_native_json_to_map_and_replay(tmp_path, samples):
    source = export(tmp_path, samples)
    out = tmp_path / "rendered"
    subprocess.run([sys.executable, str(SCRIPT), str(source), "--out", str(out), "--frames", "3"],
                   check=True, capture_output=True, text=True)
    with Image.open(out / "map.png") as still:
        assert still.format == "PNG" and still.width > 0 and still.height > 0
    with Image.open(out / "replay.gif") as replay:
        assert replay.format == "GIF" and replay.size == still.size
