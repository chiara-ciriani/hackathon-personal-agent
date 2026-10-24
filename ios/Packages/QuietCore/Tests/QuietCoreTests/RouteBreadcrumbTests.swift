import XCTest
@testable import QuietCore

final class RouteBreadcrumbTests: XCTestCase {
    private let session = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func pose(_ s: Double, _ x: Double, _ z: Double, _ tracking: TrackingState = .normal) -> PoseSample {
        PoseSample(t: t0.addingTimeInterval(s), position: Position(x: x, z: z), headingRad: 0, tracking: tracking)
    }

    func testFirstNormalPoseDropsACrumb() {
        var r = BreadcrumbRecorder(sessionId: session)
        let crumb = r.ingest(pose(0, 0, 0))
        XCTAssertEqual(crumb?.seq, 0)
        XCTAssertEqual(crumb?.segment, 0)
        XCTAssertEqual(crumb?.sessionId, session)
    }

    func testDropsCrumbEveryMetre() {
        var r = BreadcrumbRecorder(sessionId: session)
        var crumbs: [Crumb] = []
        // 0.4 m per sample (0.8 m/s at 2 Hz) along −Z for 10 s.
        for i in 0...20 {
            if let c = r.ingest(pose(Double(i) * 0.5, 0, -0.4 * Double(i))) { crumbs.append(c) }
        }
        XCTAssertEqual(crumbs.map(\.seq), Array(0..<crumbs.count))
        XCTAssertEqual(crumbs.count, 7) // z = 0, -1.2, -2.4, -3.6, -4.8, -6.0, -7.2
        for (a, b) in zip(crumbs, crumbs.dropFirst()) {
            XCTAssertGreaterThanOrEqual(a.position.distance(to: b.position), 1.0)
        }
    }

    func testIgnoresNonNormalTracking() {
        var r = BreadcrumbRecorder(sessionId: session)
        XCTAssertNil(r.ingest(pose(0, 0, 0, .limited)))
        XCTAssertNil(r.ingest(pose(1, 5, 0, .notAvailable)))
        XCTAssertNotNil(r.ingest(pose(2, 5, 0)))
        XCTAssertNil(r.ingest(pose(3, 9, 0, .limited)))
        XCTAssertEqual(r.nextSeq, 1)
    }

    func testShortGapKeepsSegment() {
        var r = BreadcrumbRecorder(sessionId: session)
        _ = r.ingest(pose(0, 0, 0))
        _ = r.ingest(pose(10, 0, 0, .limited))
        let c = r.ingest(pose(25, 2, 0))
        XCTAssertEqual(c?.segment, 0)
        XCTAssertFalse(r.needsZoneLabel)
    }

    func testLongGapClosesSegmentAndAsksForZone() {
        var r = BreadcrumbRecorder(sessionId: session)
        _ = r.ingest(pose(0, 0, 0))
        _ = r.ingest(pose(1, 1.5, 0))
        _ = r.ingest(pose(20, 0, 0, .limited))
        _ = r.ingest(pose(40, 0, 0, .notAvailable))
        XCTAssertTrue(r.needsZoneLabel)
        // Even a position close to the last crumb starts the new segment.
        let c = r.ingest(pose(41, 1.6, 0))
        XCTAssertEqual(c?.segment, 1)
        XCTAssertEqual(c?.seq, 2)
        r.acknowledgeZoneLabel()
        XCTAssertFalse(r.needsZoneLabel)
        XCTAssertNil(r.ingest(pose(42, 1.9, 0)))
    }

    func testResumesSeqAndSegment() {
        var r = BreadcrumbRecorder(sessionId: session, nextSeq: 12, segment: 3)
        // A restored recorder has no last crumb, so its first crumb continues the given segment.
        XCTAssertEqual(r.ingest(pose(0, 0, 0))?.seq, 12)
        XCTAssertEqual(r.segment, 3)
    }

    func testHeadingFromCameraAxis() throws {
        // Camera looking along world −Z: camera +Z axis is world +Z.
        XCTAssertEqual(try XCTUnwrap(Heading.fromCameraZAxis(x: 0, z: 1)), 0, accuracy: 1e-9)
        // Looking along +X: camera +Z axis is world −X; heading +π/2 (clockwise from above).
        XCTAssertEqual(try XCTUnwrap(Heading.fromCameraZAxis(x: -1, z: 0)), .pi / 2, accuracy: 1e-9)
        // Looking along −X.
        XCTAssertEqual(try XCTUnwrap(Heading.fromCameraZAxis(x: 1, z: 0)), -.pi / 2, accuracy: 1e-9)
        // Phone flat: no reliable yaw.
        XCTAssertNil(Heading.fromCameraZAxis(x: 0.05, z: 0.05))
        // Bearing uses the same convention.
        XCTAssertEqual(Heading.bearing(from: .init(x: 0, z: 0), to: .init(x: 0, z: -3)), 0, accuracy: 1e-9)
        XCTAssertEqual(Heading.bearing(from: .init(x: 0, z: 0), to: .init(x: 2, z: 0)), .pi / 2, accuracy: 1e-9)
    }
}
