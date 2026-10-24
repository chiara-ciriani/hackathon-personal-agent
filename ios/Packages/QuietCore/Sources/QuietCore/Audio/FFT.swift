// Portable radix-2 FFT and power spectrum. Foundation only.
//
// This is a straightforward iterative Cooley–Tukey FFT with precomputed twiddles. It exists so the DSP
// is testable on Linux and works on device without Accelerate; the app may swap in vDSP for the octave
// bands through `PowerSpectrumComputing` (see ios/QuietCompass/Audio/VDSPPowerSpectrum.swift).
import Foundation

/// Computes the one-sided power spectrum |X[k]|², k = 0…size/2, of a real, already-windowed frame
/// of exactly `size` samples. No scaling is applied (see `OctaveBandAnalyzer` for normalization).
public protocol PowerSpectrumComputing: Sendable {
    var size: Int { get }
    func powerSpectrum(of windowed: [Float]) -> [Double]
}

public struct FFT: Sendable, PowerSpectrumComputing {
    public let size: Int
    private let log2n: Int
    private let cosTable: [Double]
    private let sinTable: [Double]
    private let bitReversed: [Int]

    /// `size` must be a power of two ≥ 2.
    public init(size: Int) {
        precondition(size >= 2 && size & (size - 1) == 0, "FFT size must be a power of two")
        self.size = size
        var l = 0
        while (1 << l) < size { l += 1 }
        log2n = l
        var c = [Double](repeating: 0, count: size / 2)
        var s = [Double](repeating: 0, count: size / 2)
        for k in 0..<(size / 2) {
            let a = -2 * Double.pi * Double(k) / Double(size)
            c[k] = cos(a); s[k] = sin(a)
        }
        cosTable = c; sinTable = s
        var rev = [Int](repeating: 0, count: size)
        for i in 0..<size {
            var x = i, r = 0
            for _ in 0..<l { r = (r << 1) | (x & 1); x >>= 1 }
            rev[i] = r
        }
        bitReversed = rev
    }

    /// In-place forward complex FFT: X[k] = Σ x[n]·e^{−j2πkn/N}.
    public func transform(re: inout [Double], im: inout [Double]) {
        precondition(re.count == size && im.count == size)
        let n = size
        re.withUnsafeMutableBufferPointer { r in
            im.withUnsafeMutableBufferPointer { i in
                for a in 0..<n {
                    let b = bitReversed[a]
                    if b > a { r.swapAt(a, b); i.swapAt(a, b) }
                }
                var len = 2
                while len <= n {
                    let half = len / 2
                    let step = n / len
                    var start = 0
                    while start < n {
                        var t = 0
                        for k in 0..<half {
                            let wr = cosTable[t], wi = sinTable[t]
                            let p = start + k, q = p + half
                            let xr = r[q] * wr - i[q] * wi
                            let xi = r[q] * wi + i[q] * wr
                            r[q] = r[p] - xr; i[q] = i[p] - xi
                            r[p] += xr; i[p] += xi
                            t += step
                        }
                        start += len
                    }
                    len <<= 1
                }
            }
        }
    }

    /// One-sided complex spectrum (bins 0…size/2) of a real frame.
    public func realSpectrum(_ x: [Float]) -> (re: [Double], im: [Double]) {
        precondition(x.count == size)
        var re = x.map { Double($0) }
        var im = [Double](repeating: 0, count: size)
        transform(re: &re, im: &im)
        let m = size / 2 + 1
        return (Array(re[0..<m]), Array(im[0..<m]))
    }

    public func powerSpectrum(of windowed: [Float]) -> [Double] {
        let (re, im) = realSpectrum(windowed)
        var p = [Double](repeating: 0, count: re.count)
        for k in p.indices { p[k] = re[k] * re[k] + im[k] * im[k] }
        return p
    }

    /// Convenience: |X[k]|² of `samples` (power-of-two length) after an optional window.
    public static func realPowerSpectrum(_ samples: [Float], window: [Float]? = nil) -> [Double] {
        var x = samples
        if let window {
            precondition(window.count == x.count)
            for n in x.indices { x[n] *= window[n] }
        }
        return FFT(size: x.count).powerSpectrum(of: x)
    }

    /// Periodic Hann window, w[n] = 0.5·(1 − cos(2πn/N)). Its mean square is 0.375.
    public static func hann(_ n: Int) -> [Float] {
        (0..<n).map { Float(0.5 * (1 - cos(2 * Double.pi * Double($0) / Double(n)))) }
    }
}
