import Accelerate
import CoreAudioTypes
import simd

// Direction of arrival from FOA by pseudo-intensity:
//   I(k) = Re{ conj(W(k)) * [X(k), Y(k), Z(k)] }, summed over 200-4000 Hz bins.
// For a single plane wave every bin's I points at the source; diffuse sound or two
// sources make the per-bin vectors disagree, so |sum I| / sum |I| (0...1) is used as
// confidence. Overall gain of W (SN3D vs N3D vs FuMa's -3 dB) does not change the
// direction or the confidence, because it scales every component of I equally.
//
// Ambisonic axes (convention, not iPhone-specific): +X front, +Y left, +Z up.
// UNVERIFIED: where "front" is on an iPhone. See MountPreset and the README calibration.

/// Which input channel holds W, X, Y, Z.
nonisolated enum ChannelOrder: String, CaseIterable, Sendable {
    case auto, acn, fuma

    var label: String {
        switch self {
        case .auto: "Auto (from layout tag)"
        case .acn: "ACN / AmbiX: W Y Z X"
        case .fuma: "FuMa: W X Y Z"
        }
    }

    /// Channel indices of (W, X, Y, Z). Apple documents HOA_ACN_SN3D, i.e. ACN order,
    /// where ACN 0..3 = W, Y, Z, X. Auto only switches to FuMa if the layout tag says B-format.
    func indices(for tag: AudioChannelLayoutTag) -> (w: Int, x: Int, y: Int, z: Int) {
        let fuma = self == .fuma || (self == .auto && tag == kAudioChannelLayoutTag_Ambisonic_B_Format)
        return fuma ? (0, 1, 2, 3) : (0, 3, 1, 2)
    }
}

/// ASSUMPTION (unverified): how the FOA frame sits on the phone.
/// CoreMotion device axes: +x right edge, +y top edge, +z out of the screen.
nonisolated enum MountPreset: String, CaseIterable, Sendable {
    /// FOA front = where the rear camera looks, up = top edge (as when filming in portrait).
    case camera
    /// FOA front = top edge, up = out of the screen (phone lying flat like a compass).
    case topEdge

    var label: String {
        switch self {
        case .camera: "Rear camera"
        case .topEdge: "Top edge"
        }
    }

    func foaToDevice(_ v: SIMD3<Double>) -> SIMD3<Double> {
        switch self {
        case .camera: SIMD3(-v.y, v.z, -v.x)
        case .topEdge: SIMD3(-v.y, v.x, v.z)
        }
    }
}

nonisolated struct DOASettings: Equatable, Sendable {
    var order: ChannelOrder = .auto
    var mount: MountPreset = .camera
    // Calibration toggles, applied in the FOA frame before mapping to the device.
    var swapXY = false
    var negateX = false
    var negateY = false
}

nonisolated struct DOAEstimate: Sendable {
    var bearingWorld: Double   // degrees clockwise from reference north (magnetic if available)
    var elevation: Double      // degrees above the horizon, world frame
    var azimuthFOA: Double     // degrees CCW from FOA +X, after toggles, not motion-compensated
    var confidence: Double     // 0...1
}

