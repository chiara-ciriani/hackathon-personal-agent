import XCTest
@testable import QuietCore

final class AudioDOATests: XCTestCase {
    private let fs = 48_000

    private func run(_ acn: [[Float]], config: FOADirectionConfiguration = .init(),
                     calibration: FOAAxisCalibration = .identity) -> [FOADirectionBlock] {
        var est = FOADirectionEstimator(configuration: config, calibration: calibration)
        var blocks: [FOADirectionBlock] = []
        // Feed in 4096-sample chunks like a capture callback would.
        var i = 0
        let n = acn[0].count
        while i < n {
            let e = min(i + 4096, n)
            blocks += est.append(acn: acn.map { Array($0[i..<e]) })
            i = e
        }
        return blocks
    }

    /// Plane-wave noise bursts from `azimuth` plus a little independent sensor noise (−30 dB).
    private func burstScene(azimuth: Double, elevation: Double = 0, seed: UInt64) -> [[Float]] {
        let src = TestSignals.bursts(count: fs * 2, amplitude: 0.3, seed: seed)
        var acn = FOAEncoder.encodeACN(src, azimuthDeg: azimuth, elevationDeg: elevation)
        var rng = TestNoise(seed: seed &+ 99)
        for c in 0..<4 { acn[c] = TestSignals.add(acn[c], rng.samples(fs * 2, amplitude: 0.009)) }
        return acn
    }

    func testChannelReorder() {
        XCTAssertEqual(FOAChannelOrder.acnToWXYZ(["W", "Y", "Z", "X"]), ["W", "X", "Y", "Z"])
    }

    func testAzimuthConventions() {
        XCTAssertEqual(DirectionMath.azimuthDegrees(Vector3(1, 0, 0)), 0, accuracy: 1e-9)
        XCTAssertEqual(DirectionMath.azimuthDegrees(Vector3(0, -1, 0)), 90, accuracy: 1e-9)   // right
        XCTAssertEqual(DirectionMath.azimuthDegrees(Vector3(0, 1, 0)), -90, accuracy: 1e-9)   // left
        XCTAssertEqual(DirectionMath.sector(azimuthDeg: 0), 0)
        XCTAssertEqual(DirectionMath.sector(azimuthDeg: 22.4), 0)
        XCTAssertEqual(DirectionMath.sector(azimuthDeg: -22.4), 0)
        XCTAssertEqual(DirectionMath.sector(azimuthDeg: 22.6), 1)
        XCTAssertEqual(DirectionMath.sector(azimuthDeg: 90), 2)
        XCTAssertEqual(DirectionMath.sector(azimuthDeg: 180), 4)
        XCTAssertEqual(DirectionMath.sector(azimuthDeg: -180), 4)
        XCTAssertEqual(DirectionMath.sector(azimuthDeg: -90), 6)
        XCTAssertEqual(DirectionMath.sector(azimuthDeg: -30), 7)
        let v = DirectionMath.unitVector(azimuthDeg: 37, elevationDeg: 12)
        XCTAssertEqual(DirectionMath.azimuthDegrees(v), 37, accuracy: 1e-9)
        XCTAssertEqual(DirectionMath.elevationDegrees(v), 12, accuracy: 1e-9)
    }

    func testPlaneWaveBurstsFromKnownDirections() {
        for (i, az) in [0.0, 30, 90, -90, 135, 180, -45].enumerated() {
            let blocks = run(burstScene(azimuth: az, seed: UInt64(10 + i)))
            let estimates = blocks.compactMap(\.estimate)
            XCTAssertGreaterThanOrEqual(estimates.count, 2, "azimuth \(az): \(blocks.map { $0.abstention?.rawValue ?? "ok" })")
            for e in estimates {
                XCTAssertEqual(e.frame, .device)
                XCTAssertLessThan(angularDistance(e.azimuthDeg, az), 5, "azimuth \(az) estimated \(e.azimuthDeg)")
                XCTAssertGreaterThan(e.confidence, 0.7)
                XCTAssertEqual(e.sector, DirectionMath.sector(azimuthDeg: az))
            }
        }
    }

    func testElevatedSource() {
        let estimates = run(burstScene(azimuth: 60, elevation: 30, seed: 5)).compactMap(\.estimate)
        XCTAssertFalse(estimates.isEmpty)
        for e in estimates {
            XCTAssertLessThan(angularDistance(e.azimuthDeg, 60), 5)
            XCTAssertEqual(e.elevationDeg!, 30, accuracy: 5)
        }
    }

    func testSteadyToneWithoutOnsetGate() {
        let n = fs * 2
        var src = [Float](repeating: 0, count: n)
        for f in [600.0, 1000, 2000, 3000] {
            src = TestSignals.add(src, TestSignals.sine(frequency: f, amplitude: 0.05, count: n))
        }
        var config = FOADirectionConfiguration()
        config.requireOnset = false
        let estimates = run(FOAEncoder.encodeACN(src, azimuthDeg: -120), config: config).compactMap(\.estimate)
        XCTAssertGreaterThanOrEqual(estimates.count, 3)
        for e in estimates { XCTAssertLessThan(angularDistance(e.azimuthDeg, -120), 5) }
        // With the gate on, a steady tone has no onsets after the first block and is ignored.
        let gated = run(FOAEncoder.encodeACN(src, azimuthDeg: -120))
        XCTAssertTrue(gated.dropFirst().allSatisfy { $0.estimate == nil })
    }

