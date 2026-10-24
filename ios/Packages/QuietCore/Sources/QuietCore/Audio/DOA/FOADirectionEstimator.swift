// FOA direction of arrival by pseudo-intensity, pure Swift (Foundation only).
//
// Pipeline (per 0.5 s block, ~47 STFT frames):
//   1. Input: SN3D first-order ambisonics in ACN order (W, Y, Z, X) -> reordered to W, X, Y, Z.
//      The axis calibration matrix is applied to [X, Y, Z] in the time domain (it is linear, so this is
//      the same as applying it to the spectra).
//   2. STFT, 1024-point periodic Hann, hop 512 at 48 kHz. Keep bins 500 Hz–4 kHz, grouped into ten
//      third-octave bands (centres 500 … 4000 Hz, edges fc·2^(±1/6), clipped to 500–4000 Hz).
//   3. Per bin: pseudo-intensity I = Re{conj(W)·[X, Y, Z]}, energy E = ½(|W|² + |X|² + |Y|² + |Z|²).
//      For an SN3D plane wave ‖I‖ = E exactly; for an ideal diffuse field ⟨I⟩ → 0.
//   4. Frame gating ("onset"): the frame's total in-range energy rises more than `onsetRiseDb` (6 dB) over
//      the frame `onsetLagFrames` earlier (2 = the previous non-overlapping frame; with 50 % overlap the
//      immediately previous frame already contains half of the onset). The gate stays open for
//      `onsetHoldFrames` more frames. Onsets favour the direct sound over reverberation (precedence effect).
//      `requireOnset = false` disables the gate (use it for calibration with a steady tone).
//   5. Diffuseness per band per block: ψ_b = 1 − ‖Σ I‖ / Σ E over all in-band bins of gated frames.
//   6. Bin selection for the direction: gated frames AND a direct-path-dominance proxy ‖I‖/E ≥ `binDirectness`
//      (0.8). A band with no selected bins abstains.
//   7. Band direction u_b = normalize(Σ I over selected bins). Bands are combined with weights
//      w_b = E_b(selected) · (1 − ψ_b). Combined directness (1 − ψ) is the w-weighted mean of (1 − ψ_b).
//      Circular spread across bands (horizontal plane): R = ‖Σ w_b·h_b‖ / Σ w_b·‖h_b‖,
//      spread = √(−2 ln R) in degrees (circular standard deviation).
//   8. Abstain when fewer than `minimumBands` bands survive, (1 − ψ) < `minimumDirectness` (0.3), or
//      spread > `maximumSpreadDeg` (45°). Otherwise emit a device-frame DirectionEstimate with
//      confidence = 1 − ψ.
// Reference: pseudo-intensity DOA as in Jarrett, Habets & Naylor, "3D source localization in the spherical
// harmonic domain using a pseudointensity vector" (EUSIPCO 2010), and DirAC diffuseness (Pulkki 2007).
import Foundation

public struct FOADirectionConfiguration: Sendable, Hashable {
    public var sampleRate: Double = 48_000
    public var fftSize = 1024
    public var hop = 512
    public var minimumFrequency: Double = 500
    public var maximumFrequency: Double = 4000
    public var bandCentres: [Double] = [500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000]
    public var blockSeconds: Double = 0.5
    public var requireOnset = true
    public var onsetRiseDb: Double = 6
    public var onsetLagFrames = 2
    public var onsetHoldFrames = 2
    public var binDirectness: Double = 0.8
    public var minimumBands = 2
    public var minimumDirectness: Double = 0.3
    public var maximumSpreadDeg: Double = 45
    /// Frames whose in-range energy is below this (linear, spectrum units) are ignored entirely (digital silence).
    public var energyFloor: Double = 1e-10
    public init() {}
}

