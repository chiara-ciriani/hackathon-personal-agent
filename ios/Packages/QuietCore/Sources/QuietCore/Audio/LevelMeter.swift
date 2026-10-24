// Relative level helpers. Foundation only, so this compiles on Linux.
//
// All levels are relative, uncalibrated dBFS: a mean square of 1.0 (a full-scale DC signal) is 0 dB,
// a full-scale sine is about −3.01 dB. They are never dBA or SPL.
import Foundation

public enum LevelMeter {
    /// Added to every power before the log so silence maps to −120 dB instead of −∞.
    public static let powerFloor: Double = 1e-12
    /// 125 ms frames, eight per second.
    public static let framesPerSecond = 8
    public static let frameDuration: Double = 0.125

    /// 10·log10(power + 1e-12).
    @inlinable
    public static func db(power: Double) -> Double {
        10 * log10(power + powerFloor)
    }

    /// Inverse of `db(power:)`, ignoring the floor.
    @inlinable
    public static func power(db: Double) -> Double {
        pow(10, db / 10)
    }

    /// mean(x²) of a buffer; 0 for an empty buffer.
    public static func meanSquare(_ samples: [Float]) -> Double {
        samples.withUnsafeBufferPointer { meanSquare($0) }
    }

    public static func meanSquare(_ samples: UnsafeBufferPointer<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        var acc = 0.0
        for s in samples { let d = Double(s); acc += d * d }
        return acc / Double(samples.count)
    }

    /// Level of one 125 ms frame: 10·log10(mean(x²) + 1e-12).
    public static func frameLevelDb(_ samples: [Float]) -> Double {
        db(power: meanSquare(samples))
    }

    /// Power mean of dB values: each level is converted to power, the powers are averaged, and the
    /// mean is converted back to dB. This is how the 1 s level is built from the eight 125 ms frame
    /// levels, and how the 5 s observation level is built from five 1 s levels. It is *not* the
    /// arithmetic mean of the dB values (that would under-weight loud frames).
    /// Returns nil for an empty input.
    public static func powerMeanDb(_ levelsDb: [Double]) -> Double? {
        guard !levelsDb.isEmpty else { return nil }
        var acc = 0.0
        for l in levelsDb { acc += power(db: l) }
        // max() instead of +floor so that powerMeanDb([x]) == x even near the floor.
        return 10 * log10(max(acc / Double(levelsDb.count), powerFloor))
    }

    /// The 1 s level from its eight 125 ms frame levels (power average).
    public static func secondLevelDb(frameLevelsDb: [Double]) -> Double {
        powerMeanDb(frameLevelsDb) ?? db(power: 0)
    }
}
