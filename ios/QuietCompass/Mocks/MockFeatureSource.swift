// Simulator stand-in for audio capture. Synthesizes plausible 1 s feature frames that cycle through
// three scenes: quiet (−52 dBFS, steady), loud with speech (−28 dBFS, bursty, speech_share ≈ 0.8) and
// medium (−40 dBFS, some peaks). No fixture files and no microphone.
import Foundation
import QuietCore

final class MockFeatureSource: FeatureSource, @unchecked Sendable {
    // @unchecked: `continuation` and `task` are only touched while holding `lock`.
    let name = "Mock (synthesized frames)"

    struct Scene: Sendable {
        var label: String
        var baseDb: Double
        var jitterDb: Double
        var burstChance: Double
        var burstDb: Double
        var speech: Double
        var classes: [SoundClass]
    }

    static let scenes: [Scene] = [
        Scene(label: "quiet", baseDb: -52, jitterDb: 1.0, burstChance: 0.01, burstDb: 8, speech: 0.05,
              classes: [SoundClass(label: "silence", confidence: 0.6), SoundClass(label: "air_conditioner", confidence: 0.3)]),
        Scene(label: "loud with speech", baseDb: -28, jitterDb: 4.0, burstChance: 0.12, burstDb: 12, speech: 0.8,
              classes: [SoundClass(label: "speech", confidence: 0.8), SoundClass(label: "crowd", confidence: 0.55),
                        SoundClass(label: "laughter", confidence: 0.2)]),
        Scene(label: "medium", baseDb: -40, jitterDb: 2.5, burstChance: 0.05, burstDb: 10, speech: 0.35,
              classes: [SoundClass(label: "speech", confidence: 0.35), SoundClass(label: "music", confidence: 0.3)]),
    ]

    /// Seconds per scene. 40 s so each scene completes a 30 s dwell.
    let sceneSeconds: Int
    private let lock = NSLock()
    private var continuation: AsyncStream<FeatureFrame>.Continuation?
    private var task: Task<Void, Never>?

    init(sceneSeconds: Int = 40) {
        self.sceneSeconds = max(5, sceneSeconds)
    }

    func frames() -> AsyncStream<FeatureFrame> {
        let (stream, cont) = AsyncStream<FeatureFrame>.makeStream(bufferingPolicy: .bufferingNewest(32))
        lock.withLock {
            continuation?.finish()
            continuation = cont
        }
        return stream
    }

    func start() async throws {
        let sceneSeconds = self.sceneSeconds
        let newTask = Task.detached { [weak self] in
            var rng = SystemRandomNumberGenerator()
            var second = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let scene = Self.scenes[(second / sceneSeconds) % Self.scenes.count]
                let frame = Self.makeFrame(scene: scene, t: Date(), rng: &rng)
                self.lock.withLock { _ = self.continuation?.yield(frame) }
                second += 1
            }
        }
        lock.withLock {
            task?.cancel()
            task = newTask
        }
    }

    func stop() async {
        lock.withLock {
            task?.cancel()
            task = nil
            continuation?.finish()
            continuation = nil
        }
    }

    static func makeFrame<R: RandomNumberGenerator>(scene: Scene, t: Date, rng: inout R) -> FeatureFrame {
        var short: [Double] = []
        for _ in 0..<LevelMeter.framesPerSecond {
            var l = scene.baseDb + Double.random(in: -scene.jitterDb...scene.jitterDb, using: &rng)
            if Double.random(in: 0..<1, using: &rng) < scene.burstChance { l += scene.burstDb }
            short.append(min(-1, l))
        }
        let level = LevelMeter.secondLevelDb(frameLevelsDb: short)
        // A gently falling spectrum, louder overall in the speech scene around 500 Hz–2 kHz.
        let tilt: [Double] = [-4, -2, -3, -6, -10, -16]
        let speechLift: [Double] = [0, 2, 3, 2, 0, 0].map { $0 * scene.speech }
        let bands = zip(tilt, speechLift).map { min(0, level + $0 + $1 + Double.random(in: -1...1, using: &rng)) }
        let speech = min(1, max(0, scene.speech + Double.random(in: -0.1...0.1, using: &rng)))
        return FeatureFrame(t: t, levelDbfs: level, levelAwDbfs: min(0, level - 3), shortFrameLevelsDbfs: short,
                            bandsDb: bands, speechShare: speech, classes: scene.classes, doa: nil)
    }
}
