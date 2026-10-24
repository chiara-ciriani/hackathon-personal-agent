import XCTest
import QuietCore
@testable import QuietCompass

final class SharedContributionTests: XCTestCase {
    private func sample(_ level: Double, spread: Double = 6, peaks: Double? = 2) -> SharedContribution.WindowSample {
        .init(levelDbfs: level, spreadDb: spread, peaksPerMin: peaks, durationSeconds: 5)
    }

    func testCoordinatesRoundToThreeDecimals() {
        XCTAssertEqual(SharedContribution.roundCoordinate(37.774929), 37.775, accuracy: 1e-9)
        XCTAssertEqual(SharedContribution.roundCoordinate(-122.419416), -122.419, accuracy: 1e-9)
    }

    func testTimeBucketFloorsToFiveMinutesUTC() {
        // 2026-10-24T17:08:59.900Z → 17:05:00Z
        let date = Date(timeIntervalSince1970: 1_792_861_739.9)
        XCTAssertEqual(SharedContribution.bucketString(date), "2026-10-24T17:05:00Z")
        let exact = Date(timeIntervalSince1970: 1_792_861_500)
        XCTAssertEqual(SharedContribution.bucketString(exact), "2026-10-24T17:05:00Z")
    }

    func testMakeUsesMediansAndSumsDuration() throws {
        let c = try XCTUnwrap(SharedContribution.make(
            area: (id: "place:abc", name: "Courtyard"), endingAt: Date(),
            samples: [sample(-40), sample(-30, spread: 10, peaks: nil), sample(-50, spread: 2, peaks: 4),
                      sample(-35), sample(-45)],
            maxFrameLevelDbfs: -12, captureProfile: "iPhone17,1/mode-C/measurement", source: .device))
        XCTAssertEqual(c.measurement.rmsDbfs, -40)
        XCTAssertEqual(c.measurement.frameLevelSpreadDb, 6)
        XCTAssertEqual(c.measurement.peaksPerMin, 2)
        XCTAssertEqual(c.durationSeconds, 25)
        XCTAssertFalse(c.quality.clippingDetected)
        XCTAssertNil(SharedContribution.make(area: (id: "x", name: nil), endingAt: Date(), samples: [],
                                             maxFrameLevelDbfs: nil, captureProfile: "p", source: .device))
    }

    func testClippingFlag() throws {
        let c = try XCTUnwrap(SharedContribution.make(area: (id: "x", name: nil), endingAt: Date(), samples: [sample(-20)],
                                                      maxFrameLevelDbfs: -0.5, captureProfile: "p", source: .simulated))
        XCTAssertTrue(c.quality.clippingDetected)
    }

