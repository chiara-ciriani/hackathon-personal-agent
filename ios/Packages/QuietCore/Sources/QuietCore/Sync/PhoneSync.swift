import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PhoneError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

public struct PhoneServer: Sendable {
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public let origin: URL
    private let token: String
    private let send: Send

    public init(origin: String, token: String, send: Send? = nil) throws {
        guard let url = URL(string: origin), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)),
              !token.isEmpty, !token.contains("\n"), !token.contains("\r") else {
            throw PhoneError.message("Enter an HTTPS server address and its access token.")
        }
        var normalized = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        normalized.path = ""
        self.origin = normalized.url!
        self.token = token
        if let send { self.send = send } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
            self.send = { request in
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw PhoneError.message("Invalid server response.") }
                return (data, http)
            }
        }
    }

    public func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard path.hasPrefix("/v1/"), !path.contains("?"), !path.contains("#") else {
            throw PhoneError.message("Invalid server path.")
        }
        var request = URLRequest(url: origin.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw PhoneError.message(detail ?? "Server returned \(response.statusCode). Pending measurements are kept on this phone.")
        }
        return data
    }
}

/// Each request is written atomically before sending. A failed send leaves its UUIDs intact,
/// so the server can deduplicate a retry after a timeout or app restart. Tokens are never saved here.
public actor PhoneOutbox {
    private struct Entry: Codable {
        let destination: String
        let path: String
        let method: String
        let body: Data
    }
    private let directory: URL
    private var files: [URL]
    private var sequence: Int
    private var flushing = false

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        sequence = (files.compactMap { Int($0.deletingPathExtension().lastPathComponent) }.max() ?? 0) + 1
        var mutableDirectory = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try mutableDirectory.setResourceValues(values)
    }

    public var count: Int { files.count }

    public func enqueue<T: Encodable & Sendable>(_ body: T, path: String, method: String = "POST",
                                                  server: PhoneServer) throws {
        guard files.count < 10000 else { throw PhoneError.message("Pending storage is full. Reconnect to sync before measuring more.") }
        let entry = Entry(destination: server.origin.absoluteString, path: path, method: method,
                          body: try ContractJSON.encoder().encode(body))
        let file = directory.appendingPathComponent(String(format: "%012d.json", sequence))
        let data = try JSONEncoder().encode(entry)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        sequence += 1
        files.append(file)
    }

    public func flush(to server: PhoneServer) async throws {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        while let file = files.first {
            try Task.checkCancellation()
            let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: file))
            guard entry.destination == server.origin.absoluteString else {
                throw PhoneError.message("Pending data belongs to another server. Restore that server address to sync it.")
            }
            _ = try await server.request(entry.path, method: entry.method, body: entry.body)
            try FileManager.default.removeItem(at: file)
            files.removeFirst()
        }
    }
}
