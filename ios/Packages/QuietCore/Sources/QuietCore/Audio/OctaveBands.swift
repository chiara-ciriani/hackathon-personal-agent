// Octave band levels (250 Hz … 8 kHz) from a 2048-point Hann power spectrum. Foundation only.
import Foundation

public enum OctaveBands {
    /// Nominal centre frequencies, in the order used by `Observation.bandsDb`.
    public static let centres: [Double] = [250, 500, 1000, 2000, 4000, 8000]
    public static let fftSize = 2048

    /// Band edges fc·2^(±1/2).
    public static func edges(centre fc: Double) -> (lo: Double, hi: Double) {
        (fc / 2.0.squareRoot(), fc * 2.0.squareRoot())
    }

    /// Band powers (mean-square units of the *unwindowed* signal) from a one-sided power spectrum
    /// |X[k]|², k = 0…N/2, of a frame windowed with `window`.
    ///
    /// Normalization: by Parseval, mean(x_w²) = (1/N²)·Σ_{all k}|X[k]|². The one-sided sum doubles bins
    /// 1…N/2−1. Dividing by the window's mean square (0.375 for Hann) gives the mean square of the
    /// unwindowed signal, so a band holding a full-scale sine reads about −3 dB, the same as its
    /// broadband level. Bins with k·fs/N in [lo, hi) belong to a band.
    public static func bandPowers(powerSpectrum p: [Double], fftSize n: Int, sampleRate fs: Double,
                                  windowMeanSquare: Double = 0.375) -> [Double] {
        let scale = 1.0 / (Double(n) * Double(n) * windowMeanSquare)
        let binHz = fs / Double(n)
        return centres.map { fc in
            let (lo, hi) = edges(centre: fc)
            let k0 = max(1, Int((lo / binHz).rounded(.up)))
            let k1 = min(p.count - 1, Int((hi / binHz).rounded(.up)) - 1)
            guard k0 <= k1 else { return 0 }
            var acc = 0.0
            for k in k0...k1 { acc += (k == n / 2 ? 1 : 2) * p[k] }
            return acc * scale
        }
    }

    public static func bandLevelsDb(powerSpectrum p: [Double], fftSize n: Int, sampleRate fs: Double,
                                    windowMeanSquare: Double = 0.375) -> [Double] {
        bandPowers(powerSpectrum: p, fftSize: n, sampleRate: fs, windowMeanSquare: windowMeanSquare)
            .map { LevelMeter.db(power: $0) }
    }
}

/// Streaming octave-band analyzer: feed samples in any chunk size; read the per-band power mean of all
/// completed 2048-point frames (50 % overlap by default) with `takeBandsDb()`, usually once per second.
public struct OctaveBandAnalyzer: Sendable {
    public let sampleRate: Double
    public let hop: Int
    private let spectrum: any PowerSpectrumComputing
    private let window: [Float]
    private let windowMeanSquare: Double
    private var pending: [Float] = []
    private var accumulated = [Double](repeating: 0, count: OctaveBands.centres.count)
    private var frameCount = 0

    public init(sampleRate: Double = 48_000, spectrum: any PowerSpectrumComputing = FFT(size: OctaveBands.fftSize),
                hop: Int? = nil) {
        self.sampleRate = sampleRate
        self.spectrum = spectrum
        self.hop = hop ?? spectrum.size / 2
        window = FFT.hann(spectrum.size)
        var ms = 0.0
        for w in window { ms += Double(w) * Double(w) }
        windowMeanSquare = ms / Double(spectrum.size)
        pending.reserveCapacity(spectrum.size * 2)
    }

    public mutating func append(_ samples: UnsafeBufferPointer<Float>) {
        pending.append(contentsOf: samples)
        let n = spectrum.size
        var start = 0
        while pending.count - start >= n {
            var frame = [Float](repeating: 0, count: n)
            for i in 0..<n { frame[i] = pending[start + i] * window[i] }
            let p = spectrum.powerSpectrum(of: frame)
            let bands = OctaveBands.bandPowers(powerSpectrum: p, fftSize: n, sampleRate: sampleRate,
                                               windowMeanSquare: windowMeanSquare)
            for b in bands.indices { accumulated[b] += bands[b] }
            frameCount += 1
            start += hop
        }
        if start > 0 { pending.removeFirst(min(start, pending.count)) }
    }

    public mutating func append(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { append($0) }
    }

    /// Power mean per band (dB) of the frames completed since the last call; nil if none completed.
    public mutating func takeBandsDb() -> [Double]? {
        guard frameCount > 0 else { return nil }
        let out = accumulated.map { LevelMeter.db(power: $0 / Double(frameCount)) }
        for i in accumulated.indices { accumulated[i] = 0 }
        frameCount = 0
        return out
    }

    public mutating func reset() {
        pending.removeAll(keepingCapacity: true)
        for i in accumulated.indices { accumulated[i] = 0 }
        frameCount = 0
    }
}
