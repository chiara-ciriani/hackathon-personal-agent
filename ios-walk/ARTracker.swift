import Foundation
import simd
#if canImport(ARKit)
import ARKit
#endif

// Optional ARKit world tracking for Locate and Walk map: position (camera x/z) and, while it
// runs, the device orientation used to rotate DOA into the world (see ARFrameMath in
// SourceMap.swift). No rendering. Started only when Locate mode or a walk recording needs it,
// because ARKit runs the camera through its own capture session and may disturb the audio
// session (AudioCapture reports interruptions).
//
// Frame: worldAlignment = .gravityAndHeading, so +y is up, −z is TRUE north, +x is east, and
// the origin is where the session first started. CoreMotion's frame uses MAGNETIC north (about
// 13° apart in the Bay Area), so while ARKit runs the app uses ARKit's camera orientation for
// both the position and the DOA bearing; mixing the two would skew every bearing by the
// magnetic declination.

nonisolated enum ARTrackingKind: String, Sendable {
    case off, starting, normal, limited, notAvailable, failed, unsupported
}

nonisolated struct ARStatus: Sendable, Equatable {
    var kind: ARTrackingKind = .off
    var detail = "off"
    /// Raw ARKit world (x, z) in metres; set only while tracking is normal.
    var position: SIMD2<Double>?
    var lastNormalPosition: SIMD2<Double>?
    /// Phone bearing from ARKit (true north) minus CoreMotion's (magnetic north). Expect about
    /// the local declination (+13° in San Francisco); 90° or 180° means an axis mapping is wrong.
    var headingDifference: Double?

    var isNormal: Bool { kind == .normal }
}

nonisolated final class ARTracker: NSObject, @unchecked Sendable {
    typealias StatusHandler = @Sendable (ARStatus) -> Void
    /// Mean square of one mono mic buffer from ARKit (fallback level source for Walk map).
    typealias PowerHandler = @Sendable (Double) -> Void

    private let motion: MotionTracker
    private let onStatus: StatusHandler
    private let onPower: PowerHandler?
    private let queue = DispatchQueue(label: "quietcompass.arkit")
    // Touched only on `queue` (delegate callbacks) after start().
    private var status = ARStatus()
    private var lastPublish = 0.0
    #if canImport(ARKit)
    private var session: ARSession?
    #endif

    /// Pass `onPower` to let ARKit capture the microphone too (`providesAudioData`), for when the
    /// separate AVCaptureSession audio stops while ARKit runs. Mono only: no direction then.
    init(motion: MotionTracker, onPower: PowerHandler? = nil, onStatus: @escaping StatusHandler) {
        self.motion = motion
        self.onPower = onPower
        self.onStatus = onStatus
        super.init()
    }

    static var isSupported: Bool {
        #if canImport(ARKit)
        ARWorldTrackingConfiguration.isSupported
        #else
        false
        #endif
    }

    /// Call from the main thread. Resumes without resetting, so the origin stays put across
    /// pause/resume; pass `resetOrigin` to start a fresh coordinate system.
    func start(resetOrigin: Bool = false) {
        #if canImport(ARKit)
        guard ARWorldTrackingConfiguration.isSupported else {
            publish(ARStatus(kind: .unsupported, detail: "ARKit world tracking not supported"))
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        config.providesAudioData = onPower != nil   // normally leave the microphone to AudioCapture
        config.isLightEstimationEnabled = false
        config.planeDetection = []
        let session = self.session ?? ARSession()
        session.delegate = self
        session.delegateQueue = queue
        self.session = session
        session.run(config, options: resetOrigin ? [.resetTracking, .removeExistingAnchors] : [])
        publish(ARStatus(kind: .starting, detail: "starting ARKit…"))
        #else
        publish(ARStatus(kind: .unsupported, detail: "ARKit not available in this build"))
        #endif
    }

    func stop() {
        #if canImport(ARKit)
        session?.pause()
        #endif
        motion.setARAttitude(nil)
        publish(ARStatus(kind: .off, detail: "off"))
    }

    private func publish(_ s: ARStatus) {
        queue.async {
            var s = s
            s.lastNormalPosition = s.lastNormalPosition ?? self.status.lastNormalPosition
            self.status = s
            self.onStatus(s)
        }
    }
}

#if canImport(ARKit)
extension ARTracker: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let camera = frame.camera
        let t = camera.transform
        func d(_ c: SIMD4<Float>) -> SIMD3<Double> { SIMD3(Double(c.x), Double(c.y), Double(c.z)) }
        let attitude = Attitude(arDeviceAxes: ARFrameMath.deviceAxesNWU(cameraX: d(t.columns.0),
                                                                        cameraY: d(t.columns.1),
                                                                        cameraZ: d(t.columns.2)))
        // Orientation is usable even while position tracking is limited.
        let coreMotion = motion.coreMotion
        motion.setARAttitude(attitude)

        var s = status
        switch camera.trackingState {
        case .normal:
            s.kind = .normal
            s.detail = "tracking normal"
            let p = SIMD2(Double(t.columns.3.x), Double(t.columns.3.z))
            s.position = p
            s.lastNormalPosition = p
        case .limited(let reason):
            s.kind = .limited
            s.detail = "tracking limited (\(Self.describe(reason)))"
            s.position = nil
        case .notAvailable:
            s.kind = .notAvailable
            s.detail = "tracking not available"
            s.position = nil
        @unknown default:
            s.kind = .limited
            s.detail = "tracking state unknown"
            s.position = nil
        }
        let diff = attitude.phoneBearing - coreMotion.phoneBearing
        s.headingDifference = (diff + 540).truncatingRemainder(dividingBy: 360) - 180
        let kindChanged = s.kind != status.kind
        status = s
        // Position is published about twice a second (and at once when the state changes).
        let now = ProcessInfo.processInfo.systemUptime
        if kindChanged || now - lastPublish >= 0.5 {
            lastPublish = now
            onStatus(s)
        }
    }

    func session(_ session: ARSession, didOutputAudioSampleBuffer audioSampleBuffer: CMSampleBuffer) {
        guard let onPower, let asbd = audioSampleBuffer.formatDescription?.audioStreamBasicDescription,
              let channels = AudioCapture.channels(of: audioSampleBuffer, asbd: asbd), !channels.isEmpty
        else { return }
        onPower(pow(10, Double(LevelInfo(channels).rmsDB) / 10))
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        motion.setARAttitude(nil)
        var s = status
        s.kind = .failed
        s.detail = "ARKit failed: \(error.localizedDescription)"
        s.position = nil
        status = s
        onStatus(s)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        motion.setARAttitude(nil)
        var s = status
        s.kind = .limited
        s.detail = "ARKit interrupted"
        s.position = nil
        status = s
        onStatus(s)
    }

    private static func describe(_ reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .initializing: "initializing, move slowly"
        case .excessiveMotion: "moving too fast"
        case .insufficientFeatures: "too few features, point at a textured scene"
        case .relocalizing: "relocalizing"
        @unknown default: "unknown reason"
        }
    }
}
#endif
