import XCTest
@testable import QuietCore

final class AudioLevelTests: XCTestCase {
    func testFrameLevelOfFullScaleSineIsMinus3dB() {
        let s = TestSignals.sine(frequency: 1000, amplitude: 1, count: 6000)
        XCTAssertEqual(LevelMeter.frameLevelDb(s), -3.0103, accuracy: 0.01)
    }

    func testSilenceHitsFloor() {
        XCTAssertEqual(LevelMeter.frameLevelDb([Float](repeating: 0, count: 6000)), -120, accuracy: 1e-9)
    }

    func testPowerMeanIsNotDbMean() {
        // One loud frame at −10 dB and seven at −60 dB: power mean ≈ −19 dB, dB mean would be −53.75 dB.
        let levels = [-10.0] + [Double](repeating: -60, count: 7)
        let l = LevelMeter.secondLevelDb(frameLevelsDb: levels)
        let expected = 10 * log10((pow(10, -1.0) + 7 * pow(10, -6.0)) / 8)
        XCTAssertEqual(l, expected, accuracy: 1e-9)
        XCTAssertEqual(l, -19.03, accuracy: 0.01)
    }

    func testPowerMeanOfEqualLevelsIsThatLevel() {
        XCTAssertEqual(LevelMeter.powerMeanDb([-42, -42, -42])!, -42, accuracy: 1e-9)
        XCTAssertNil(LevelMeter.powerMeanDb([]))
    }

    func testExtractorEmitsOneSecondWithEightFrames() {
        var ex = LevelFeatureExtractor(sampleRate: 48_000)
        let s = TestSignals.sine(frequency: 1000, amplitude: 0.1, count: 48_000 * 2 + 100)
        let t0 = Date(timeIntervalSince1970: 1000)
        // Feed in odd chunk sizes to exercise frame boundaries.
        var out: [SecondFeatures] = []
        var i = 0
        while i < s.count {
            let n = min(1013, s.count - i)
            out += ex.append(Array(s[i..<(i + n)]), startTime: t0.addingTimeInterval(Double(i) / 48_000))
            i += n
        }
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].shortFrameLevelsDbfs.count, 8)
        XCTAssertEqual(out[0].t.timeIntervalSince(t0), 1.0, accuracy: 1e-6)
        XCTAssertEqual(out[1].t.timeIntervalSince(t0), 2.0, accuracy: 1e-6)
        XCTAssertEqual(out[1].levelDbfs, -23.01, accuracy: 0.05)              // 0.1 amplitude sine
        XCTAssertEqual(out[1].levelAwDbfs!, -23.01, accuracy: 0.2)            // A-weighting ≈ 0 dB at 1 kHz
        let bands = out[1].bandsDb!
        XCTAssertEqual(bands.count, 6)
        XCTAssertEqual(bands[2], -23.01, accuracy: 0.5)                       // all energy in the 1 kHz band
        XCTAssertLessThan(bands[0], -60)
        XCTAssertLessThan(bands[5], -60)
    }
}

final class AudioAWeightingTests: XCTestCase {
    func testResponseAtReferenceFrequencies() {
        XCTAssertEqual(AWeighting.responseDb(at: 1000), 0, accuracy: 0.01)
        XCTAssertEqual(AWeighting.responseDb(at: 100), -19.1, accuracy: 1.0)
        XCTAssertEqual(AWeighting.responseDb(at: 4000), 1.0, accuracy: 1.0)
        XCTAssertEqual(AWeighting.responseDb(at: 8000), -1.1, accuracy: 1.0)
        XCTAssertEqual(AWeighting.responseDb(at: 250), -8.6, accuracy: 1.0)
    }

    /// Runs real sines through the stateful filter and compares levels in and out.
    func testFilterGainOnSines() {
        func gainDb(_ f: Double) -> Double {
            var filter = BiquadCascade.aWeighting()
            let x = TestSignals.sine(frequency: f, amplitude: 0.5, count: 48_000)
            let y = filter.processed(x)
            // Skip the first 0.5 s (filter settling, the 20 Hz poles are slow).
            let xin = Array(x[24_000...]), yout = Array(y[24_000...])
            return LevelMeter.frameLevelDb(yout) - LevelMeter.frameLevelDb(xin)
        }
        XCTAssertEqual(gainDb(1000), 0, accuracy: 1)
        XCTAssertEqual(gainDb(100), -19, accuracy: 1)
        // IEC 61672 A-weighting is +1.0 dB at 4 kHz (this design gives +0.9 dB).
        XCTAssertEqual(gainDb(4000), 1.0, accuracy: 1)
    }
}

