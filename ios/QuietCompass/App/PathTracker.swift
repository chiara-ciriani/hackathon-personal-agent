import ARKit
import QuietCore

final class PathTracker: NSObject, ARSessionDelegate, @unchecked Sendable {
    private let session = ARSession()
    private let queue = DispatchQueue(label: "QuietCompass.PathTracker")
    private var lastTimestamp = -Double.infinity // accessed only on delegate queue
    private let onPose: @MainActor @Sendable (PoseSample) -> Void
    private let onFailure: @MainActor @Sendable (String) -> Void

    init(onPose: @escaping @MainActor @Sendable (PoseSample) -> Void,
         onFailure: @escaping @MainActor @Sendable (String) -> Void) {
        self.onPose = onPose; self.onFailure = onFailure
        super.init()
        session.delegateQueue = queue; session.delegate = self
    }
    @MainActor func start() throws {
        guard ARWorldTrackingConfiguration.isSupported else { throw PhoneError.message("Path tracking requires a supported iPhone.") }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    @MainActor func stop() { session.pause() }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard frame.timestamp - lastTimestamp >= 0.5 else { return }
        lastTimestamp = frame.timestamp
        let tracking: TrackingState
        switch frame.camera.trackingState {
        case .normal: tracking = .normal
        case .limited: tracking = .limited
        case .notAvailable: tracking = .notAvailable
        }
        let transform = frame.camera.transform
        let pose = PoseSample(t: Date(), position: tracking == .normal ?
            Position(x: Double(transform.columns.3.x), z: Double(transform.columns.3.z)) : nil,
            headingRad: Heading.fromCameraZAxis(x: Double(transform.columns.2.x), z: Double(transform.columns.2.z)),
            tracking: tracking)
        Task { @MainActor in onPose(pose) }
    }
    func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in onFailure("Tracking was interrupted. Start a new recording to establish a new path.") }
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in onFailure("Path tracking failed. Start a new recording.") }
    }
}
