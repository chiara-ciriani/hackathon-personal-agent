import Foundation

// Pure maths for the "Walk map" mode (no Apple framework beyond Foundation, so the
// self-check in SelfCheck/main.swift can compile it with plain `swiftc`).
//
// A port of the team server's quiet_compass/sound_field.py, same constants and blend:
//   1. Grid of 0.5 m cells covering every sample and path point plus 1.5 m padding
//      (the cell grows ×1.5 while the grid would exceed 6000 cells).
//   2. Each cell = Gaussian-weighted mean of sample levels (σ = 1.5 m) × exp(−age/20 min).
//   3. A cell further than 3 m from every sample is unknown (nil): never reported as quiet.
//   4. confidence = 1 − exp(−Σw).
//   5. Quiet spots: quietest cells within 1 m of a real sample, confidence ≥ 0.5,
//      at least 2 m apart, at most 3.
// Coordinates are raw ARKit world x/z in metres (see WalkRecord below for the convention).
// Levels are relative dBFS from one phone: only compare samples from one walk.

nonisolated struct FieldConfig: Sendable {
    var cellM = 0.5
    var kernelM = 1.5
    var maxSupportM = 3.0
    var ageTauMin = 20.0
    var paddingM = 1.5
    var maxCells = 6000
    var minSpotConfidence = 0.5
    var spotMaxDistanceM = 1.0
    var spotSeparationM = 2.0
    var maxSpots = 3
}

nonisolated struct FieldSample: Sendable {
    var x: Double
    var z: Double
    var levelDB: Double
    var ageMin: Double
}

nonisolated struct FieldCell: Sendable {
    var x: Double
    var z: Double
    var levelDB: Double?      // nil = not measured (further than maxSupportM from every sample)
    var confidence: Double
    var ageMin: Double?
    var nearestM: Double
}

nonisolated struct QuietSpot: Sendable {
    var x: Double
    var z: Double
    var levelDB: Double
    var confidence: Double
    var ageMin: Double
    var distanceM: Double?    // from the user, when a user position was given
}

