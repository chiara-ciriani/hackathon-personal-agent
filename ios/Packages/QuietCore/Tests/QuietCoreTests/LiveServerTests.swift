import Foundation
import XCTest
@testable import QuietCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Opt-in local integration against the actual Python ASGI server. Uses synthetic data only.
final class LiveServerTests: XCTestCase, @unchecked Sendable {
    func testPhoneUploadAgentReadAndGuidanceRoundTrip() async throws {
        guard let origin = ProcessInfo.processInfo.environment["QC_TEST_SERVER_URL"] else {
            throw XCTSkip("Set QC_TEST_SERVER_URL to an isolated local test server.")
        }
        guard let url = URL(string: origin), url.host == "127.0.0.1" else {
            throw PhoneError.message("Integration test requires a loopback server, never production.")
        }
        let token = "synthetic-integration-token"
        let server = try PhoneServer(origin: origin, token: token)
        let session = Session(name: "SIMULATED integration", deviceProfile: .init(model: "synthetic", osVersion: "26",
            captureMode: .arLevels, audioSessionMode: "measurement", sampleRateHz: 48000, appVersion: "test"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let outbox = try PhoneOutbox(directory: folder)
        try await outbox.enqueue(SessionUpsert(session: session), path: "/v1/sessions/\(session.id)", method: "PUT", server: server)
        let place = Place(sessionId: session.id, label: "SIMULATED corner", position: .init(x: 0, z: 0), crumbId: nil)
        try await outbox.enqueue(PlaceBatch(places: [place]), path: "/v1/places", server: server)
        let observation = QuietCore.Observation(sessionId: session.id, t: Date(), durationS: 5, position: place.position,
            crumbId: nil, placeId: place.id, levelDbfsRel: -48, levelAwDbfsRel: nil, spreadDb: 4, peaksPerMin: 1,
            bandsDb: nil, speechShare: nil, classes: [], doa: nil, tracking: .normal)
        try await outbox.enqueue(ObservationBatch(observations: [observation]), path: "/v1/observations", server: server)
        try await outbox.flush(to: server)
        let remaining = await outbox.count
        XCTAssertEqual(remaining, 0)
        let summary = HealthSummary(capturedAt: Date(), metrics: [.init(name: "steps", value: 1234, unit: "count", day: "2026-10-23")], note: "Synthetic test")
        _ = try await server.request("/v1/wearables/apple-health", method: "PUT", body: ContractJSON.encoder().encode(summary))

        func tool(_ name: String, _ arguments: [String: String] = [:]) async throws -> [String: Any] {
            var request = URLRequest(url: url.appendingPathComponent("mcp"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                "params": ["name": name, "arguments": arguments]])
            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let result = try XCTUnwrap(object["result"] as? [String: Any])
            XCTAssertNotEqual(result["isError"] as? Bool, true)
            return try XCTUnwrap(result["structuredContent"] as? [String: Any])
        }
        let context = try await tool("quiet_get_context", ["response_format": "detailed"])
        XCTAssertEqual((context["now"] as? [String: Any])?["level_dbfs_rel"] as? Double, -48)
        let personal = try await tool("quiet_get_personal_context")
        XCTAssertNotNil((personal["sources"] as? [String: Any])?["apple_health"])
        _ = try await tool("quiet_start_guidance", ["place_id": place.id.uuidString.lowercased()])
        let guidance = try ContractJSON.decoder().decode(Guidance.self,
            from: await server.request("/v1/sessions/\(session.id)/guidance"))
        XCTAssertEqual(guidance.targetPlaceId, place.id)
        _ = try await server.request("/v1/sessions/\(session.id)/guidance/status", method: "POST",
                                     body: ContractJSON.encoder().encode(GuidanceStatusUpdate(status: .arrived)))
        let afterArrival = try await server.request("/v1/sessions/\(session.id)/guidance")
        XCTAssertTrue(afterArrival.isEmpty)
    }
}
