import Foundation
import simd

// Pure maths for the Radar and Locate modes (Foundation + simd only, so the self-check in
// SelfCheck/main.swift compiles it with plain `swiftc`).
//
// Angles: "bearing" = compass degrees, clockwise from north, 0..<360.
// Plane coordinates for Locate: SIMD2(east, north) in metres.

/// One DOA analysis window (2048 samples, hop 1024), already rotated to the world frame.
nonisolated struct WindowObservation: Sendable {
    var bearing: Double        // world bearing of this window's intensity vector
    var elevation: Double      // degrees above the horizon
    var confidence: Double     // |Σ I| / Σ |I| for this window alone, 0...1
    var energy: Double         // W-channel mean square in the DOA band (200-4000 Hz), linear
    var duration: Double       // seconds of audio this window stands for (hop / sample rate)
}

nonisolated enum Compass {
    static let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    static func normalize(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    static func point(_ bearing: Double) -> String {
        points[Int((normalize(bearing) / 45).rounded()) % 8]
    }

    /// Unit vector (east, north) of a compass bearing.
    static func unit(_ bearing: Double) -> SIMD2<Double> {
        let r = bearing * .pi / 180
        return SIMD2(sin(r), cos(r))
    }

    static func bearing(of v: SIMD2<Double>) -> Double {
        normalize(atan2(v.x, v.y) * 180 / .pi)
    }
}

// MARK: - Radar: per-sector accumulation from one spot

nonisolated struct RadarSector: Sendable, Equatable {
    var centre: Double            // bearing of the sector centre
    var heard: Bool               // enough confident data to draw it
    var relativeDB: Double?       // 10·log10(energy / loudest sector's energy), ≤ 0; nil if not heard
    var levelDBFS: Double?        // mean band level of the windows that landed here (relative dBFS)
    var meanConfidence: Double?
    var seconds: Double           // decayed seconds of confident audio that landed here
}

nonisolated struct RadarSnapshot: Sendable, Equatable {
    var sectors: [RadarSector]
    var dominant: Int?            // index of the loudest heard sector
    var dominantBearing: Double?  // energy-weighted mean bearing of the dominant sector ± 1 neighbour
    var dominantLevelDBFS: Double?
    var dominantConfidence: Double?

    static let empty = SectorRadar().snapshot()
}

/// Energy accumulated per world-bearing sector with exponential forgetting.
/// Sector i is centred on i·15°, so sector 0 spans 352.5°..<7.5° (north).
nonisolated struct SectorRadar: Sendable {
    static let sectorCount = 24
    static var width: Double { 360 / Double(sectorCount) }

    var timeConstant: Double = 20
    var minSeconds: Double = 0.25        // a sector with less decayed confident audio is "not heard yet"
    var maxAbsElevation: Double = 60     // overhead/underfoot windows have no useful bearing

    private(set) var energy = [Double](repeating: 0, count: sectorCount)
    private(set) var seconds = [Double](repeating: 0, count: sectorCount)
    private var confidenceSeconds = [Double](repeating: 0, count: sectorCount)
    private var vector = [SIMD2<Double>](repeating: .zero, count: sectorCount)  // Σ energy · unit(bearing)
    private var lastTime: Double?

    init(timeConstant: Double = 20) { self.timeConstant = timeConstant }

    static func sector(for bearing: Double) -> Int {
        Int((Compass.normalize(bearing) / width).rounded()) % sectorCount
    }

    mutating func reset() { self = SectorRadar(timeConstant: timeConstant) }

    /// Forget old data up to `time` (seconds, any monotonic clock).
    mutating func decay(to time: Double) {
        defer { lastTime = max(lastTime ?? time, time) }
        guard let last = lastTime, time > last else { return }
        let f = exp(-(time - last) / timeConstant)
        for i in 0..<Self.sectorCount {
            energy[i] *= f; seconds[i] *= f; confidenceSeconds[i] *= f; vector[i] *= f
        }
    }

    /// Adds the window if its confidence reaches `threshold`. Returns whether it was used.
    @discardableResult
    mutating func add(_ w: WindowObservation, threshold: Double, time: Double) -> Bool {
        decay(to: time)
        guard w.confidence >= threshold, abs(w.elevation) <= maxAbsElevation,
              w.energy.isFinite, w.energy > 0 else { return false }
        let i = Self.sector(for: w.bearing)
        energy[i] += w.energy * w.duration
        seconds[i] += w.duration
        confidenceSeconds[i] += w.confidence * w.duration
        vector[i] += w.energy * w.duration * Compass.unit(w.bearing)
        return true
    }

    func snapshot() -> RadarSnapshot {
        let heard = (0..<Self.sectorCount).map { seconds[$0] >= minSeconds && energy[$0] > 0 }
        let loudest = (0..<Self.sectorCount).filter { heard[$0] }.max { energy[$0] < energy[$1] }
        let sectors = (0..<Self.sectorCount).map { i -> RadarSector in
            guard heard[i], let top = loudest else {
                return RadarSector(centre: Double(i) * Self.width, heard: false, relativeDB: nil,
                                   levelDBFS: nil, meanConfidence: nil, seconds: seconds[i])
            }
            return RadarSector(centre: Double(i) * Self.width, heard: true,
                               relativeDB: 10 * log10(energy[i] / energy[top]),
                               levelDBFS: 10 * log10(energy[i] / seconds[i]),
                               meanConfidence: confidenceSeconds[i] / seconds[i], seconds: seconds[i])
        }
        var snap = RadarSnapshot(sectors: sectors, dominant: loudest)
        if let d = loudest {
            let n = Self.sectorCount
            let v = vector[(d + n - 1) % n] + vector[d] + vector[(d + 1) % n]
            snap.dominantBearing = simd_length(v) > 0 ? Compass.bearing(of: v) : sectors[d].centre
            snap.dominantLevelDBFS = sectors[d].levelDBFS
            snap.dominantConfidence = sectors[d].meanConfidence
        }
        return snap
    }
}

// MARK: - Locate: least-squares intersection of bearing rays

nonisolated struct BearingRay: Sendable, Equatable {
    var origin: SIMD2<Double>     // (east, north) metres
    var bearing: Double           // compass degrees, clockwise from north
    var confidence: Double = 1

    var direction: SIMD2<Double> { Compass.unit(bearing) }

    init(origin: SIMD2<Double>, bearing: Double, confidence: Double = 1) {
        self.origin = origin
        self.bearing = bearing
        self.confidence = confidence
    }

    /// Maths convention: angle counter-clockwise from +x (east). 45° = NE, 135° = NW.
    init(origin: SIMD2<Double>, mathAngle: Double, confidence: Double = 1) {
        self.init(origin: origin, bearing: Compass.normalize(90 - mathAngle), confidence: confidence)
    }
}

nonisolated enum TriangulationFailure: Error, Equatable, Sendable {
    case needTwoRays
    case nearlyParallel(maxAngle: Double)      // all pairs closer than the minimum crossing angle
    case pointsBehind(remaining: Int)          // after dropping rays that point away, < 2 remain
}

nonisolated struct SourceEstimate: Sendable, Equatable {
    var position: SIMD2<Double>               // (east, north) metres
    var uncertainty: Double                   // metres, ~1σ radius
    var residualRMS: Double                   // metres, weighted perpendicular miss of the used rays
    var usedRays: [Int]                       // indices into the input
    var rejectedRays: [Int]                   // pointed away from the solution
    var maxCrossingAngle: Double              // degrees, best pair among used rays
}

nonisolated enum Triangulation {
    static let minCrossingAngle = 15.0
    /// Bearing error assumed for a ray with confidence 1; scaled by 1/confidence (capped).
    static let bearingSigmaAtFullConfidence = 8.0

    /// Angle between two rays as lines, 0...90°.
    static func lineAngle(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        acos(min(1, abs(simd_dot(a, b)))) * 180 / .pi
    }

    static func maxCrossingAngle(_ rays: [BearingRay]) -> Double {
        var best = 0.0
        for i in rays.indices { for j in rays.indices where j > i {
            best = max(best, lineAngle(rays[i].direction, rays[j].direction))
        } }
        return best
    }

    /// Point minimising Σ wᵢ · (perpendicular distance to line i)², wᵢ = confidence.
    /// Rays whose source would lie behind them are dropped and the solve repeated.
    static func locate(_ rays: [BearingRay]) -> Result<SourceEstimate, TriangulationFailure> {
        guard rays.count >= 2 else { return .failure(.needTwoRays) }
        var used = Array(rays.indices)
        var rejected: [Int] = []
        while true {
            let subset = used.map { rays[$0] }
            let angle = maxCrossingAngle(subset)
            guard angle >= minCrossingAngle else { return .failure(.nearlyParallel(maxAngle: angle)) }
            guard let p = solve(subset) else { return .failure(.nearlyParallel(maxAngle: angle)) }
            // Distance along each ray to the foot of the perpendicular from p.
            let along = subset.map { simd_dot(p - $0.origin, $0.direction) }
            if let worst = along.indices.filter({ along[$0] <= 0 }).min(by: { along[$0] < along[$1] }) {
                rejected.append(used.remove(at: worst))
                guard used.count >= 2 else { return .failure(.pointsBehind(remaining: used.count)) }
                continue
            }
            let (sigma, rms) = uncertainty(p, subset)
            return .success(SourceEstimate(position: p, uncertainty: max(sigma, rms), residualRMS: rms,
                                           usedRays: used, rejectedRays: rejected, maxCrossingAngle: angle))
        }
    }

    private static func weight(_ r: BearingRay) -> Double { max(0.05, min(1, r.confidence)) }

    private static func solve(_ rays: [BearingRay]) -> SIMD2<Double>? {
        var a = simd_double2x2(0)
        var b = SIMD2<Double>.zero
        for r in rays {
            let d = r.direction
            let proj = matrix_identity_double2x2 - simd_double2x2(columns: (d * d.x, d * d.y))  // I − d dᵀ
            a += weight(r) * proj
            b += weight(r) * (proj * r.origin)
        }
        guard abs(a.determinant) > 1e-9 else { return nil }
        return a.inverse * b
    }

    /// (1σ radius from bearing errors, weighted RMS of perpendicular misses).
    /// Bearing-only Fisher information: F = Σ (I − d dᵀ) / (rᵢ² σᵢ²), radius = √trace(F⁻¹).
    private static func uncertainty(_ p: SIMD2<Double>, _ rays: [BearingRay]) -> (Double, Double) {
        var f = simd_double2x2(0)
        var miss2 = 0.0, wsum = 0.0
        for r in rays {
            let d = r.direction
            let proj = matrix_identity_double2x2 - simd_double2x2(columns: (d * d.x, d * d.y))
            let range = max(0.5, simd_length(p - r.origin))
            let sigma = bearingSigmaAtFullConfidence / max(0.25, min(1, r.confidence)) * .pi / 180
            f += (1 / (range * range * sigma * sigma)) * proj
            miss2 += weight(r) * simd_length_squared(proj * (p - r.origin))
            wsum += weight(r)
        }
        let rms = (miss2 / max(wsum, 1e-12)).squareRoot()
        guard abs(f.determinant) > 1e-12 else { return (.infinity, rms) }
        let cov = f.inverse
        return ((cov.columns.0.x + cov.columns.1.y).squareRoot(), rms)
    }

    /// "6.2 m NE of start, ±1.5 m"
    static func describe(_ e: SourceEstimate, start: SIMD2<Double> = .zero) -> String {
        let v = e.position - start
        return String(format: "%.1f m %@ of start, ±%.1f m", simd_length(v), Compass.point(Compass.bearing(of: v)),
                      e.uncertainty)
    }
}

// MARK: - ARKit frames ↔ the app's world frame

/// ARKit (worldAlignment = .gravityAndHeading): +x east, +y up, −z TRUE north; positions in metres
/// from where the session started.
/// ARCamera.transform columns are the camera axes in that world. Camera space (Apple docs): +x along
/// the long axis from the front camera toward the bottom (Home button) edge, +y toward the right edge
/// in portrait, +z out of the screen, so it looks along −z (the rear camera direction).
/// CoreMotion device axes: +x right edge, +y top edge, +z out of the screen. Hence
///   device +x = camera +y,  device +y = camera −x,  device +z = camera +z.
/// The rest of the app works in CoreMotion's xNorth/yWest/zUp frame (see Geo.bearing), so ARKit
/// world vectors are mapped with north = −z, west = −x, up = +y.
nonisolated enum ARFrameMath {
    static func nwu(_ ar: SIMD3<Double>) -> SIMD3<Double> { SIMD3(-ar.z, -ar.x, ar.y) }

    /// World (north/west/up) images of the device's x, y, z axes, i.e. the rows `Attitude.toWorld` uses.
    static func deviceAxesNWU(cameraX c0: SIMD3<Double>, cameraY c1: SIMD3<Double>, cameraZ c2: SIMD3<Double>)
        -> (x: SIMD3<Double>, y: SIMD3<Double>, z: SIMD3<Double>) {
        (nwu(c1), nwu(-c0), nwu(c2))
    }

    /// ARKit position (x, z) → (east, north) for the Locate plot.
    static func eastNorth(x: Double, z: Double) -> SIMD2<Double> { SIMD2(x, -z) }
}
