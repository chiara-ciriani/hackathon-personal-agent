import XCTest
@testable import QuietCore

final class NoiseAlertTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Observation number `i` ends at t0 + 5(i+1) s.
    private func obs(_ i: Int, level: Double, peaks: Double = 0, gapS: Double = 0) -> Observation {
        Observation(sessionId: UUID(), t: t0.addingTimeInterval(Double(i + 1) * 5 + gapS), durationS: 5,
                    position: nil, crumbId: nil, placeId: nil, levelDbfsRel: level + 2, levelAwDbfsRel: level,
                    spreadDb: 0, peaksPerMin: peaks, bandsDb: nil, speechShare: nil, classes: [], doa: nil,
                    tracking: .none)
    }

    private func run(_ m: inout NoiseAlertMonitor, _ observations: [Observation]) -> [NoiseAlert] {
        observations.compactMap { m.ingest($0) }
    }

    func testFirstObservationBecomesBaselineAndUsesAWeighting() {
        var m = NoiseAlertMonitor()
        XCTAssertNil(m.ingest(obs(0, level: -50)))
        XCTAssertEqual(m.baselineDb, -50)
        XCTAssertEqual(m.thresholdDb, -40)
    }

    func testSustainedLoudnessAlertsAfterThirtySeconds() {
        var m = NoiseAlertMonitor(baselineDb: -50)
        // Five loud observations cover 25 s: not yet.
        XCTAssertTrue(run(&m, (0..<5).map { obs($0, level: -35) }).isEmpty)
        let alert = m.ingest(obs(5, level: -35))
        guard case .sustainedLevel(let over, let seconds)? = alert?.reason else { return XCTFail("expected an alert") }
        XCTAssertEqual(over, 15, accuracy: 1e-9)
        XCTAssertEqual(seconds, 30, accuracy: 1e-9)
    }

    func testBriefLoudnessDoesNotAlert() {
        var m = NoiseAlertMonitor(baselineDb: -50)
        let levels: [Double] = [-35, -35, -35, -45, -35, -35, -35]
        XCTAssertTrue(run(&m, levels.enumerated().map { obs($0.offset, level: $0.element) }).isEmpty)
    }

    func testPeaksAlertWithoutLoudness() {
        var m = NoiseAlertMonitor(baselineDb: -50)
        let alert = m.ingest(obs(0, level: -48, peaks: 25))
        XCTAssertEqual(alert?.reason, .peaks(perMinute: 25))
    }

    func testCooldownAndRearm() {
        var settings = NoiseAlertMonitor.Settings()
        settings.cooldownS = 60
        var m = NoiseAlertMonitor(settings: settings, baselineDb: -50)
        XCTAssertEqual(run(&m, (0..<6).map { obs($0, level: -35) }).count, 1)
        // Still loud: no repeat while not re-armed, even after the cooldown.
        XCTAssertTrue(run(&m, (6..<30).map { obs($0, level: -35) }).isEmpty)
        // Dropping just under the threshold does not re-arm; well under does.
        XCTAssertNil(m.ingest(obs(30, level: -42)))
        XCTAssertNil(m.ingest(obs(31, level: -46)))
        XCTAssertEqual(run(&m, (32..<38).map { obs($0, level: -35) }).count, 1)
    }

    func testCooldownBlocksQuickRepeats() {
        var m = NoiseAlertMonitor(baselineDb: -50) // 10 min cooldown
        XCTAssertEqual(run(&m, (0..<6).map { obs($0, level: -35) }).count, 1)
        XCTAssertNil(m.ingest(obs(6, level: -60)))  // re-armed
        XCTAssertTrue(run(&m, (7..<13).map { obs($0, level: -35) }).isEmpty) // but within 10 min
    }

    func testSnooze() {
        var m = NoiseAlertMonitor(baselineDb: -50)
        m.snooze(until: t0.addingTimeInterval(1000))
        XCTAssertTrue(run(&m, (0..<10).map { obs($0, level: -35) }).isEmpty)
    }

    func testGapRestartsSustainTimer() {
        var m = NoiseAlertMonitor(baselineDb: -50)
        XCTAssertTrue(run(&m, (0..<4).map { obs($0, level: -35) }).isEmpty)
        // 60 s interruption, then only 20 s more of loudness.
        XCTAssertTrue(run(&m, (4..<8).map { obs($0, level: -35, gapS: 60) }).isEmpty)
        XCTAssertNotNil(m.ingest(obs(9, level: -35, gapS: 60)))
    }

    func testNewBaselineResets() {
        var m = NoiseAlertMonitor(baselineDb: -50)
        XCTAssertTrue(run(&m, (0..<4).map { obs($0, level: -35) }).isEmpty)
        m.setBaseline(-35) // "this feels comfortable"
        XCTAssertTrue(run(&m, (4..<20).map { obs($0, level: -35) }).isEmpty)
    }
}
