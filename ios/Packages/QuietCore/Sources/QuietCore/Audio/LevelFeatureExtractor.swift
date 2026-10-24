// Turns a stream of mono (omni) samples into one `SecondFeatures` per second: the eight 125 ms frame
// levels, the 1 s level (power mean), the A-weighted 1 s level and the octave bands. Shared by the FOA
// source (fed the W channel) and the mono source. Foundation only; call from one serial queue.
import Foundation

/// Level features of one second; the capture source adds classifier output and DOA to make a FeatureFrame.
public struct SecondFeatures: Sendable, Hashable {
    /// Time of the last sample of the second (host clock, as a Date).
    public var t: Date
    public var levelDbfs: Double
    public var levelAwDbfs: Double?
    public var shortFrameLevelsDbfs: [Double]
    public var bandsDb: [Double]?

    public func featureFrame(speechShare: Double?, classes: [SoundClass], doa: DirectionEstimate?) -> FeatureFrame {
        FeatureFrame(t: t, levelDbfs: levelDbfs, levelAwDbfs: levelAwDbfs, shortFrameLevelsDbfs: shortFrameLevelsDbfs,
                     bandsDb: bandsDb, speechShare: speechShare, classes: classes, doa: doa)
    }
}

public struct LevelFeatureExtractor: Sendable {
    public let sampleRate: Double
    public let samplesPerFrame: Int
    private var aWeighting: BiquadCascade?
    private var bands: OctaveBandAnalyzer?

    private var frameSum = 0.0
    private var frameSumAw = 0.0
    private var frameFill = 0
    private var frameLevels: [Double] = []
    private var frameLevelsAw: [Double] = []

    public init(sampleRate: Double = 48_000, aWeighting: Bool = true, octaveBands: Bool = true,
                spectrum: any PowerSpectrumComputing = FFT(size: OctaveBands.fftSize)) {
        self.sampleRate = sampleRate
        samplesPerFrame = Int((sampleRate * LevelMeter.frameDuration).rounded())
        self.aWeighting = aWeighting ? BiquadCascade.aWeighting(sampleRate: sampleRate) : nil
        self.bands = octaveBands ? OctaveBandAnalyzer(sampleRate: sampleRate, spectrum: spectrum) : nil
        frameLevels.reserveCapacity(LevelMeter.framesPerSecond)
        frameLevelsAw.reserveCapacity(LevelMeter.framesPerSecond)
    }

    /// Feeds samples whose first sample was captured at `startTime`. Returns any seconds completed.
    public mutating func append(_ samples: UnsafeBufferPointer<Float>, startTime: Date) -> [SecondFeatures] {
        var out: [SecondFeatures] = []
        var i = 0
        let n = samples.count
        while i < n {
            let take = min(samplesPerFrame - frameFill, n - i)
            let seg = UnsafeBufferPointer(rebasing: samples[i..<(i + take)])
            for s in seg {
                let d = Double(s)
                frameSum += d * d
                if let a = aWeighting?.process(d) { frameSumAw += a * a }
            }
            bands?.append(seg)
            frameFill += take
            i += take
            if frameFill == samplesPerFrame {
                frameLevels.append(LevelMeter.db(power: frameSum / Double(samplesPerFrame)))
                frameLevelsAw.append(LevelMeter.db(power: frameSumAw / Double(samplesPerFrame)))
                frameSum = 0; frameSumAw = 0; frameFill = 0
                if frameLevels.count == LevelMeter.framesPerSecond {
                    let t = startTime.addingTimeInterval(Double(i) / sampleRate)
                    out.append(SecondFeatures(
                        t: t,
                        levelDbfs: LevelMeter.secondLevelDb(frameLevelsDb: frameLevels),
                        levelAwDbfs: aWeighting == nil ? nil : LevelMeter.secondLevelDb(frameLevelsDb: frameLevelsAw),
                        shortFrameLevelsDbfs: frameLevels,
                        bandsDb: bands?.takeBandsDb()))
                    frameLevels.removeAll(keepingCapacity: true)
                    frameLevelsAw.removeAll(keepingCapacity: true)
                }
            }
        }
        return out
    }

    public mutating func append(_ samples: [Float], startTime: Date) -> [SecondFeatures] {
        samples.withUnsafeBufferPointer { append($0, startTime: startTime) }
    }

    public mutating func reset() {
        frameSum = 0; frameSumAw = 0; frameFill = 0
        frameLevels.removeAll(keepingCapacity: true)
        frameLevelsAw.removeAll(keepingCapacity: true)
        aWeighting?.reset()
        bands?.reset()
    }
}
