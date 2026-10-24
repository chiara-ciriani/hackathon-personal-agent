// Mode C: AVAudioEngine input tap, 48 kHz mono float. Same level meters as FOA, no DOA.
import AVFoundation
import QuietCore
import os

public final class MonoFeatureSource: FeatureSource, @unchecked Sendable {
    // @unchecked: `extractor`, `continuation` and stats are only touched on `queue`; `engine` is
    // started/stopped from start()/stop(), which the app calls serially.
    public let name = "Mono (AVAudioEngine)"
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "QuietCompass.MonoFeatureSource")
    private let classifier: SoundClassifier?
    private var extractor: LevelFeatureExtractor?
    private var continuation: AsyncStream<FeatureFrame>.Continuation?
    private var running = false
    public private(set) var sessionResult: AudioSessionConfigurator.Result?

    public init(classifier: SoundClassifier? = nil) {
        self.classifier = classifier
    }

    public func frames() -> AsyncStream<FeatureFrame> {
        let (stream, cont) = AsyncStream<FeatureFrame>.makeStream(bufferingPolicy: .bufferingNewest(32))
        queue.sync { continuation?.finish(); continuation = cont }
        return stream
    }

    public func start() async throws {
        guard !running else { return }
        sessionResult = try AudioSessionConfigurator.configure()
        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        // Tap in a mono float format at the hardware rate (the engine converts channels for us).
        // VERIFY: hardware rate is 48 kHz on iPhone 16 Pro with .measurement; if it is 44.1 kHz the
        // meters still work (they take sampleRate) but DeviceProfile.sampleRateHz must say so.
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hwFormat.sampleRate,
                                       channels: 1, interleaved: false) else {
            throw CocoaError(.featureUnsupported)
        }
        let sr = hwFormat.sampleRate
        queue.sync {
            extractor = LevelFeatureExtractor(sampleRate: sr, spectrum: VDSPPowerSpectrum())
        }
        input.installTap(onBus: 0, bufferSize: 4800, format: mono) { [weak self] buffer, when in
            guard let self, let ch = buffer.floatChannelData?[0] else { return }
            // Copy out of the tap immediately; all work happens on our serial queue.
            let samples = Array(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
            let t = Self.date(forHostTime: when.isHostTimeValid ? when.hostTime : mach_absolute_time())
            self.queue.async { self.process(samples, start: t, sampleRate: sr) }
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    public func stop() async {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        classifier?.stop()
        running = false
        queue.sync { continuation?.finish(); continuation = nil; extractor = nil }
    }

    private func process(_ samples: [Float], start: Date, sampleRate: Double) {
        samples.withUnsafeBufferPointer { buf in
            classifier?.feed(buf, sampleRate: sampleRate)
            guard var ex = extractor else { return }
            let seconds = ex.append(buf, startTime: start)
            extractor = ex
            for s in seconds {
                let snap = classifier?.takeSnapshot()
                continuation?.yield(s.featureFrame(speechShare: snap?.speech, classes: snap?.top ?? [], doa: nil))
            }
        }
    }

    /// Host time (mach ticks) to wall-clock Date.
    static func date(forHostTime hostTime: UInt64) -> Date {
        let now = mach_absolute_time()
        let delta = AVAudioTime.seconds(forHostTime: now) - AVAudioTime.seconds(forHostTime: hostTime)
        return Date().addingTimeInterval(-delta)
    }
}
