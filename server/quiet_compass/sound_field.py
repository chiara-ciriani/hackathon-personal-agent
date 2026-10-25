"""Pure sound-field estimate for one session's floor plane. No I/O; constants live in `FieldConfig`.

The phone sends an observation every few seconds with its AR position (metres, x/z). As the
user walks, the field fills in along the path:

1. Grid: cells of `cell_m` covering every positioned sample and crumb plus `padding_m`. The
   cell size grows if the grid would exceed `max_cells`.
2. Each cell blends nearby samples with a Gaussian weight on distance (σ = `kernel_m`) times
   an age weight exp(−age/τ), so a newer reading at a spot outweighs an older one there.
3. A cell further than `max_support_m` from every sample is unknown (level None). An unmeasured
   area is never reported as quiet.
4. confidence = 1 − exp(−Σw): one fresh reading on the cell gives ~0.63, two give ~0.86.
5. Quiet spots: the quietest cells within `spot_max_distance_m` of a real reading, with
   confidence ≥ `min_spot_confidence`, at least `spot_separation_m` apart. A cell at the edge of
   the measured area is never a spot just because no loud reading sits beyond it.

Levels are relative dBFS from one device profile, so only pass samples from one session.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass


@dataclass(frozen=True)
class FieldConfig:
    cell_m: float = 0.5
    kernel_m: float = 1.5
    max_support_m: float = 3.0
    age_tau_min: float = 20.0
    padding_m: float = 1.5
    max_cells: int = 6000
    min_spot_confidence: float = 0.5
    spot_max_distance_m: float = 1.0
    spot_separation_m: float = 2.0
    max_spots: int = 3


DEFAULT_CONFIG = FieldConfig()


@dataclass(frozen=True)
class Sample:
    x: float
    z: float
    level_db: float
    age_min: float


@dataclass(frozen=True)
class Cell:
    x: float
    z: float
    level_db: float | None
    confidence: float
    age_min: float | None
    nearest_m: float


@dataclass(frozen=True)
class QuietSpot:
    x: float
    z: float
    level_db: float
    confidence: float
    age_min: float
    distance_m: float | None


@dataclass(frozen=True)
class SoundField:
    cell_m: float
    origin_x: float
    origin_z: float
    cols: int
    rows: int
    cells: list[Cell]
    level_range_db: tuple[float, float] | None
    quiet_spots: list[QuietSpot]


def _bounds(points: Sequence[tuple[float, float]], pad: float) -> tuple[float, float, float, float]:
    xs = [p[0] for p in points]
    zs = [p[1] for p in points]
    return min(xs) - pad, min(zs) - pad, max(xs) + pad, max(zs) + pad


def _grid(
    points: Sequence[tuple[float, float]], cfg: FieldConfig
) -> tuple[float, float, float, int, int]:
    x0, z0, x1, z1 = _bounds(points, cfg.padding_m)
    cell = cfg.cell_m
    while True:
        cols = max(1, math.ceil((x1 - x0) / cell))
        rows = max(1, math.ceil((z1 - z0) / cell))
        if cols * rows <= cfg.max_cells:
            return x0, z0, cell, cols, rows
        cell *= 1.5


def _estimate(x: float, z: float, samples: Sequence[Sample], cfg: FieldConfig) -> Cell:
    two_sigma2 = 2 * cfg.kernel_m**2
    total = weighted = 0.0
    nearest = math.inf
    nearest_age: float | None = None
    for s in samples:
        d2 = (s.x - x) ** 2 + (s.z - z) ** 2
        if d2 < nearest:
            nearest, nearest_age = d2, s.age_min
        w = math.exp(-d2 / two_sigma2) * math.exp(-max(s.age_min, 0.0) / cfg.age_tau_min)
        total += w
        weighted += w * s.level_db
    nearest_m = math.sqrt(nearest)
    if nearest_m > cfg.max_support_m or total <= 0:
        return Cell(x, z, None, 0.0, None, nearest_m)
    return Cell(x, z, weighted / total, 1 - math.exp(-total), nearest_age, nearest_m)


def _spots(cells: Sequence[Cell], user: tuple[float, float] | None, cfg: FieldConfig) -> list[QuietSpot]:
    candidates = sorted(
        (
            c for c in cells
            if c.level_db is not None
            and c.confidence >= cfg.min_spot_confidence
            and c.nearest_m <= cfg.spot_max_distance_m
        ),
        key=lambda c: c.level_db,
    )
    spots: list[QuietSpot] = []
    for c in candidates:
        if any(math.dist((c.x, c.z), (s.x, s.z)) < cfg.spot_separation_m for s in spots):
            continue
        distance = math.dist((c.x, c.z), user) if user is not None else None
        spots.append(QuietSpot(c.x, c.z, c.level_db, c.confidence, c.age_min or 0.0, distance))
        if len(spots) == cfg.max_spots:
            break
    return spots


def build_field(
    samples: Sequence[Sample],
    path: Sequence[tuple[float, float]] = (),
    user: tuple[float, float] | None = None,
    cfg: FieldConfig = DEFAULT_CONFIG,
) -> SoundField | None:
    """Estimate the field, or None when there is no positioned sample yet."""
    if not samples:
        return None
    points = [(s.x, s.z) for s in samples] + list(path)
    x0, z0, cell, cols, rows = _grid(points, cfg)
    cells = [
        _estimate(x0 + (col + 0.5) * cell, z0 + (row + 0.5) * cell, samples, cfg)
        for row in range(rows)
        for col in range(cols)
    ]
    levels = [s.level_db for s in samples]
    return SoundField(
        cell_m=cell,
        origin_x=x0,
        origin_z=z0,
        cols=cols,
        rows=rows,
        cells=cells,
        level_range_db=(min(levels), max(levels)),
        quiet_spots=_spots(cells, user, cfg),
    )
