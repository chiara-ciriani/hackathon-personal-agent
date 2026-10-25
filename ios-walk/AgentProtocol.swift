import Foundation

/// Only the short-lived phone capability crosses the app link; no account API key.
nonisolated enum AgentProtocol {
    static let origin = URL(string: "https://quiet-compass-navy.vercel.app")!
    static func token(from url: URL) -> String? {
        guard url.scheme == "quietcompass-walk", url.host == "connect", url.path.isEmpty,
              url.query == nil, url.user == nil, url.password == nil, url.port == nil,
              let fragment = url.fragment,
              let fields = URLComponents(string: "https://local/?" + fragment)?.queryItems,
              fields.count == 1, fields[0].name == "pair", let token = fields[0].value,
              token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return nil }
        return token
    }
    static func date(_ value: String) -> Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

nonisolated struct AgentDestination: Decodable, Sendable {
    let x: Double
    let z: Double
    let requestId: String
    let kind: String
}
nonisolated struct AgentAdvice: Decodable, Sendable {
    let message: String
    let action: String
    let expiresAt: String
    let destination: AgentDestination?
}
nonisolated struct AgentReply: Decodable, Sendable {
    let status: String
    let expiresAt: String?
    let requestId: String?
    let durationSeconds: Int?
    let mode: String?
    let recommendation: AgentAdvice?
}
nonisolated struct AgentDirection: Encodable, Sendable {
    let bearingDegrees: Double
    let confidence: Double
}
nonisolated struct AgentWalk: Encodable, Sendable {
    let startedAt: String
    let captureProfile: String
    let samples: [WalkSample]
    let clippingDetected: Bool
    let dominantSound: AgentDirection?
    let location: AgentLocationPoint?
}
nonisolated struct AgentLocationPoint: Codable, Sendable {
    let lat: Double
    let lon: Double
}
nonisolated struct AgentNativeConsent: Encodable, Sendable {
    let microphoneConsent: Bool
    let spatialConsent: Bool
    let locationConsent: Bool
    let shareConsent: Bool
}
nonisolated struct AgentWalkResult: Encodable, Sendable {
    let requestId: String
    let walk: AgentWalk?
    let error: String?
}
nonisolated final class NoAgentRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
nonisolated struct AgentConnectionError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
nonisolated final class AgentClient: Sendable {
    private let session = URLSession(configuration: .ephemeral, delegate: NoAgentRedirect(), delegateQueue: nil)
    func call(_ action: String, token: String, body: Data = Data("{}".utf8)) async throws -> AgentReply {
        var request = URLRequest(url: AgentProtocol.origin.appendingPathComponent("api/phone/" + action))
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AgentConnectionError("Connection unavailable or expired. Reopen a new link from your agent.")
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AgentReply.self, from: data)
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(value)
    }
}
