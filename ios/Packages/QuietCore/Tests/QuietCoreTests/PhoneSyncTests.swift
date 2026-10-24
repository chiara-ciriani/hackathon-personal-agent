import Foundation
import XCTest
@testable import QuietCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor Requests {
    var items: [URLRequest] = []
    var fail = true
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        items.append(request)
        if fail { throw URLError(.notConnectedToInternet) }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func succeed() { fail = false }
}

final class PhoneSyncTests: XCTestCase, @unchecked Sendable {
    func testOutboxSurvivesFailureRestartAndKeepsRecordIdentity() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let requests = Requests()
        let server = try PhoneServer(origin: "https://example.org", token: "private-token",
                                     send: { try await requests.send($0) })
        let session = Session(deviceProfile: .init(model: "test", osVersion: "26", captureMode: .arLevels,
                                                   audioSessionMode: "measurement", sampleRateHz: 48000, appVersion: "test"))
        let first = try PhoneOutbox(directory: folder)
        try await first.enqueue(SessionUpsert(session: session), path: "/v1/sessions/\(session.id)", method: "PUT", server: server)
        do { try await first.flush(to: server); XCTFail("Offline send succeeded") } catch {}
        let count = await first.count
        XCTAssertEqual(count, 1)
        let persisted = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let saved = try String(contentsOf: persisted[0], encoding: .utf8)
        XCTAssertFalse(saved.contains("private-token"))
        let restarted = try PhoneOutbox(directory: folder)
        await requests.succeed()
        try await restarted.flush(to: server)
        let remaining = await restarted.count
        XCTAssertEqual(remaining, 0)
        let sent = await requests.items
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0].httpBody, sent[1].httpBody)
        XCTAssertEqual(sent[1].url?.path, "/v1/sessions/\(session.id)")
        XCTAssertEqual(sent[1].value(forHTTPHeaderField: "Authorization"), "Bearer private-token")
    }

    func testOutboxCannotLeakDataToDifferentServer() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let requests = Requests()
        let first = try PhoneServer(origin: "https://first.example", token: "token")
        let other = try PhoneServer(origin: "https://other.example", token: "token", send: { try await requests.send($0) })
        let outbox = try PhoneOutbox(directory: folder)
        try await outbox.enqueue(["example": "private"], path: "/v1/places", server: first)
        do { try await outbox.flush(to: other); XCTFail("Cross-server send allowed") } catch {}
        let sent = await requests.items
        XCTAssertTrue(sent.isEmpty)
        let count = await outbox.count
        XCTAssertEqual(count, 1)
    }

    func testServerRequiresSecureOrigin() throws {
        for address in ["http://public.example", "https://user:pass@example.org", "https://example.org/path", "https://example.org?token=x"] {
            XCTAssertThrowsError(try PhoneServer(origin: address, token: "token"))
        }
        XCTAssertNoThrow(try PhoneServer(origin: "http://localhost:8000", token: "token"))
    }

    func testSleepStagesAndTwoDevicesAreNotDoubleCounted() {
        let start = Date(timeIntervalSince1970: 1000)
        func interval(_ a: Double, _ b: Double) -> DateInterval {
            DateInterval(start: start.addingTimeInterval(a), end: start.addingTimeInterval(b))
        }
        let seconds = SleepIntervals.seconds([interval(-100, 100), interval(0, 400), interval(100, 300),
                                              interval(500, 800), interval(750, 1200)], within: interval(0, 1000))
        XCTAssertEqual(seconds, 900)
        XCTAssertEqual(SleepIntervals.seconds([], within: interval(0, 1000)), 0)
    }
}