    func testEncodesExactlyTheAgreedFields() throws {
        let c = SharedContribution(areaId: "zone:courtyard", areaName: nil, time: Date(timeIntervalSince1970: 1_792_861_739),
                                   durationSeconds: 30,
                                   measurement: .init(rmsDbfs: -31.4, frameLevelSpreadDb: 8.2, peaksPerMin: nil),
                                   quality: .init(captureProfile: "p", clippingDetected: false), source: .simulated)
        let body = try ContractJSON.encoder().encode(ContributionSubmission(contribution: c))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["contract_version"] as? Int, 1)
        let obj = try XCTUnwrap(json["contribution"] as? [String: Any])
        XCTAssertEqual(Set(obj.keys), ["id", "schema_version", "area_id", "area_name", "lat", "lon", "time_bucket",
                                       "duration_seconds", "measurement", "quality", "source"])
        XCTAssertEqual(obj["schema_version"] as? String, "0.1")
        XCTAssertEqual(obj["time_bucket"] as? String, "2026-10-24T17:05:00Z")
        XCTAssertEqual(obj["source"] as? String, "simulated")
        XCTAssertTrue(obj["lat"] is NSNull)
        let m = try XCTUnwrap(obj["measurement"] as? [String: Any])
        XCTAssertEqual(Set(m.keys), ["kind", "rms_dbfs", "frame_level_spread_db", "peaks_per_min", "calibrated"])
        XCTAssertEqual(m["kind"] as? String, "relative_uncalibrated")
        XCTAssertEqual(m["calibrated"] as? Bool, false)
        let q = try XCTUnwrap(obj["quality"] as? [String: Any])
        XCTAssertEqual(Set(q.keys), ["capture_profile", "clipping_detected"])
    }

    func testAreaIds() {
        let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        XCTAssertEqual(SharedContribution.areaId(forPlace: id), "place:6f9619ff-8b86-d011-b42d-00c04fc964ff")
        XCTAssertEqual(SharedContribution.areaId(forZone: "  Café Courtyard (east) "), "zone:cafe-courtyard-east")
        XCTAssertEqual(SharedContribution.areaId(forZone: "!!!"), "zone:unnamed")
    }

    func testResultDecodes() throws {
        let data = Data(#"{"status":"withheld","reason":"needs 2 contributions","area_id":"place:x","time_bucket":"2026-10-24T17:05:00Z"}"#.utf8)
        let r = try JSONDecoder().decode(ContributionResult.self, from: data)
        XCTAssertEqual(r.status, .withheld)
        XCTAssertTrue(r.displayText.hasPrefix("Kept back"))
    }
}

final class DwellCounterTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testEmitsOneWindowPerThirtySecondsAtAPlace() {
        var counter = DwellCounter()
        let place = UUID()
        var windows: [DwellCounter.Window] = []
        for i in 1...65 {
            let (_, w, _) = counter.ingest(t: t0.addingTimeInterval(Double(i)), placeId: place)
            if let w { windows.append(w) }
        }
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].placeId, place)
    }

    func testNoWindowAwayFromPlacesAndRestartOnMove() {
        var counter = DwellCounter()
        for i in 1...40 { XCTAssertNil(counter.ingest(t: t0.addingTimeInterval(Double(i)), placeId: nil).1) }
        let (status, _, restarted) = counter.ingest(t: t0.addingTimeInterval(41), placeId: UUID())
        XCTAssertTrue(restarted)
        XCTAssertEqual(status.seconds, 1, accuracy: 1e-9)
        XCTAssertEqual(status.label, "measuring 1 s / 30 s")
    }

    func testGapRestartsDwell() {
        var counter = DwellCounter()
        let place = UUID()
        for i in 1...20 { _ = counter.ingest(t: t0.addingTimeInterval(Double(i)), placeId: place) }
        let (status, _, restarted) = counter.ingest(t: t0.addingTimeInterval(30), placeId: place)
        XCTAssertTrue(restarted)
        XCTAssertEqual(status.seconds, 1, accuracy: 1e-9)
    }
}

final class LevelDescriptionTests: XCTestCase {
    func testWordsRelativeToMedian() {
        XCTAssertEqual(LevelDescription.relative(-50, median: -40), "Much quieter than usual here")
        XCTAssertEqual(LevelDescription.relative(-40.5, median: -40), "About usual for this session")
        XCTAssertEqual(LevelDescription.relative(-36, median: -40), "A bit louder than usual here")
        XCTAssertEqual(LevelDescription.relative(nil, median: -40), "Listening…")
        XCTAssertEqual(LevelDescription.meterFraction(-40, median: -40), 0.5)
    }

    func testBaselineMedian() {
        var b = SessionLevelBaseline(capacity: 3)
        [-10.0, -20, -30, -40].forEach { b.append($0) }
        XCTAssertEqual(b.count, 3)
        XCTAssertEqual(b.median, -30)
    }

    func testCaptureProfileLabel() {
        XCTAssertEqual(DeviceProfileBuilder.captureProfileLabel(model: "iPhone17,1", captureMode: "C", audioSessionMode: "measurement"),
                       "iPhone17,1/mode-C/measurement")
    }
}
