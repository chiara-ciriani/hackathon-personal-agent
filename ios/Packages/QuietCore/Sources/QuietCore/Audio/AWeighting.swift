// A-weighting filter for 48 kHz, pure Swift.
//
// Derivation
// ----------
// IEC 61672-1 defines the analogue A-weighting response with four pole frequencies
//   f1 = 20.598997 Hz (double), f2 = 107.65265 Hz, f3 = 737.86223 Hz, f4 = 12194.217 Hz (double)
// and four zeros at s = 0:
//   H(s) = K · s⁴ / ((s + ω1)² (s + ω2)(s + ω3)(s + ω4)²),   ωi = 2π·fi.
// We map it to the z-plane with the bilinear transform s = 2·fs·(1 − z⁻¹)/(1 + z⁻¹) without
// pre-warping (as in the widely used MATLAB `adsgn` / Octave `A_weighting` scripts):
//   - each real pole −ωi maps to a z-plane pole pi = (2fs − ωi)/(2fs + ωi),
//   - each zero at s = 0 maps to z = 1, i.e. a factor (1 − z⁻¹),
//   - the order mismatch (4 zeros, 6 poles) puts the two remaining zeros at z = −1, (1 + z⁻¹)².
// Grouped into three second-order sections:
//   SOS1 (high-pass, f1 double pole):  (1 − z⁻¹)² / (1 − p1 z⁻¹)²
//   SOS2 (high-pass, f4 double pole):  (1 − z⁻¹)² / (1 − p4 z⁻¹)²
//   SOS3 (low-pass, f2 and f3 poles):  (1 + z⁻¹)² / ((1 − p2 z⁻¹)(1 − p3 z⁻¹))
// The overall gain is chosen so that |H| = 1 (0 dB) at 1 kHz, computed numerically at init.
//
// Accuracy at 48 kHz (checked numerically): 100 Hz −19.1 dB, 1 kHz 0.0 dB, 4 kHz +0.9 dB, 8 kHz −1.7 dB,
// 16 kHz −13 dB. Below ~10 kHz this is within ~0.5 dB of the IEC table (e.g. 100 Hz −19.1, 4 kHz +1.0,
// 8 kHz −1.1); the bilinear warping makes the top octave fall off early, which is fine for a relative metric.
import Foundation

/// One biquad section, normalized so a0 = 1.
public struct BiquadCoefficients: Sendable, Hashable {
    public var b0, b1, b2, a1, a2: Double
    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    /// Complex response at frequency f (Hz) for sample rate fs, as (re, im).
    func response(f: Double, fs: Double) -> (re: Double, im: Double) {
        let w = 2 * Double.pi * f / fs
        // z⁻¹ = e^{−jw}
        let c1 = cos(w), s1 = -sin(w), c2 = cos(2 * w), s2 = -sin(2 * w)
        let nr = b0 + b1 * c1 + b2 * c2, ni = b1 * s1 + b2 * s2
        let dr = 1 + a1 * c1 + a2 * c2, di = a1 * s1 + a2 * s2
        let den = dr * dr + di * di
        return ((nr * dr + ni * di) / den, (ni * dr - nr * di) / den)
    }
}

public enum AWeighting {
    public static let f1 = 20.598997
    public static let f2 = 107.65265
    public static let f3 = 737.86223
    public static let f4 = 12194.217

    /// Second-order sections for sample rate `fs` (designed for 48 kHz; 44.1 kHz also works).
    /// The overall gain is folded into the first section so the cascade is 0 dB at 1 kHz.
    public static func sections(sampleRate fs: Double = 48_000) -> [BiquadCoefficients] {
        func pole(_ f: Double) -> Double {
            let w = 2 * Double.pi * f
            return (2 * fs - w) / (2 * fs + w)
        }
        let p1 = pole(f1), p2 = pole(f2), p3 = pole(f3), p4 = pole(f4)
        var s = [
            BiquadCoefficients(b0: 1, b1: -2, b2: 1, a1: -2 * p1, a2: p1 * p1),
            BiquadCoefficients(b0: 1, b1: -2, b2: 1, a1: -2 * p4, a2: p4 * p4),
            BiquadCoefficients(b0: 1, b1: 2, b2: 1, a1: -(p2 + p3), a2: p2 * p3)
        ]
        let g = 1 / magnitude(sections: s, f: 1000, fs: fs)
        s[0].b0 *= g; s[0].b1 *= g; s[0].b2 *= g
        return s
    }

    /// |H(f)| of a cascade.
    public static func magnitude(sections: [BiquadCoefficients], f: Double, fs: Double) -> Double {
        var re = 1.0, im = 0.0
        for sec in sections {
            let r = sec.response(f: f, fs: fs)
            (re, im) = (re * r.re - im * r.im, re * r.im + im * r.re)
        }
        return (re * re + im * im).squareRoot()
    }

    /// Response in dB at f for the default 48 kHz design.
    public static func responseDb(at f: Double, sampleRate fs: Double = 48_000) -> Double {
        20 * log10(magnitude(sections: sections(sampleRate: fs), f: f, fs: fs))
    }
}

/// Stateful biquad cascade, Direct Form II transposed, Double state for stability of the
/// low-frequency poles (p1 ≈ 0.9973). Not thread-safe: own one per stream.
public struct BiquadCascade: Sendable {
    public let sections: [BiquadCoefficients]
    private var z1: [Double]
    private var z2: [Double]

    public init(sections: [BiquadCoefficients]) {
        self.sections = sections
        z1 = Array(repeating: 0, count: sections.count)
        z2 = Array(repeating: 0, count: sections.count)
    }

    /// A-weighting at `sampleRate`.
    public static func aWeighting(sampleRate: Double = 48_000) -> BiquadCascade {
        BiquadCascade(sections: AWeighting.sections(sampleRate: sampleRate))
    }

    public mutating func reset() {
        for i in z1.indices { z1[i] = 0; z2[i] = 0 }
    }

    public mutating func process(_ x: Double) -> Double {
        var v = x
        for i in 0..<sections.count { v = step(i, v) }
        return v
    }

    private mutating func step(_ i: Int, _ x: Double) -> Double {
        let c = sections[i]
        let y = c.b0 * x + z1[i]
        z1[i] = c.b1 * x - c.a1 * y + z2[i]
        z2[i] = c.b2 * x - c.a2 * y
        return y
    }

    /// Filters a buffer in place.
    public mutating func process(_ buffer: inout [Float]) {
        for n in buffer.indices { buffer[n] = Float(process(Double(buffer[n]))) }
    }

    /// Filters a buffer and returns the output.
    public mutating func processed(_ input: [Float]) -> [Float] {
        var out = input
        process(&out)
        return out
    }
}
