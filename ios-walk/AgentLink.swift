import AVFoundation
import Foundation
import Observation

@MainActor @Observable
final class AgentLink {
    var hasLink = false
    var connected = false
    var connecting = false
    var message = ""
    var advice: AgentAdvice?
    var lastRequestId: String?
    var secondsLeft = 0
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let client = AgentClient()
    @ObservationIgnored private var generation = 0

    func receive(_ url: URL, model: CompassModel) {
        guard let next = AgentProtocol.token(from: url) else {
            message = "Invalid agent link. Open a fresh link from your agent."
            return
        }
        disconnect(model: model)
        token = next; hasLink = true; advice = nil; lastRequestId = nil
        message = "Allow your agent to analyze sound and your private room map for up to 15 minutes."
    }

    func connect(model: CompassModel) {
        guard hasLink, let token, !connecting, !connected else { return }
        connecting = true
        generation += 1; let current = generation
        task = Task {
            do {
                // Explicit button approval precedes both OS permissions and server consent.
                guard await AVCaptureDevice.requestAccess(for: .audio),
                      await AVCaptureDevice.requestAccess(for: .video) else {
                    throw AgentConnectionError("Microphone and camera access are needed to map this room.")
                }
                try Task.checkCancellation()
                await model.start()
                guard model.stream.sessionRunning else { throw AgentConnectionError("The microphone could not start.") }
                try Task.checkCancellation()
                let approval = Data("{\"microphone_consent\":true,\"spatial_consent\":true}".utf8)
                let ready = try await client.call("native-consent", token: token, body: approval)
                guard let stamp = ready.expiresAt, let expires = AgentProtocol.date(stamp), expires > Date() else {
                    throw AgentConnectionError("This connection expired.")
                }
                guard current == generation else { return }
                connecting = false; connected = true; message = "Connected. Waiting for your agent."
                while !Task.isCancelled, Date() < expires {
                    let reply = try await client.call("native-poll", token: token)
                    try Task.checkCancellation()
                    advice = reply.recommendation
                    if reply.status == "measure" {
                        guard reply.mode == "walk", let id = reply.requestId, let duration = reply.durationSeconds,
                              (30...180).contains(duration), Date().addingTimeInterval(Double(duration)) < expires else {
                            throw AgentConnectionError("Invalid or expired analysis request.")
                        }
                        advice = nil; lastRequestId = id
                        model.beginAgentWalk()
                        let rate = model.stream.sampleRate, channels = model.stream.channelCount
                        let profile = "ios-walk-v1:\(UUID().uuidString):\(Int(rate)):\(channels)"
                        let start = Date()
                        while Date().timeIntervalSince(start) < Double(duration) {
                            try await Task.sleep(for: .seconds(2))
                            try Task.checkCancellation()
                            guard Date() < expires else { throw AgentConnectionError("Connection expired.") }
                            secondsLeft = max(0, duration - Int(Date().timeIntervalSince(start)))
                            message = "Agent analyzing · \(secondsLeft) s left. Walk slowly, camera forward."
                            if secondsLeft % 10 < 2 { _ = try await client.call("native-poll", token: token) }
                        }
                        model.stopWalk()
                        let upload: AgentWalk?
                        if let walk = model.walk, walk.samples.count >= 3, !model.agentClipped,
                           model.stream.sampleRate == rate, model.stream.channelCount == channels {
                            upload = AgentWalk(startedAt: walk.startedAt, captureProfile: profile,
                                               samples: walk.samples.filter { $0.t <= Double(duration) },
                                               clippingDetected: false,
                                               dominantSound: model.radarFromARKit && channels >= 4 && (model.estimate?.confidence ?? 0) >= 0.5
                                                   ? model.estimate.map { AgentDirection(bearingDegrees: ($0.bearingWorld + 360).truncatingRemainder(dividingBy: 360), confidence: $0.confidence) } : nil)
                        } else { upload = nil }
                        let result = AgentWalkResult(requestId: id, walk: upload, error: upload == nil ? "capture_failed" : nil)
                        let body = try AgentClient.encode(result)
                        var delivered = false
                        for attempt in 0..<3 {
                            do {
                                _ = try await client.call("native-result", token: token, body: body)
                                delivered = true; break
                            } catch {
                                try Task.checkCancellation()
                                if attempt == 2 { throw error }
                                try await Task.sleep(for: .seconds(2))
                            }
                        }
                        message = delivered && upload != nil ? "Analysis sent. Waiting for your agent's recommendation." : "Tracking or audio was incomplete. Your agent can try again."
                        secondsLeft = 0
                    }
                    try await Task.sleep(for: .seconds(2))
                }
                if current == generation { disconnect(model: model); message = "Connection expired. Sensors off." }
            } catch {
                if current == generation {
                    disconnect(model: model)
                    message = error is CancellationError ? "Disconnected. Sensors off." : error.localizedDescription
                }
            }
        }
    }

    func disconnect(model: CompassModel) {
        generation += 1; task?.cancel(); task = nil
        let old = token; token = nil
        connected = false; connecting = false; hasLink = false; advice = nil; secondsLeft = 0
        model.stopSensors()
        message = "Disconnected. Microphone and camera off."
        if let old { Task { _ = try? await client.call("disconnect", token: old) } }
    }
}
