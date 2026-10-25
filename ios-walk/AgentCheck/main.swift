import Foundation

let token = String(repeating: "a", count: 43)
let valid = URL(string: "quietcompass-walk://connect#pair=" + token)!
precondition(AgentProtocol.token(from: valid) == token)
for url in ["https://connect#pair=" + token, "quietcompass-walk://other#pair=" + token,
            "quietcompass-walk://connect?server=https://bad.example#pair=" + token,
            "quietcompass-walk://connect/path#pair=" + token,
            "quietcompass-walk://connect#pair=short", "quietcompass-walk://connect#pair=" + token + "&pair=" + token] {
    precondition(AgentProtocol.token(from: URL(string: url)!) == nil)
}
precondition(AgentProtocol.date("2026-10-24T21:00:00.000Z") != nil)
precondition(AgentProtocol.date("invalid") == nil)
let walk = AgentWalk(startedAt: "2026-10-24T21:00:00Z", captureProfile: "ios-walk-v1:test:48000:1",
                     samples: [WalkSample(t: 2, x: 1, z: 0, levelDBFS: -35, tracking: "normal")],
                     clippingDetected: false, dominantSound: nil)
let data = try AgentClient.encode(AgentWalkResult(requestId: "issued-job", walk: walk, error: nil))
let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let encoded = body["walk"] as! [String: Any]
let sample = (encoded["samples"] as! [[String: Any]])[0]
precondition(body["request_id"] as? String == "issued-job")
precondition(encoded["capture_profile"] as? String == "ios-walk-v1:test:48000:1")
precondition(sample["level_dbfs"] as? Double == -35)
precondition(Set(sample.keys) == ["t", "x", "z", "level_dbfs", "tracking"])
let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
let reply = try decoder.decode(AgentReply.self, from: Data("{\"status\":\"measure\",\"request_id\":\"job\",\"duration_seconds\":60,\"mode\":\"walk\"}".utf8))
precondition(reply.requestId == "job" && reply.durationSeconds == 60 && reply.mode == "walk")
print("PASS: app link validation, timestamps, native JSON contract and command decoding")
