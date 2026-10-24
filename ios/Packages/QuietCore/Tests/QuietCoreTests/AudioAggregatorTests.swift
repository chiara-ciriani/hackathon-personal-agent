import XCTest
@testable import QuietCore

final class AudioAggregatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func frame(_ i: Int, level: Double, speech: Double? = nil, classes: [SoundClass] = [],
                       doa: DirectionEstimate? = nil, bands: [Double]? = nil) -> FeatureFrame {
        FeatureFrame(t: t0.addingTimeInterval(Double(i + 1)), levelDbfs: level, levelAwDbfs: level - 2,
                     shortFrameLevelsDbfs: [Double](repeating: level, count: 8),
                     bandsDb: bands, speechShare: speech, classes: classes, doa: doa)
    }

    func testEmitsEveryFiveFramesWithPowerMeanLevel() async {
        let session = UUID()
        let agg = ObservationAggregator(sessionId: session)
        var out: [Observation] = []
        let levels = [-40.0, -40, -40, -40, -20]
        for (i, l) in levels.enumerated() {
            if let o = await agg.ingest(frame(i, level: l, bands: [Double](repeating: l, count: 6))) { out.append(o) }
        }
        XCTAssertEqual(out.count, 1)
        let o = out[0]
        XCTAssertEqual(o.sessionId, session)
        XCTAssertEqual(o.durationS, 5)
        XCTAssertEqual(o.t, t0.addingTimeInterval(5))
        let expected = 10 * log10((4 * pow(10, -4.0) + pow(10, -2.0)) / 5)
        XCTAssertEqual(o.levelDbfsRel, expected, accuracy: 1e-9)
        XCTAssertEqual(o.levelAwDbfsRel!, expected - 2, accuracy: 1e-9)
        XCTAssertEqual(o.bandsDb!.count, 6)
        XCTAssertEqual(o.bandsDb![0], expected, accuracy: 1e-9)
        XCTAssertEqual(o.tracking, TrackingState.none)
        XCTAssertNil(o.position)
        XCTAssertNil(o.speechShare)
        XCTAssertNil(o.doa)
    }

    func testClassesSpeechAndDoa() async throws {
        let agg = ObservationAggregator(sessionId: UUID())
        let weak = DirectionEstimate(frame: .device, azimuthDeg: 10, elevationDeg: 0, sector: 0, confidence: 0.4)
        let strong = DirectionEstimate(frame: .device, azimuthDeg: 95, elevationDeg: 0, sector: 2, confidence: 0.8)
        var o: Observation?
        for i in 0..<5 {
            let classes = [SoundClass(label: "speech", confidence: 0.6), SoundClass(label: "music", confidence: i < 2 ? 0.9 : 0),
                           SoundClass(label: "crowd", confidence: 0.2), SoundClass(label: "dog", confidence: 0.1)]
            let doa: DirectionEstimate? = i == 1 ? weak : (i == 3 ? strong : nil)
            o = await agg.ingest(frame(i, level: -30, speech: Double(i) * 0.1, classes: classes, doa: doa)) ?? o
        }
        let obs = try XCTUnwrap(o)
        XCTAssertEqual(obs.speechShare!, 0.2, accuracy: 1e-9)
        XCTAssertEqual(obs.classes.map(\.label), ["speech", "music", "crowd"])
        XCTAssertEqual(obs.classes[1].confidence, 0.36, accuracy: 1e-9)
        XCTAssertEqual(obs.doa, strong)
    }

    func testPositionOnlyWhenTrackingNormalAndPlaceLookup() async {
        let place = UUID(), crumb = UUID()
        let agg = ObservationAggregator(sessionId: UUID(),
                                        placeLocator: { $0 == nil ? nil : place },
                                        crumbLocator: { _ in crumb })
        await agg.updatePose(PoseSample(t: t0, position: Position(x: 1, z: 2), headingRad: 0, tracking: .limited))
        var o: Observation?
        for i in 0..<5 { o = await agg.ingest(frame(i, level: -30)) ?? o }
        XCTAssertEqual(o?.tracking, .limited)
        XCTAssertNil(o?.position)
        XCTAssertNil(o?.placeId)
        XCTAssertEqual(o?.crumbId, crumb)

        await agg.updatePose(PoseSample(t: t0, position: Position(x: 1, z: 2), headingRad: 0, tracking: .normal))
        o = nil
        for i in 5..<10 { o = await agg.ingest(frame(i, level: -30)) ?? o }
        XCTAssertEqual(o?.position, Position(x: 1, z: 2))
        XCTAssertEqual(o?.placeId, place)
    }

    func testSpreadAndPeaksComeFromRollingState() async throws {
        let agg = ObservationAggregator(sessionId: UUID())
        var last: Observation?
        for i in 0..<30 {
            // Every 10 s a 1 s event 20 dB above the background.
            let level = i % 10 == 9 ? -30.0 : -50.0
            last = await agg.ingest(frame(i, level: level)) ?? last
        }
        let o = try XCTUnwrap(last)
        XCTAssertGreaterThan(o.spreadDb, 0)
        XCTAssertEqual(o.peaksPerMin, 6, accuracy: 0.01)   // 3 onsets in 30 s
    }

    func testDwellAndConfidence() async {
        let agg = ObservationAggregator(sessionId: UUID())
        for i in 0..<12 { _ = await agg.ingest(frame(i, level: -40)) }
        var d = await agg.currentDwell()
        XCTAssertEqual(d.seconds, 12, accuracy: 1e-9)
        XCTAssertEqual(d.confidence, .low)
        XCTAssertEqual(d.label, "measuring 12 s / 30 s")
        for i in 12..<20 { _ = await agg.ingest(frame(i, level: -40)) }
        d = await agg.currentDwell()
        XCTAssertEqual(d.confidence, .building)
        for i in 20..<31 { _ = await agg.ingest(frame(i, level: -40)) }
        d = await agg.currentDwell()
        XCTAssertEqual(d.confidence, .ok)
        XCTAssertEqual(MeasurementConfidence(dwellSeconds: 14.9), .low)
        XCTAssertEqual(MeasurementConfidence(dwellSeconds: 30), .ok)
    }

    func testObservationEncodesToContractKeys() async throws {
        let agg = ObservationAggregator(sessionId: UUID())
        var o: Observation?
        for i in 0..<5 { o = await agg.ingest(frame(i, level: -30)) ?? o }
        let data = try ContractJSON.encoder().encode(try XCTUnwrap(o))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["level_dbfs_rel", "spread_db", "peaks_per_min", "duration_s", "tracking", "session_id"] {
            XCTAssertNotNil(json[key], key)
        }
    }
}
