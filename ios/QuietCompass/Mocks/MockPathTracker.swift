// Simulator stand-in for PathTracker: a scripted walk around a 10 × 6 m rectangle at 0.8 m/s, starting at
// the origin facing world −Z, pausing 35 s at each corner so each corner can complete a 30 s measurement.
// Poses arrive at 2 Hz on the main actor, like PathTracker's.
import Foundation
import QuietCore

@MainActor
final class MockPathTracker: PathTracking {
    static let width = 10.0        // along +X
    static let depth = 6.0         // along −Z
    static let speed = 0.8         // m/s
    static let cornerPause = 35.0  // s

    private let onPose: @MainActor @Sendable (PoseSample) -> Void
    private var timer: Task<Void, Never>?
    private var startedAt = Date()

    init(onPose: @escaping @MainActor @Sendable (PoseSample) -> Void) {
        self.onPose = onPose
    }

    func start() throws {
        guard timer == nil else { return }
        startedAt = Date()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let now = Date()
        let (position, heading) = Self.pose(atElapsed: now.timeIntervalSince(startedAt))
        onPose(PoseSample(t: now, position: position, headingRad: heading, tracking: .normal))
    }

    static var corners: [Position] {
        [Position(x: 0, z: 0), Position(x: 0, z: -depth), Position(x: width, z: -depth), Position(x: width, z: 0)]
    }

    static var lapSeconds: Double { 2 * (width + depth) / speed + 4 * cornerPause }

    /// Position and heading at a time into the walk.
    static func pose(atElapsed t: Double) -> (Position, Double) {
        let pts = corners
        var remaining = t.truncatingRemainder(dividingBy: lapSeconds)
        for i in 0..<4 {
            let a = pts[i], b = pts[(i + 1) % 4]
            let heading = Heading.bearing(from: a, to: b)
            if remaining < cornerPause { return (a, heading) }
            remaining -= cornerPause
            let legTime = a.distance(to: b) / speed
            if remaining < legTime {
                let f = remaining / legTime
                return (Position(x: a.x + (b.x - a.x) * f, z: a.z + (b.z - a.z) * f), heading)
            }
            remaining -= legTime
        }
        return (pts[0], 0)
    }
}