/// Result of one analysis block, including diagnostics for the bench and the calibration flow.
public struct FOADirectionBlock: Sendable, Hashable {
    public enum Abstention: String, Sendable, Hashable {
        case noOnset = "no onset frames"
        case tooFewBands = "too few directional bands"
        case diffuse = "too diffuse"
        case spread = "bands disagree"
    }
    /// End of the block, seconds since the estimator started (sample clock).
    public var endTime: Double
    public var estimate: DirectionEstimate?
    public var abstention: Abstention?
    /// Σ I over selected bins after calibration, in the device ambisonic frame. Use it for calibration.
    public var intensity: Vector3
    public var directness: Double
    public var spreadDeg: Double
    public var bandsUsed: Int
    public var gatedFrames: Int
}

public struct FOADirectionEstimator: Sendable {
    public let configuration: FOADirectionConfiguration
    public var calibration: FOAAxisCalibration

    private let fft: FFT
    private let window: [Double]
    /// For each kept bin: (bin index, band index).
    private let bins: [(k: Int, band: Int)]
    private let bandCount: Int
    private let framesPerBlock: Int

    // Sample FIFO, W X Y Z (calibrated).
    private var fifo: [[Float]] = [[], [], [], []]
    private var samplesConsumed = 0

    // Onset state.
    private var energyHistory: [Double] = []
    private var holdRemaining = 0

    // Block accumulators.
    private var frameInBlock = 0
    private var gatedFrames = 0
    private var allI: [Vector3]
    private var allE: [Double]
    private var selI: [Vector3]
    private var selE: [Double]
    private var selCount: [Int]

    public init(configuration: FOADirectionConfiguration = .init(), calibration: FOAAxisCalibration = .identity) {
        self.configuration = configuration
        self.calibration = calibration
        fft = FFT(size: configuration.fftSize)
        window = FFT.hann(configuration.fftSize).map { Double($0) }
        let binHz = configuration.sampleRate / Double(configuration.fftSize)
        var b: [(k: Int, band: Int)] = []
        for k in 1..<(configuration.fftSize / 2) {
            let f = Double(k) * binHz
            guard f >= configuration.minimumFrequency, f <= configuration.maximumFrequency else { continue }
            for (i, c) in configuration.bandCentres.enumerated() {
                if f >= c * pow(2, -1.0 / 6) && f < c * pow(2, 1.0 / 6) { b.append((k: k, band: i)); break }
            }
        }
        bins = b
        bandCount = configuration.bandCentres.count
        framesPerBlock = max(1, Int((configuration.blockSeconds * configuration.sampleRate / Double(configuration.hop)).rounded()))
        allI = Array(repeating: .zero, count: bandCount)
        allE = Array(repeating: 0, count: bandCount)
        selI = Array(repeating: .zero, count: bandCount)
        selE = Array(repeating: 0, count: bandCount)
        selCount = Array(repeating: 0, count: bandCount)
    }

    /// Feeds four channels in ACN order (W, Y, Z, X), equal lengths. Returns completed blocks.
    public mutating func append(acn channels: [UnsafeBufferPointer<Float>]) -> [FOADirectionBlock] {
        precondition(channels.count == 4)
        let wxyz = FOAChannelOrder.acnToWXYZ(channels)
        return append(w: wxyz[0], x: wxyz[1], y: wxyz[2], z: wxyz[3])
    }

    public mutating func append(acn channels: [[Float]]) -> [FOADirectionBlock] {
        precondition(channels.count == 4)
        return channels[0].withUnsafeBufferPointer { c0 in
            channels[1].withUnsafeBufferPointer { c1 in
                channels[2].withUnsafeBufferPointer { c2 in
                    channels[3].withUnsafeBufferPointer { c3 in
                        append(acn: [c0, c1, c2, c3])
                    }
                }
            }
        }
    }