nonisolated enum Geo {
    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    /// Compass bearing of a world vector. CoreMotion's xMagneticNorthZVertical frame is
    /// right-handed with +x north and +z up, so +y is west and east is -y.
    static func bearing(_ v: SIMD3<Double>) -> Double {
        (degrees(atan2(-v.y, v.x)) + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// Not thread-safe: call from a single queue (the audio capture queue).
nonisolated final class DOAEstimator {
    static let windowSize = 2048
    static let hop = 1024            // 50 % overlap
    var band: ClosedRange<Double> = 200...4000
    var smoothingSeconds = 0.5

    private let dft: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]
    private let zeros: [Float]
    private var fifo: [[Float]] = Array(repeating: [], count: 4)   // W, X, Y, Z
    private var world = SIMD3<Double>.zero
    private var foa = SIMD3<Double>.zero
    private var magnitude = 0.0
    private(set) var estimate: DOAEstimate?
    /// Per-window results from the last `process` call (unsmoothed), for the radar.
    private(set) var windows: [WindowObservation] = []

    init() throws {
        // Complex-to-complex with a zero imaginary part: simplest safe API, cost is negligible.
        dft = try vDSP.DiscreteFourierTransform(count: Self.windowSize, direction: .forward,
                                                transformType: .complexComplex, ofType: Float.self)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                             count: Self.windowSize, isHalfWindow: false)
        zeros = [Float](repeating: 0, count: Self.windowSize)
    }

    /// Feed one capture buffer. Returns the latest smoothed estimate (nil until the first window).
    func process(_ channels: [[Float]], sampleRate: Double, layoutTag: AudioChannelLayoutTag,
                 settings: DOASettings, attitude: Attitude) -> DOAEstimate? {
        let idx = settings.order.indices(for: layoutTag)
        let order = [idx.w, idx.x, idx.y, idx.z]
        windows.removeAll(keepingCapacity: true)
        guard sampleRate > 0, let highest = order.max(), channels.count > highest else { return estimate }

        for (slot, channel) in order.enumerated() { fifo[slot] += channels[channel] }
        while fifo[0].count >= Self.windowSize {
            analyzeWindow(sampleRate: sampleRate, settings: settings, attitude: attitude)
            for slot in 0..<4 { fifo[slot].removeFirst(Self.hop) }
        }
        return estimate
    }

    private func analyzeWindow(sampleRate: Double, settings: DOASettings, attitude: Attitude) {
        let spectra = fifo.map { samples in
            dft.transform(real: vDSP.multiply(Array(samples.prefix(Self.windowSize)), window), imaginary: zeros)
        }
        let binHz = sampleRate / Double(Self.windowSize)
        let lo = max(1, Int((band.lowerBound / binHz).rounded(.up)))
        let hi = min(Self.windowSize / 2 - 1, Int(band.upperBound / binHz))
        guard lo <= hi else { return }

        let (w, x, y, z) = (spectra[0], spectra[1], spectra[2], spectra[3])
        var sum = SIMD3<Double>.zero
        var sumOfMagnitudes = 0.0
        var wPower = 0.0
        for k in lo...hi {
            let wr = Double(w.real[k]), wi = Double(w.imaginary[k])
            wPower += wr * wr + wi * wi
            // Re{conj(W) * V} = Wr*Vr + Wi*Vi
            let i = SIMD3(wr * Double(x.real[k]) + wi * Double(x.imaginary[k]),
                          wr * Double(y.real[k]) + wi * Double(y.imaginary[k]),
                          wr * Double(z.real[k]) + wi * Double(z.imaginary[k]))
            sum += i
            sumOfMagnitudes += simd_length(i)
        }

        if settings.swapXY { sum = SIMD3(sum.y, sum.x, sum.z) }
        if settings.negateX { sum.x = -sum.x }
        if settings.negateY { sum.y = -sum.y }

        // Smooth in the world frame so turning the phone does not smear the average.
        let toWorld = attitude.toWorld(settings.mount.foaToDevice(sum))

        // Unsmoothed per-window observation. Band mean square of W from Parseval:
        // one-sided Σ|X|² · 2 / N², divided by the Hann window's mean square (0.375).
        let n = Double(Self.windowSize)
        if sumOfMagnitudes > 0 {
            windows.append(WindowObservation(
                bearing: Geo.bearing(toWorld),
                elevation: Geo.degrees(atan2(toWorld.z, hypot(toWorld.x, toWorld.y))),
                confidence: min(1, simd_length(sum) / sumOfMagnitudes),
                energy: 2 * wPower / (n * n * 0.375),
                duration: Double(Self.hop) / sampleRate))
        }
        let a = 1 - exp(-Double(Self.hop) / (sampleRate * smoothingSeconds))
        world += a * (toWorld - world)
        foa += a * (sum - foa)
        magnitude += a * (sumOfMagnitudes - magnitude)
        guard magnitude > 0 else { return }

        estimate = DOAEstimate(
            bearingWorld: Geo.bearing(world),
            elevation: Geo.degrees(atan2(world.z, hypot(world.x, world.y))),
            azimuthFOA: Geo.degrees(atan2(foa.y, foa.x)),
            confidence: min(1, simd_length(world) / magnitude)
        )
    }
}
