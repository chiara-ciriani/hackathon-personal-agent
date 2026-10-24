// FOA channel order and axis calibration. Foundation only.
import Foundation

public enum FOAChannelOrder {
    /// ACN order is W(0), Y(1), Z(2), X(3). Returns the indices to read W, X, Y, Z from an ACN buffer.
    public static let acnIndicesForWXYZ = [0, 3, 1, 2]

    /// Reorders four ACN channels (W, Y, Z, X) into W, X, Y, Z.
    public static func acnToWXYZ<T>(_ acn: [T]) -> [T] {
        precondition(acn.count == 4, "FOA needs exactly four channels")
        return acnIndicesForWXYZ.map { acn[$0] }
    }
}

/// A 3×3 matrix applied to the [X, Y, Z] components before any direction is computed, plus a scalar gain
/// for the directional channels relative to W.
///
/// - `matrix` fixes axis order, sign flips and small rotations between what the device delivers and the
///   ambisonic convention (x front, y left, z up). Identity by default.
/// - `directionalGain` fixes normalization: 1 for SN3D (what we request). If the device turns out to deliver
///   N3D, use 1/√3; for FuMa (W scaled by 1/√2) use 1/√2. Check on the bench: with a near loudspeaker
///   the per-bin ratio ‖I‖/E should peak close to 1 (it is exactly 1 for an SN3D plane wave).
public struct FOAAxisCalibration: Sendable, Hashable, Codable {
    public var matrix: Matrix3
    public var directionalGain: Double

    public init(matrix: Matrix3 = .identity, directionalGain: Double = 1) {
        self.matrix = matrix; self.directionalGain = directionalGain
    }
    public static let identity = FOAAxisCalibration()

    public func apply(_ v: Vector3) -> Vector3 { (matrix * v) * directionalGain }

    /// Fits the calibration from three reference measurements: the mean (pseudo-intensity or direction)
    /// vector measured with a loudspeaker in FRONT of the phone, to its RIGHT, and ABOVE it, all in the raw
    /// device frame. Magnitudes do not matter.
    ///
    /// Method: orthogonal Procrustes. Targets are front = (1,0,0), right = (0,−1,0), up = (0,0,1). We want the
    /// orthogonal R minimizing Σ‖R·mᵢ − eᵢ‖², whose solution is the orthogonal polar factor of
    /// M = Σ eᵢ·mᵢᵀ (equivalently U·Vᵀ from the SVD of M). We compute the polar factor by Newton iteration,
    /// which avoids an SVD. Reflections (det = −1) are allowed on purpose: a swapped or sign-flipped axis is
    /// exactly what this is meant to catch. Returns nil if the readings are degenerate (e.g. collinear).
    public static func fit(front: Vector3, right: Vector3, up: Vector3, directionalGain: Double = 1) -> FOAAxisCalibration? {
        let targets = [Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1)]
        let measured = [front.normalized, right.normalized, up.normalized]
        guard measured.allSatisfy({ $0.norm > 0.5 }) else { return nil }
        var m = [Double](repeating: 0, count: 9)
        for (e, v) in zip(targets, measured) {
            let ev = [e.x, e.y, e.z], vv = [v.x, v.y, v.z]
            for r in 0..<3 { for c in 0..<3 { m[r * 3 + c] += ev[r] * vv[c] } }
        }
        guard let r = Matrix3(rowMajor: m).orthogonalized else { return nil }
        return FOAAxisCalibration(matrix: r, directionalGain: directionalGain)
    }

    /// Largest angular error (degrees) of the calibration on the three reference readings.
    public func residualDegrees(front: Vector3, right: Vector3, up: Vector3) -> Double {
        let pairs = [(front, Vector3(1, 0, 0)), (right, Vector3(0, -1, 0)), (up, Vector3(0, 0, 1))]
        return pairs.map { pair -> Double in
            let (m, e) = pair
            let c = max(-1, min(1, (matrix * m).normalized.dot(e)))
            return acos(c) * 180 / .pi
        }.max() ?? 0
    }
}

extension Matrix3: Codable {
    public init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer().decode([Double].self)
        guard values.count == 9 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Matrix3 needs 9 values"))
        }
        self.init(rowMajor: values)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(m)
    }
}