    /// Feeds four channels already in W, X, Y, Z order.
    public mutating func append(w: UnsafeBufferPointer<Float>, x: UnsafeBufferPointer<Float>,
                                y: UnsafeBufferPointer<Float>, z: UnsafeBufferPointer<Float>) -> [FOADirectionBlock] {
        let n = min(w.count, x.count, y.count, z.count)
        let m = calibration.matrix.m, g = calibration.directionalGain
        fifo[0].append(contentsOf: w[0..<n])
        fifo[1].reserveCapacity(fifo[1].count + n)
        fifo[2].reserveCapacity(fifo[2].count + n)
        fifo[3].reserveCapacity(fifo[3].count + n)
        for i in 0..<n {
            let vx = Double(x[i]), vy = Double(y[i]), vz = Double(z[i])
            fifo[1].append(Float(g * (m[0] * vx + m[1] * vy + m[2] * vz)))
            fifo[2].append(Float(g * (m[3] * vx + m[4] * vy + m[5] * vz)))
            fifo[3].append(Float(g * (m[6] * vx + m[7] * vy + m[8] * vz)))
        }
        var out: [FOADirectionBlock] = []
        let size = configuration.fftSize, hop = configuration.hop
        var start = 0
        while fifo[0].count - start >= size {
            if let block = analyzeFrame(at: start) { out.append(block) }
            start += hop
        }
        if start > 0 {
            for c in 0..<4 { fifo[c].removeFirst(start) }
            samplesConsumed += start
        }
        return out
    }

    public mutating func reset() {
        for c in 0..<4 { fifo[c].removeAll(keepingCapacity: true) }
        samplesConsumed = 0
        energyHistory.removeAll()
        holdRemaining = 0
        clearBlock()
    }

    // MARK: - Analysis

    private mutating func analyzeFrame(at start: Int) -> FOADirectionBlock? {
        let size = configuration.fftSize
        var spectra: [(re: [Double], im: [Double])] = []
        spectra.reserveCapacity(4)
        for c in 0..<4 {
            var re = [Double](repeating: 0, count: size)
            var im = [Double](repeating: 0, count: size)
            fifo[c].withUnsafeBufferPointer { buf in
                for i in 0..<size { re[i] = Double(buf[start + i]) * window[i] }
            }
            fft.transform(re: &re, im: &im)
            spectra.append((re: re, im: im))
        }

        // Per-bin intensity and energy.
        var binI = [Vector3](repeating: .zero, count: bins.count)
        var binE = [Double](repeating: 0, count: bins.count)
        var frameEnergy = 0.0
        for (j, b) in bins.enumerated() {
            let k = b.k
            let wr = spectra[0].re[k], wi = spectra[0].im[k]
            let xr = spectra[1].re[k], xi = spectra[1].im[k]
            let yr = spectra[2].re[k], yi = spectra[2].im[k]
            let zr = spectra[3].re[k], zi = spectra[3].im[k]
            // Re{conj(W)·V} = wr·vr + wi·vi
            binI[j] = Vector3(wr * xr + wi * xi, wr * yr + wi * yi, wr * zr + wi * zi)
            let e = 0.5 * (wr * wr + wi * wi + xr * xr + xi * xi + yr * yr + yi * yi + zr * zr + zi * zi)
            binE[j] = e
            frameEnergy += e
        }

        // Onset gate.
        var gated: Bool
        if !configuration.requireOnset {
            gated = true
        } else {
            let lag = max(1, configuration.onsetLagFrames)
            if energyHistory.count >= lag {
                let ref = energyHistory[energyHistory.count - lag]
                if frameEnergy > ref * pow(10, configuration.onsetRiseDb / 10) && frameEnergy > configuration.energyFloor {
                    holdRemaining = configuration.onsetHoldFrames + 1
                }
            }
            gated = holdRemaining > 0
            if holdRemaining > 0 { holdRemaining -= 1 }
            energyHistory.append(frameEnergy)
            if energyHistory.count > lag { energyHistory.removeFirst(energyHistory.count - lag) }
        }
        if frameEnergy <= configuration.energyFloor { gated = false }

        if gated {
            gatedFrames += 1
            for (j, b) in bins.enumerated() {
                allI[b.band] += binI[j]
                allE[b.band] += binE[j]
                let e = binE[j]
                if e > 0 && binI[j].norm / e >= configuration.binDirectness {
                    selI[b.band] += binI[j]
                    selE[b.band] += e
                    selCount[b.band] += 1
                }
            }
        }

        frameInBlock += 1
        guard frameInBlock >= framesPerBlock else { return nil }
        let endSample = samplesConsumed + start + size
        let block = finishBlock(endTime: Double(endSample) / configuration.sampleRate)
        clearBlock()
        return block
    }