final class AudioOctaveBandTests: XCTestCase {
    func testFFTMatchesNaiveDFT() {
        var rng = TestNoise(seed: 7)
        let x = rng.samples(64, amplitude: 1)
        let p = FFT.realPowerSpectrum(x)
        for k in [0, 1, 5, 17, 32] {
            var re = 0.0, im = 0.0
            for n in 0..<64 {
                let a = -2 * Double.pi * Double(k * n) / 64
                re += Double(x[n]) * cos(a); im += Double(x[n]) * sin(a)
            }
            XCTAssertEqual(p[k], re * re + im * im, accuracy: 1e-6)
        }
    }

    func testSineLandsInItsBandWithCorrectLevel() {
        let n = OctaveBands.fftSize
        for (b, f) in OctaveBands.centres.enumerated() {
            let s = TestSignals.sine(frequency: f, amplitude: 1, count: n)
            let p = FFT.realPowerSpectrum(s, window: FFT.hann(n))
            let levels = OctaveBands.bandLevelsDb(powerSpectrum: p, fftSize: n, sampleRate: 48_000)
            XCTAssertEqual(levels[b], -3.01, accuracy: 0.5, "band \(f)")
            for (o, l) in levels.enumerated() where abs(o - b) >= 2 {
                XCTAssertLessThan(l, -40, "leak from \(f) into band \(OctaveBands.centres[o])")
            }
        }
    }

    func testWhiteNoiseBandsRiseThreeDbPerOctave() {
        var rng = TestNoise(seed: 3)
        var an = OctaveBandAnalyzer()
        an.append(rng.samples(48_000, amplitude: 1))
        let bands = an.takeBandsDb()!
        for i in 1..<bands.count {
            XCTAssertEqual(bands[i] - bands[i - 1], 3.01, accuracy: 1.0)
        }
        XCTAssertNil(an.takeBandsDb())
    }
}

final class AudioRollingStatsTests: XCTestCase {
    func testSpreadOfConstantIsZero() {
        var s = RollingStats()
        s.append(contentsOf: [Double](repeating: -40, count: 400))
        XCTAssertEqual(s.spreadDb, 0, accuracy: 1e-9)
        XCTAssertEqual(s.peaksPerMinute, 0)
    }

    func testSpreadUsesOnlyLast30Seconds() {
        var s = RollingStats()
        // 30 s alternating −40/−60 then 30 s constant −50: spread should be 0 afterwards.
        for i in 0..<240 { s.append(i % 2 == 0 ? -40 : -60) }
        XCTAssertEqual(s.spreadDb, 20, accuracy: 1e-9)
        for _ in 0..<240 { s.append(-50) }
        XCTAssertEqual(s.spreadDb, 0, accuracy: 1e-9)
    }

    func testSpreadOfRampIsL10MinusL90() {
        var s = RollingStats()
        for i in 0..<240 { s.append(Double(i) * 0.1) }   // 0 … 23.9 dB
        // percentiles: 0.9·239·0.1 and 0.1·239·0.1
        XCTAssertEqual(s.spreadDb, 0.8 * 23.9, accuracy: 1e-9)
    }

    func testPeaksCountOnsetsNotFrames() {
        var s = RollingStats()
        // 60 s at −50 dB with a 1 s event (8 frames at −30 dB) every 10 s: six onsets per minute.
        for i in 0..<480 {
            let inEvent = (i % 80) >= 40 && (i % 80) < 48
            s.append(inEvent ? -30 : -50)
        }
        XCTAssertEqual(s.peaksPerMinute, 6, accuracy: 1e-9)
    }

    func testPeaksBelowThresholdAreIgnored() {
        var s = RollingStats()
        for i in 0..<480 { s.append(i % 40 == 0 ? -42 : -50) }   // only +8 dB
        XCTAssertEqual(s.peaksPerMinute, 0)
    }

    func testPeaksAgeOut() {
        var s = RollingStats()
        for i in 0..<480 { s.append(i % 80 == 40 ? -20 : -50) }
        XCTAssertEqual(s.peaksPerMinute, 6, accuracy: 1e-9)
        for _ in 0..<480 { s.append(-50) }
        XCTAssertEqual(s.peaksPerMinute, 0)
    }
}
