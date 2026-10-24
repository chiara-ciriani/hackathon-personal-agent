// Small 3-D vector/matrix helpers and azimuth conventions for FOA direction of arrival. Foundation only.
//
// Frames
// ------
// "Ambisonic frame" (used for the device and for the world): x = front, y = left, z = up (right-handed),
// which is the standard ambisonic convention. Azimuth reported in DirectionEstimate is 0° ahead (+x) and
// POSITIVE CLOCKWISE seen from above, so a source on the right (−y) is +90° and on the left is −90°:
//     azimuth = atan2(−y, x)          elevation = atan2(z, √(x² + y²))
// Sector: 0 = −22.5°…22.5°, then clockwise in 45° steps (2 = right, 4 = behind, 6 = left).
import Foundation

public struct Vector3: Sendable, Hashable {
    public var x: Double, y: Double, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static let zero = Vector3(0, 0, 0)

    public var norm: Double { (x * x + y * y + z * z).squareRoot() }
    public var normalized: Vector3 { let n = norm; return n > 0 ? self / n : self }
    public func dot(_ o: Vector3) -> Double { x * o.x + y * o.y + z * o.z }
    public func cross(_ o: Vector3) -> Vector3 {
        Vector3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }
    public static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Vector3, s: Double) -> Vector3 { Vector3(a.x * s, a.y * s, a.z * s) }
    public static func / (a: Vector3, s: Double) -> Vector3 { Vector3(a.x / s, a.y / s, a.z / s) }
    public static func += (a: inout Vector3, b: Vector3) { a = a + b }
}

/// Row-major 3×3 matrix.
public struct Matrix3: Sendable, Hashable {
    public var m: [Double]   // 9 values, row-major

    public init(rows r0: Vector3, _ r1: Vector3, _ r2: Vector3) {
        m = [r0.x, r0.y, r0.z, r1.x, r1.y, r1.z, r2.x, r2.y, r2.z]
    }
    public init(columns c0: Vector3, _ c1: Vector3, _ c2: Vector3) {
        m = [c0.x, c1.x, c2.x, c0.y, c1.y, c2.y, c0.z, c1.z, c2.z]
    }
    public init(rowMajor values: [Double]) {
        precondition(values.count == 9)
        m = values
    }
    public static let identity = Matrix3(rowMajor: [1, 0, 0, 0, 1, 0, 0, 0, 1])

    public subscript(r: Int, c: Int) -> Double {
        get { m[r * 3 + c] }
        set { m[r * 3 + c] = newValue }
    }

    public static func * (a: Matrix3, v: Vector3) -> Vector3 {
        Vector3(a.m[0] * v.x + a.m[1] * v.y + a.m[2] * v.z,
                a.m[3] * v.x + a.m[4] * v.y + a.m[5] * v.z,
                a.m[6] * v.x + a.m[7] * v.y + a.m[8] * v.z)
    }

    public static func * (a: Matrix3, b: Matrix3) -> Matrix3 {
        var out = [Double](repeating: 0, count: 9)
        for r in 0..<3 { for c in 0..<3 {
            out[r * 3 + c] = a[r, 0] * b[0, c] + a[r, 1] * b[1, c] + a[r, 2] * b[2, c]
        } }
        return Matrix3(rowMajor: out)
    }

    public var transposed: Matrix3 {
        Matrix3(rowMajor: [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]])
    }

    public var determinant: Double {
        m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6]) + m[2] * (m[3] * m[7] - m[4] * m[6])
    }

    public var inverse: Matrix3? {
        let d = determinant
        guard abs(d) > 1e-12 else { return nil }
        let a = m
        let inv: [Double] = [
            a[4] * a[8] - a[5] * a[7], a[2] * a[7] - a[1] * a[8], a[1] * a[5] - a[2] * a[4],
            a[5] * a[6] - a[3] * a[8], a[0] * a[8] - a[2] * a[6], a[2] * a[3] - a[0] * a[5],
            a[3] * a[7] - a[4] * a[6], a[1] * a[6] - a[0] * a[7], a[0] * a[4] - a[1] * a[3]
        ]
        return Matrix3(rowMajor: inv.map { $0 / d })
    }

    /// Orthogonal polar factor (nearest orthogonal matrix, det ±1) by Newton iteration
    /// X ← ½(X + X⁻ᵀ). Converges quadratically for non-singular input.
    public var orthogonalized: Matrix3? {
        var x = self
        for _ in 0..<50 {
            guard let inv = x.inverse else { return nil }
            let it = inv.transposed
            var next = x
            for i in 0..<9 { next.m[i] = 0.5 * (x.m[i] + it.m[i]) }
            var delta = 0.0
            for i in 0..<9 { delta = max(delta, abs(next.m[i] - x.m[i])) }
            x = next
            if delta < 1e-13 { break }
        }
        return x
    }
}

public enum DirectionMath {
    /// Wraps degrees to [−180, 180).
    public static func wrapDegrees(_ a: Double) -> Double {
        var v = (a + 180).truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        return v - 180
    }

    /// Clockwise-positive azimuth of a vector in an ambisonic frame (x front, y left).
    public static func azimuthDegrees(_ v: Vector3) -> Double {
        wrapDegrees(atan2(-v.y, v.x) * 180 / .pi)
    }

    public static func elevationDegrees(_ v: Vector3) -> Double {
        atan2(v.z, (v.x * v.x + v.y * v.y).squareRoot()) * 180 / .pi
    }

    /// Unit vector for a clockwise-positive azimuth and elevation (degrees).
    public static func unitVector(azimuthDeg: Double, elevationDeg: Double = 0) -> Vector3 {
        let a = azimuthDeg * .pi / 180, e = elevationDeg * .pi / 180
        return Vector3(cos(a) * cos(e), -sin(a) * cos(e), sin(e))
    }

    /// 0 = −22.5°…22.5°, clockwise in 45° steps.
    public static func sector(azimuthDeg: Double) -> Int {
        let s = Int(((wrapDegrees(azimuthDeg) + 22.5) / 45).rounded(.down))
        return ((s % 8) + 8) % 8
    }

    /// Builds a DirectionEstimate from a direction vector.
    public static func estimate(from v: Vector3, frame: DirectionEstimate.Frame, confidence: Double) -> DirectionEstimate {
        let az = azimuthDegrees(v)
        return DirectionEstimate(frame: frame, azimuthDeg: az, elevationDeg: elevationDegrees(v),
                                 sector: sector(azimuthDeg: az), confidence: min(1, max(0, confidence)))
    }

    /// Rotates a device-frame estimate into the world frame.
    /// `deviceToWorld` maps a vector in the (calibrated) device ambisonic frame to the world ambisonic
    /// frame (x = the world's reference "ahead", y = left, z = up along gravity). The app builds it from
    /// the ARKit camera transform (see ios/QuietCompass/Audio/FOAFeatureSource.swift).
    public static func toWorld(_ e: DirectionEstimate, deviceToWorld: Matrix3) -> DirectionEstimate {
        let v = unitVector(azimuthDeg: e.azimuthDeg, elevationDeg: e.elevationDeg ?? 0)
        return toWorld(deviceUnitVector: v, deviceToWorld: deviceToWorld, confidence: e.confidence)
    }

    public static func toWorld(deviceUnitVector v: Vector3, deviceToWorld: Matrix3, confidence: Double) -> DirectionEstimate {
        estimate(from: deviceToWorld * v, frame: .world, confidence: confidence)
    }
}
