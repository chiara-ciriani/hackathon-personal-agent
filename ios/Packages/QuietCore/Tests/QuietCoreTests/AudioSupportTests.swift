import Foundation
@testable import QuietCore

/// Deterministic uniform noise (SplitMix64) so tests behave the same on every platform.
struct TestNoise {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [−1, 1).
    mutating func uniform() -> Float {
        Float(Double(next() >> 11) / Double(1 << 53) * 2 - 1)
    }

    mutating func samples(_ n: Int, amplitude: Float) -> [Float] {
        (0..<n).map { _ in uniform() * amplitude }
    }
}

enum TestSignals {
    static func sine(frequency: Double, amplitude: Double, count: Int, sampleRate: Double = 48_000) -> [Float] {
        (0..<count).map { Float(amplitude * sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    /// Noise bursts: on for `onSamples` out of every `periodSamples`.
    static func bursts(count: Int, amplitude: Float, onSamples: Int = 4800, periodSamples: Int = 12000,
                       seed: UInt64) -> [Float] {
        var rng = TestNoise(seed: seed)
        return (0..<count).map { i in (i % periodSamples) < onSamples ? rng.uniform() * amplitude : 0 }
    }

    static func add(_ a: [Float], _ b: [Float]) -> [Float] { zip(a, b).map { $0 + $1 } }
}

func angularDistance(_ a: Double, _ b: Double) -> Double {
    abs(DirectionMath.wrapDegrees(a - b))
}