    private func finishBlock(endTime: Double) -> FOADirectionBlock {
        var weights = [Double](repeating: 0, count: bandCount)
        var directness = [Double](repeating: 0, count: bandCount)
        var used: [Int] = []
        for b in 0..<bandCount where selCount[b] > 0 && allE[b] > 0 {
            let d = min(1, max(0, allI[b].norm / allE[b]))   // 1 − ψ_b
            directness[b] = d
            weights[b] = selE[b] * d
            if weights[b] > 0 { used.append(b) }
        }

        var total = Vector3.zero
        for b in used { total += selI[b] }

        func block(_ estimate: DirectionEstimate?, _ why: FOADirectionBlock.Abstention?, _ d: Double, _ s: Double) -> FOADirectionBlock {
            FOADirectionBlock(endTime: endTime, estimate: estimate, abstention: why, intensity: total,
                              directness: d, spreadDeg: s, bandsUsed: used.count, gatedFrames: gatedFrames)
        }

        if gatedFrames == 0 { return block(nil, .noOnset, 0, 0) }
        if used.count < max(1, configuration.minimumBands) { return block(nil, .tooFewBands, 0, 0) }

        let wSum = used.reduce(0.0) { $0 + weights[$1] }
        let combinedDirectness = used.reduce(0.0) { $0 + weights[$1] * directness[$1] } / wSum
        var v = Vector3.zero
        var hSum = (x: 0.0, y: 0.0), hNorm = 0.0
        for b in used {
            let u = selI[b].normalized
            v += u * weights[b]
            hSum.x += weights[b] * u.x; hSum.y += weights[b] * u.y
            hNorm += weights[b] * (u.x * u.x + u.y * u.y).squareRoot()
        }
        let r = hNorm > 0 ? (hSum.x * hSum.x + hSum.y * hSum.y).squareRoot() / hNorm : 0
        let spread = sqrt(max(0, -2 * log(min(1, max(r, 1e-12))))) * 180 / .pi

        if combinedDirectness < configuration.minimumDirectness { return block(nil, .diffuse, combinedDirectness, spread) }
        if spread > configuration.maximumSpreadDeg { return block(nil, .spread, combinedDirectness, spread) }
        let e = DirectionMath.estimate(from: v, frame: .device, confidence: combinedDirectness)
        return block(e, nil, combinedDirectness, spread)
    }

    private mutating func clearBlock() {
        frameInBlock = 0
        gatedFrames = 0
        for b in 0..<bandCount {
            allI[b] = .zero; allE[b] = 0; selI[b] = .zero; selE[b] = 0; selCount[b] = 0
        }
    }
}

/// Synthetic SN3D FOA encoding, for tests and bench sanity checks.
public enum FOAEncoder {
    /// Encodes a mono signal arriving from (clockwise azimuth, elevation) into four ACN/SN3D channels
    /// W, Y, Z, X: W = s, Y = s·sin θ·cos φ, Z = s·sin φ, X = s·cos θ·cos φ with θ = −azimuth
    /// (counter-clockwise, ambisonic convention).
    public static func encodeACN(_ s: [Float], azimuthDeg: Double, elevationDeg: Double = 0) -> [[Float]] {
        let u = DirectionMath.unitVector(azimuthDeg: azimuthDeg, elevationDeg: elevationDeg)
        let gx = Float(u.x), gy = Float(u.y), gz = Float(u.z)
        return [s, s.map { $0 * gy }, s.map { $0 * gz }, s.map { $0 * gx }]
    }
}
