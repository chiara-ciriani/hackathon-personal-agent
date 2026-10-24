// Optional on-device sound classification (SoundAnalysis built-in classifier). Last thing to cut.
import AVFoundation
import SoundAnalysis
import QuietCore
import os

public final class SoundClassifier: NSObject, SNResultsObserving, @unchecked Sendable {
    // @unchecked: mutable state is guarded by `lock`; the analyzer is only touched on `queue`.
    public struct Snapshot: Sendable { public var top: [SoundClass] = []; public var speech: Double? = nil }

    private struct State { var top: [SoundClass] = []; var speechSum = 0.0; var speechCount = 0 }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "QuietCompass.SoundClassifier")
    private var analyzer: SNAudioStreamAnalyzer?
    private var format: AVAudioFormat?
    private var framePosition: AVAudioFramePosition = 0

    public override init() { super.init() }

    /// Latest top-3 labels and the mean `speech` confidence since the last call (nil if no results yet).
    public func takeSnapshot() -> Snapshot {
        lock.withLock { s in
            let speech: Double? = s.speechCount > 0 ? s.speechSum / Double(s.speechCount) : nil
            s.speechSum = 0; s.speechCount = 0
            return Snapshot(top: s.top, speech: speech)
        }
    }

    /// Feed mono float (omni) audio. Copies the samples and analyzes on a private queue.
    public func feed(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) {
        guard !samples.isEmpty else { return }
        let copy = Array(samples)
        queue.async { [self] in
            if format?.sampleRate != sampleRate { setUp(sampleRate: sampleRate) }
            guard let format, let analyzer,
                  let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(copy.count)) else { return }
            buf.frameLength = AVAudioFrameCount(copy.count)
            copy.withUnsafeBufferPointer { src in
                buf.floatChannelData![0].update(from: src.baseAddress!, count: copy.count)
            }
            analyzer.analyze(buf, atAudioFramePosition: framePosition)
            framePosition += AVAudioFramePosition(copy.count)
        }
    }

    public func stop() {
        queue.async { [self] in
            analyzer?.completeAnalysis()
            analyzer = nil
            format = nil
        }
    }

    private func setUp(sampleRate: Double) {
        guard let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else { return }
        let a = SNAudioStreamAnalyzer(format: f)
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            // VERIFY: 1.5 s must lie inside request.windowDurationConstraint for .version1 on iOS 26.
            request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48_000)
            request.overlapFactor = 0.5
            try a.add(request, withObserver: self)
            analyzer = a
            format = f
            framePosition = 0
        } catch {
            Logger(subsystem: "QuietCompass", category: "SoundClassifier").error("classifier setup failed: \(error.localizedDescription)")
        }
    }

    // MARK: SNResultsObserving

    public func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        let top = r.classifications.prefix(3).map { SoundClass(label: $0.identifier, confidence: $0.confidence) }
        let speech = r.classification(forIdentifier: "speech")?.confidence ?? 0
        lock.withLock { s in
            s.top = top
            s.speechSum += speech
            s.speechCount += 1
        }
    }

    public func request(_ request: SNRequest, didFailWithError error: Error) {
        Logger(subsystem: "QuietCompass", category: "SoundClassifier").error("classifier failed: \(error.localizedDescription)")
    }
}