    func testDiffuseNoiseAbstains() {
        var rng = TestNoise(seed: 42)
        // Steady independent channels: no onsets.
        let steady = (0..<4).map { _ in rng.samples(fs * 2, amplitude: 0.3) }
        XCTAssertTrue(run(steady).allSatisfy { $0.estimate == nil })
        // Bursty independent channels: onsets exist, but the field is diffuse.
        let bursty = (0..<4).map { c in TestSignals.bursts(count: fs * 2, amplitude: 0.3, seed: UInt64(200 + c)) }
        let blocks = run(bursty)
        XCTAssertFalse(blocks.isEmpty)
        XCTAssertTrue(blocks.allSatisfy { $0.estimate == nil }, "\(blocks.map { ($0.directness, $0.spreadDeg) })")
        // And without the onset gate it must still abstain.
        var config = FOADirectionConfiguration()
        config.requireOnset = false
        XCTAssertTrue(run(steady, config: config).allSatisfy { $0.estimate == nil })
    }

    func testSilenceAbstains() {
        let silence = [[Float]](repeating: [Float](repeating: 0, count: fs), count: 4)
        let blocks = run(silence)
        XCTAssertFalse(blocks.isEmpty)
        XCTAssertTrue(blocks.allSatisfy { $0.estimate == nil })
    }

    func testCalibrationFixesSwappedAxes() {
        // The "device" delivers X and Y swapped with Y negated: raw = P·true.
        let p = Matrix3(rows: Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))
        let front = p * Vector3(1, 0, 0), right = p * Vector3(0, -1, 0), up = p * Vector3(0, 0, 1)
        let cal = FOAAxisCalibration.fit(front: front * 3, right: right * 0.5, up: up)!
        XCTAssertLessThan(cal.residualDegrees(front: front, right: right, up: up), 0.01)
        let dir = DirectionMath.unitVector(azimuthDeg: 70, elevationDeg: 10)
        XCTAssertEqual(DirectionMath.azimuthDegrees(cal.apply(p * dir)), 70, accuracy: 1e-6)

        // End to end: a scene recorded with swapped axes is estimated correctly after calibration.
        var acn = burstScene(azimuth: 40, seed: 77)          // W, Y, Z, X
        let x = acn[3], y = acn[1], z = acn[2]
        var rx = x, ry = y, rz = z
        for i in x.indices {
            let v = p * Vector3(Double(x[i]), Double(y[i]), Double(z[i]))
            rx[i] = Float(v.x); ry[i] = Float(v.y); rz[i] = Float(v.z)
        }
        acn = [acn[0], ry, rz, rx]
        let uncal = run(acn).compactMap(\.estimate)
        XCTAssertTrue(uncal.allSatisfy { angularDistance($0.azimuthDeg, 40) > 30 })
        let fixed = run(acn, calibration: cal).compactMap(\.estimate)
        XCTAssertFalse(fixed.isEmpty)
        for e in fixed { XCTAssertLessThan(angularDistance(e.azimuthDeg, 40), 5) }
    }

    func testCalibrationFitToleratesNoise() {
        let cal = FOAAxisCalibration.fit(front: Vector3(1, 0.05, -0.02), right: Vector3(0.03, -1, 0.04),
                                         up: Vector3(-0.02, 0.01, 1))!
        XCTAssertEqual(cal.matrix.determinant, 1, accuracy: 1e-9)
        XCTAssertLessThan(cal.residualDegrees(front: Vector3(1, 0.05, -0.02), right: Vector3(0.03, -1, 0.04),
                                              up: Vector3(-0.02, 0.01, 1)), 5)
        XCTAssertNil(FOAAxisCalibration.fit(front: .zero, right: Vector3(0, -1, 0), up: Vector3(0, 0, 1)))
    }

    func testWorldRotation() {
        // Device rotated 90° clockwise (yaw) in the world: device-front points to world-right.
        let yawCW90 = Matrix3(columns: Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1))
        let e = DirectionEstimate(frame: .device, azimuthDeg: 10, elevationDeg: 0, sector: 0, confidence: 0.9)
        let w = DirectionMath.toWorld(e, deviceToWorld: yawCW90)
        XCTAssertEqual(w.frame, .world)
        XCTAssertEqual(w.azimuthDeg, 100, accuracy: 1e-9)
        XCTAssertEqual(w.sector, 2)
        XCTAssertEqual(w.confidence, 0.9)
    }

    func testMatrixHelpers() {
        let r = Matrix3(rows: Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1))
        let prod = r * r.transposed
        for i in 0..<9 { XCTAssertEqual(prod.m[i], Matrix3.identity.m[i], accuracy: 1e-12) }
        XCTAssertEqual(r.inverse!.m, r.transposed.m)
        let skewed = Matrix3(rowMajor: [1.1, 0.1, 0, -0.05, 0.9, 0, 0, 0, 1.2])
        let o = skewed.orthogonalized!
        let oo = o * o.transposed
        for i in 0..<9 { XCTAssertEqual(oo.m[i], Matrix3.identity.m[i], accuracy: 1e-9) }
    }
}
