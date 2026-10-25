import CoreMotion
import os
import simd

/// Device attitude as the rows of CMAttitude.rotationMatrix, plus gravity (device frame, in g).
///
/// Convention used (common CoreMotion usage, not spelled out in Apple's docs):
/// v_device = R * v_reference, so v_reference = Rᵀ * v_device.
/// `gravityCheck` tests this on the device: it should read close to +1.
nonisolated struct Attitude: Sendable {
    var row1 = SIMD3<Double>(1, 0, 0)
    var row2 = SIMD3<Double>(0, 1, 0)
    var row3 = SIMD3<Double>(0, 0, 1)
    var gravity = SIMD3<Double>(0, 0, -1)

    init() {}

    init(_ motion: CMDeviceMotion) {
        let r = motion.attitude.rotationMatrix
        row1 = SIMD3(r.m11, r.m12, r.m13)
        row2 = SIMD3(r.m21, r.m22, r.m23)
        row3 = SIMD3(r.m31, r.m32, r.m33)
        gravity = SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z)
    }

    /// From ARKit (see ARFrameMath): world images of the device axes in the north/west/up frame.
    /// Gravity is derived from the same rotation, so gravityCheck reads exactly +1 here.
    init(arDeviceAxes axes: (x: SIMD3<Double>, y: SIMD3<Double>, z: SIMD3<Double>)) {
        row1 = axes.x
        row2 = axes.y
        row3 = axes.z
        gravity = -SIMD3(row1.z, row2.z, row3.z)
    }

    /// Rᵀ * v: device frame -> reference (world) frame.
    func toWorld(_ v: SIMD3<Double>) -> SIMD3<Double> {
        row1 * v.x + row2 * v.y + row3 * v.z
    }

    /// Cosine between measured gravity and the gravity predicted from R under our convention.
    var gravityCheck: Double {
        let predicted = -SIMD3(row1.z, row2.z, row3.z)   // R * (0, 0, -1)
        let g = simd_length(gravity)
        return g > 0 ? simd_dot(predicted, gravity) / g : 0
    }

    /// Bearing of what the user is "facing": the top edge when the phone lies flat,
    /// the rear camera when it is held up. The on-screen arrow is drawn relative to this.
    var phoneBearing: Double {
        let forward: SIMD3<Double> = abs(gravity.z) > 0.75 ? [0, 1, 0] : [0, 0, -1]
        return Geo.bearing(toWorld(forward))
    }
}

nonisolated enum ReferenceKind: Sendable {
    case magneticNorth, arbitrary, unavailable, arkitTrueNorth

    var label: String {
        switch self {
        case .magneticNorth: "magnetic north"
        case .arbitrary: "arbitrary heading (no north)"
        case .unavailable: "no motion (identity)"
        case .arkitTrueNorth: "true north (ARKit camera)"
        }
    }
}

nonisolated final class MotionTracker: @unchecked Sendable {
    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let latest = OSAllocatedUnfairLock(initialState: Attitude())

    /// ARKit attitude while Locate/Walk runs an AR session; ignored once older than 0.3 s,
    /// so the app falls back to CoreMotion by itself when ARKit stops delivering frames.
    private let arOverride = OSAllocatedUnfairLock<(attitude: Attitude, time: Double)?>(initialState: nil)

    /// Latest attitude; safe to read from any thread (the audio queue reads it per window).
    var current: Attitude { currentWithSource.attitude }

    /// The attitude plus whether it came from ARKit (true north) or CoreMotion (magnetic north).
    var currentWithSource: (attitude: Attitude, fromARKit: Bool) {
        if let o = arOverride.withLock({ $0 }), ProcessInfo.processInfo.systemUptime - o.time < 0.3 {
            return (o.attitude, true)
        }
        return (latest.withLock { $0 }, false)
    }

    /// CoreMotion's attitude regardless of ARKit (for the ARKit-vs-CoreMotion heading check).
    var coreMotion: Attitude { latest.withLock { $0 } }

    func setARAttitude(_ attitude: Attitude?) {
        let now = ProcessInfo.processInfo.systemUptime
        arOverride.withLock { $0 = attitude.map { ($0, now) } }
    }

    func stop() { manager.stopDeviceMotionUpdates(); setARAttitude(nil) }

    func start(onUpdate: @escaping @Sendable (Attitude) -> Void) -> ReferenceKind {
        guard manager.isDeviceMotionAvailable else { return .unavailable }
        let magnetic = CMMotionManager.availableAttitudeReferenceFrames().contains(.xMagneticNorthZVertical)
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.showsDeviceMovementDisplay = true   // lets iOS prompt for compass calibration
        manager.startDeviceMotionUpdates(using: magnetic ? .xMagneticNorthZVertical : .xArbitraryCorrectedZVertical,
                                         to: queue) { [latest] motion, _ in
            guard let motion else { return }
            let attitude = Attitude(motion)
            latest.withLock { $0 = attitude }
            onUpdate(attitude)
        }
        return magnetic ? .magneticNorth : .arbitrary
    }
}