nonisolated struct SoundField: Sendable {
    var cellM: Double
    var originX: Double
    var originZ: Double
    var cols: Int
    var rows: Int
    var cells: [FieldCell]          // row-major: index = row * cols + col
    var levelRange: ClosedRange<Double>?
    var quietSpots: [QuietSpot]

    /// The cell whose square contains (x, z), or nil outside the grid.
    func cell(atX x: Double, z: Double) -> FieldCell? {
        let col = Int(((x - originX) / cellM).rounded(.down))
        let row = Int(((z - originZ) / cellM).rounded(.down))
        guard (0..<cols).contains(col), (0..<rows).contains(row) else { return nil }
        return cells[row * cols + col]
    }

    /// Estimate the field, or nil when there is no positioned sample yet.
    static func build(samples: [FieldSample], path: [SIMD2<Double>] = [], user: SIMD2<Double>? = nil,
                      config cfg: FieldConfig = FieldConfig()) -> SoundField? {
        guard !samples.isEmpty else { return nil }
        let points = samples.map { SIMD2($0.x, $0.z) } + path
        let (x0, z0, cell, cols, rows) = grid(points, cfg)
        var cells: [FieldCell] = []
        cells.reserveCapacity(cols * rows)
        for row in 0..<rows {
            for col in 0..<cols {
                cells.append(estimate(x: x0 + (Double(col) + 0.5) * cell, z: z0 + (Double(row) + 0.5) * cell,
                                      samples: samples, cfg))
            }
        }
        let levels = samples.map(\.levelDB)
        return SoundField(cellM: cell, originX: x0, originZ: z0, cols: cols, rows: rows, cells: cells,
                          levelRange: levels.min()!...levels.max()!,
                          quietSpots: spots(cells, user: user, cfg))
    }

    private static func grid(_ points: [SIMD2<Double>], _ cfg: FieldConfig)
        -> (Double, Double, Double, Int, Int) {
        let x0 = points.map(\.x).min()! - cfg.paddingM, x1 = points.map(\.x).max()! + cfg.paddingM
        let z0 = points.map(\.y).min()! - cfg.paddingM, z1 = points.map(\.y).max()! + cfg.paddingM
        var cell = cfg.cellM
        while true {
            let cols = max(1, Int(((x1 - x0) / cell).rounded(.up)))
            let rows = max(1, Int(((z1 - z0) / cell).rounded(.up)))
            if cols * rows <= cfg.maxCells { return (x0, z0, cell, cols, rows) }
            cell *= 1.5
        }
    }

    private static func estimate(x: Double, z: Double, samples: [FieldSample], _ cfg: FieldConfig) -> FieldCell {
        let twoSigma2 = 2 * cfg.kernelM * cfg.kernelM
        var total = 0.0, weighted = 0.0
        var nearest = Double.infinity
        var nearestAge: Double?
        for s in samples {
            let d2 = (s.x - x) * (s.x - x) + (s.z - z) * (s.z - z)
            if d2 < nearest { nearest = d2; nearestAge = s.ageMin }
            let w = exp(-d2 / twoSigma2) * exp(-max(s.ageMin, 0) / cfg.ageTauMin)
            total += w
            weighted += w * s.levelDB
        }
        let nearestM = nearest.squareRoot()
        guard nearestM <= cfg.maxSupportM, total > 0 else {
            return FieldCell(x: x, z: z, levelDB: nil, confidence: 0, ageMin: nil, nearestM: nearestM)
        }
        return FieldCell(x: x, z: z, levelDB: weighted / total, confidence: 1 - exp(-total),
                         ageMin: nearestAge, nearestM: nearestM)
    }

    private static func spots(_ cells: [FieldCell], user: SIMD2<Double>?, _ cfg: FieldConfig) -> [QuietSpot] {
        let candidates = cells
            .filter { $0.levelDB != nil && $0.confidence >= cfg.minSpotConfidence && $0.nearestM <= cfg.spotMaxDistanceM }
            .sorted { $0.levelDB! < $1.levelDB! }   // stable, like Python's sorted
        var out: [QuietSpot] = []
        for c in candidates {
            if out.contains(where: { hypot($0.x - c.x, $0.z - c.z) < cfg.spotSeparationM }) { continue }
            let distance = user.map { hypot(c.x - $0.x, c.z - $0.y) }
            out.append(QuietSpot(x: c.x, z: c.z, levelDB: c.levelDB!, confidence: c.confidence,
                                 ageMin: c.ageMin ?? 0, distanceM: distance))
            if out.count == cfg.maxSpots { break }
        }
        return out
    }
}

// MARK: - Saved walk (JSON)

/// One walk as saved to Documents/walks/<walk_id>.json and shared from the app:
/// {"walk_id","device","started_at","samples":[{"t","x","z","level_dbfs","tracking"}]}
///
/// Coordinate convention: x and z are RAW ARKit world coordinates in metres
/// (ARWorldTrackingConfiguration, worldAlignment = .gravityAndHeading). The origin is where
/// the AR session started, +y is up (not stored), ARKit's camera looks along its own −z, and
/// with .gravityAndHeading world −z points to true north and +x to east. So north = −z,
/// east = +x. `t` is seconds since `started_at`; `level_dbfs` is relative, uncalibrated dBFS
/// of the W (or mono) channel averaged over the 2 s before the sample; `tracking` is
/// "normal" for every stored sample (samples are skipped while tracking is limited).
nonisolated struct WalkSample: Codable, Sendable, Equatable {
    var t: Double
    var x: Double
    var z: Double
    var levelDBFS: Double
    var tracking: String

    enum CodingKeys: String, CodingKey {
        case t, x, z, tracking
        case levelDBFS = "level_dbfs"
    }
}

nonisolated struct WalkRecord: Codable, Sendable, Identifiable, Equatable {
    var walkID: String
    var device: String
    var startedAt: String
    var samples: [WalkSample]

    var id: String { walkID }

    enum CodingKeys: String, CodingKey {
        case device, samples
        case walkID = "walk_id"
        case startedAt = "started_at"
    }

    /// Field inputs as seen at time `now` (seconds since start): samples up to `now`, aged
    /// relative to `now`. Pass the last sample's t for a finished walk.
    func fieldSamples(upTo now: Double) -> [FieldSample] {
        samples.filter { $0.t <= now && $0.tracking == "normal" }
            .map { FieldSample(x: $0.x, z: $0.z, levelDB: $0.levelDBFS, ageMin: (now - $0.t) / 60) }
    }
}
