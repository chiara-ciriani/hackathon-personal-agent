import AVFoundation
import Observation
import struct QuietCore.PhoneServer
import class QuietCore.PhoneOutbox
import struct QuietCore.HealthSummary
import struct QuietCore.Session
import struct QuietCore.Place
import struct QuietCore.Guidance
import struct QuietCore.PoseSample
import struct QuietCore.BreadcrumbRecorder
import struct QuietCore.Crumb
import struct QuietCore.Route
import struct QuietCore.SessionUpsert
import struct QuietCore.ObservationBatch
import struct QuietCore.CrumbBatch
import struct QuietCore.PlaceBatch
import struct QuietCore.GuidanceStatusUpdate
import struct QuietCore.PlaceLocator
import enum QuietCore.PhoneError
import enum QuietCore.PlaceTag
import enum QuietCore.RouteBack
import enum QuietCore.ContractJSON
import class QuietCore.ObservationAggregator
import struct QuietCore.NoiseAlertMonitor
import struct QuietCore.NoiseAlert
import UIKit

@MainActor @Observable
final class CompassModel {
    var serverAddress = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
    var token = ""
    var message = "Connect your private server to begin."
    var running = false
    var starting = false
    var pending = 0
    var level: Double?
    var tracking = "Not tracking"
    var places: [Place] = []
    var placeLabel = ""
    var seating = false
    var stepFree = false
    var guidance: Guidance?
    var direction = ""
    var healthPreview: HealthSummary?
    var wearableText = "No wearable data loaded."
    var wearableBusy = false
    var canConnectOura = false
    var ouraConnected = false
    // Noise alerts (docs/BACKGROUND_CAPTURE_AND_NOISE_ALERTS.md).
    var alertsOn = UserDefaults.standard.object(forKey: "alertsOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(alertsOn, forKey: "alertsOn") }
    }
    /// How many dB above the comfortable level counts as too loud.
    var sensitivityDb = UserDefaults.standard.object(forKey: "sensitivityDb") as? Double ?? 10 {
        didSet { UserDefaults.standard.set(sensitivityDb, forKey: "sensitivityDb"); monitor.settings.offsetDb = sensitivityDb }
    }
    var lastAlert: String?
    var hasBaseline = false
    /// True after the app went to the background: sound keeps being measured, path tracking has ended.
    var levelsOnly = false
    private var monitor = NoiseAlertMonitor()
    private var lastObservationLevel: Double?
    private let notifier = NoiseNotifier()
    private var server: PhoneServer?
    private var outbox: PhoneOutbox?
    private let health = HealthReader()
    private var session: Session?
    private var source: MonoFeatureSource?
    private var tracker: PathTracker?
    private var pose: PoseSample?
    private var recorder: BreadcrumbRecorder?
    private var crumbs: [Crumb] = []
    private var route: QuietCore.Route?
    private var lastNormal = Date()
    private var startTask: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var stopping = false

    init() {
        do {
            token = try Credentials.read()
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            outbox = try PhoneOutbox(directory: folder.appendingPathComponent("PendingMeasurements"))
            if !serverAddress.isEmpty, !token.isEmpty { server = try PhoneServer(origin: serverAddress, token: token) }
        } catch { message = error.localizedDescription }
    }

    func saveConnection() async {
        guard !running, !starting, !stopping else { return }
        do {
            let address = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            let savedToken = token
            let candidate = try PhoneServer(origin: address, token: savedToken)
            if let server, server.origin != candidate.origin, await outbox?.count ?? 0 > 0 {
                throw PhoneError.message("Sync the pending measurements before changing servers.")
            }
            _ = try await candidate.request("/v1/wearables/context")
            try Credentials.save(savedToken)
            UserDefaults.standard.set(address, forKey: "serverAddress")
            serverAddress = address; token = savedToken; server = candidate
            message = "Server connected."
            await sync()
            await refreshWearables()
        } catch { message = error.localizedDescription }
    }

    func start() {
        guard !running, !starting, !stopping else { return }
        starting = true
        startTask = Task {
            defer { starting = false }
            do {
                guard let server, let outbox else { throw PhoneError.message("Save a server connection first.") }
                guard await AudioSessionConfigurator.requestRecordPermission() else { throw PhoneError.message("Allow microphone access in Settings to measure sound.") }
                try Task.checkCancellation()
                guard await AVCaptureDevice.requestAccess(for: .video) else { throw PhoneError.message("Allow camera access in Settings to track the walked path.") }
                try Task.checkCancellation()
                if alertsOn { _ = await notifier.requestPermission() }
                var settings = NoiseAlertMonitor.Settings(); settings.offsetDb = sensitivityDb
                monitor = NoiseAlertMonitor(settings: settings); hasBaseline = false; lastAlert = nil
                lastObservationLevel = nil; levelsOnly = false
                let source = MonoFeatureSource(classifier: SoundClassifier())
                self.source = source
                let frames = source.frames()
                try await source.start()
                try Task.checkCancellation()
                let result = source.sessionResult
                let session = Session(name: "Phone recording", deviceProfile: .init(model: UIDevice.current.model,
                    osVersion: UIDevice.current.systemVersion, captureMode: .arLevels,
                    audioSessionMode: result?.mode ?? "unknown", sampleRateHz: Int(result?.sampleRate ?? 48000), appVersion: "0.2"))
                try await outbox.enqueue(SessionUpsert(session: session), path: "/v1/sessions/\(session.id)", method: "PUT", server: server)
                self.session = session; places = []; crumbs = []; pose = nil
                recorder = BreadcrumbRecorder(sessionId: session.id)
                guidance = nil; route = nil; direction = ""; level = nil; lastNormal = Date()
                let tracker = PathTracker(onPose: { [weak self] pose in self?.received(pose) }, onFailure: { [weak self] text in
                    self?.trackingFailed(text)
                })
                self.tracker = tracker
                try tracker.start()
                running = true; message = "Measuring. You can lock the phone or switch apps and sound keeps being measured; path tracking needs the app open. Raw audio and images stay off disk."
                let aggregator = ObservationAggregator(sessionId: session.id)
                frameTask = Task {
                    for await frame in frames {
                        guard !Task.isCancelled, running else { break }
                        level = frame.levelDbfs
                        let recentPose = pose.flatMap { Date().timeIntervalSince($0.t) < 2 ? $0 : nil }
                        await aggregator.updatePose(recentPose)
                        if var observation = await aggregator.ingest(frame) {
                            observation.placeId = PlaceLocator(places: places).nearestPlace(to: observation.position)?.id
                            observation.crumbId = observation.position == nil ? nil : crumbs.last?.id
                            lastObservationLevel = NoiseAlertMonitor.level(of: observation)
                            handle(monitor.ingest(observation))
                            do { try await outbox.enqueue(ObservationBatch(observations: [observation]), path: "/v1/observations", server: server) }
                            catch { message = error.localizedDescription; Task { await self.stop() }; break }
                        }
                    }
                }
                syncTask = Task {
                    while !Task.isCancelled, running {
                        await sync()
                        await pollGuidance()
                        try? await Task.sleep(for: .seconds(3))
                    }
                }
            } catch {
                tracker?.stop(); tracker = nil
                await source?.stop(); source = nil; AudioSessionConfigurator.deactivate()
                if !(error is CancellationError) { message = error.localizedDescription }
            }
        }
    }

    func stop() async {
        guard !stopping else { return }
        stopping = true
        defer { stopping = false }
        startTask?.cancel()
        await startTask?.value
        startTask = nil
        running = false
        tracker?.stop(); tracker = nil
        frameTask?.cancel(); syncTask?.cancel()
        await source?.stop(); source = nil
        await frameTask?.value; frameTask = nil
        await syncTask?.value; syncTask = nil
        AudioSessionConfigurator.deactivate()
        levelsOnly = false
        tracking = "Stopped"; pose = nil; route = nil; direction = "Recording stopped. Start a new session before following a route."
        await sync()
    }

    // MARK: Background capture and noise alerts

    /// The app went to the background. ARKit can't run there, so the path ends; the mic keeps measuring.
    func enterBackground() async {
        guard running else { await stop(); return }
        endTracking("Measuring sound in the background. Path tracking ended; start a new recording to track a path again.")
        source?.setClassifierPaused(true)
    }

    func enterForeground() {
        source?.setClassifierPaused(false)
    }

    /// ARKit is interrupted when the app leaves the foreground. That ends the path, not the session.
    private func trackingFailed(_ text: String) {
        if UIApplication.shared.applicationState != .active {
            endTracking("Measuring sound in the background. Path tracking ended; start a new recording to track a path again.")
        } else {
            message = text
            Task { await stop() }
        }
    }

    private func endTracking(_ text: String) {
        guard running, !levelsOnly else { return }
        tracker?.stop(); tracker = nil; pose = nil
        levelsOnly = true; tracking = "Ended (sound only)"; message = text
        updateDirection()
    }

    private func handle(_ alert: NoiseAlert?) {
        hasBaseline = monitor.baselineDb != nil
        guard alertsOn, let alert else { return }
        lastAlert = NoiseNotifier.text(for: alert)
        notifier.post(alert)
    }

    /// "This feels comfortable": the latest 5 s level becomes the baseline.
    func markComfortable() {
        guard let lastObservationLevel else { message = "Wait a few seconds for the first measurement."; return }
        monitor.setBaseline(lastObservationLevel); hasBaseline = true
        message = "Got it. You'll be alerted when it gets about \(Int(sensitivityDb)) dB louder than this for a while."
    }

    func snoozeAlerts() {
        monitor.snooze(until: Date().addingTimeInterval(30 * 60))
        message = "Noise alerts snoozed for 30 minutes."
    }

    private func received(_ pose: PoseSample) {
        guard running else { return }
        self.pose = pose; tracking = pose.tracking.rawValue
        if pose.tracking == .normal { lastNormal = Date() }
        if Date().timeIntervalSince(lastNormal) > 30 {
            message = "Tracking was lost. Start a new recording so old and new paths are not mixed."
            Task { await stop() }; return
        }
        if let crumb = recorder?.ingest(pose), let outbox, let server {
            crumbs.append(crumb)
            Task {
                do { try await outbox.enqueue(CrumbBatch(crumbs: [crumb]), path: "/v1/crumbs", server: server) }
                catch { message = error.localizedDescription; await stop() }
            }
        }
        updateDirection()
    }

    func markPlace() async {
        let label = placeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard running, let session, let pose, pose.tracking == .normal, let position = pose.position,
              Date().timeIntervalSince(pose.t) < 2, let server, let outbox, !label.isEmpty, label.count <= 160 else {
            message = "Wait for normal tracking and enter a place name (up to 160 characters)."; return
        }
        let tags: [PlaceTag] = (seating ? [.seating] : []) + (stepFree ? [.stepFree] : [])
        let place = Place(sessionId: session.id, label: label, position: position, crumbId: crumbs.last?.id, tags: tags)
        do {
            try await outbox.enqueue(PlaceBatch(places: [place]), path: "/v1/places", server: server)
            places.append(place); placeLabel = ""; message = "Place saved. Stay here for 30 seconds to measure it."
        } catch { message = error.localizedDescription }
    }

    func sync() async {
        guard let server, let outbox else { return }
        do { try await outbox.flush(to: server) } catch { message = error.localizedDescription }
        pending = await outbox.count
    }

    private func pollGuidance() async {
        guard running, let session, let server else { return }
        do {
            let data = try await server.request("/v1/sessions/\(session.id)/guidance")
            if data.isEmpty { guidance = nil; route = nil; direction = ""; return }
            let next = try ContractJSON.decoder().decode(Guidance.self, from: data)
            if next != guidance {
                guidance = next
                if let place = places.first(where: { $0.id == next.targetPlaceId }), let target = place.position {
                    route = RouteBack.route(crumbs: crumbs, to: target, targetCrumbId: place.crumbId, current: pose?.position)
                } else { route = nil }
            }
            updateDirection()
        } catch { message = error.localizedDescription }
    }

    private func updateDirection() {
        guard guidance != nil else { return }
        guard running, let pose, pose.tracking == .normal, Date().timeIntervalSince(pose.t) < 2,
              let position = pose.position else { direction = "Tracking unavailable. Pause guidance."; return }
        guard let route, let next = RouteBack.nextTurn(on: route, from: position, headingRad: pose.headingRad) else {
            direction = "No recorded route to this place."; return
        }
        if route.isPartial { direction = "This route has a tracking gap. The full path is unavailable."; return }
        direction = next.hasArrived ? "Near the marked place. Confirm when you arrive." :
            "\(next.instruction?.phrase ?? "Hold the phone upright") · \(Int(next.remainingM)) m remaining"
    }

    func finishGuidance(_ status: Guidance.Status) async {
        guard let session, let server, let outbox else { return }
        do {
            try await outbox.enqueue(GuidanceStatusUpdate(status: status), path: "/v1/sessions/\(session.id)/guidance/status", server: server)
            guidance = nil; route = nil; direction = ""; await sync()
        } catch { message = error.localizedDescription }
    }

    func previewHealth() async {
        wearableBusy = true; defer { wearableBusy = false }
        do { healthPreview = try await health.preview() }
        catch { message = error.localizedDescription }
    }
    func shareHealth() async {
        guard let server, let preview = healthPreview else { return }
        wearableBusy = true; defer { wearableBusy = false }
        do {
            _ = try await server.request("/v1/wearables/apple-health", method: "PUT", body: ContractJSON.encoder().encode(preview))
            healthPreview = nil; message = "Daily summary shared with your private server."
            await refreshWearables()
        } catch { message = error.localizedDescription }
    }
    func connectOura() async -> URL? {
        guard let server else { return nil }
        wearableBusy = true; defer { wearableBusy = false }
        do {
            struct Link: Decodable { let connection_url: URL }
            let data = try await server.request("/v1/wearables/oura/link", method: "POST")
            let url = try JSONDecoder().decode(Link.self, from: data).connection_url
            guard url.scheme == server.origin.scheme, url.host == server.origin.host, url.port == server.origin.port else {
                throw PhoneError.message("The Oura connection URL does not match this server.")
            }
            return url
        } catch { message = error.localizedDescription; return nil }
    }
    func syncOura() async {
        guard let server else { return }
        wearableBusy = true; defer { wearableBusy = false }
        do { _ = try await server.request("/v1/wearables/oura/sync", method: "POST"); await refreshWearables() }
        catch { message = error.localizedDescription }
    }
    func refreshWearables() async {
        guard let server else { return }
        do {
            let data = try await server.request("/v1/wearables/context")
            struct Context: Decodable {
                let status: String
                let sources: [String: HealthSummary]
                let oura_configured: Bool?
                let oura_connected: Bool?
            }
            let context = try ContractJSON.decoder().decode(Context.self, from: data)
            canConnectOura = context.oura_configured ?? false; ouraConnected = context.oura_connected ?? false
            wearableText = context.sources.sorted { $0.key < $1.key }.map { source, summary in
                "\(source): \(summary.metrics.map { "\($0.name): \($0.value.formatted()) \($0.unit) (\($0.day))" }.joined(separator: ", "))"
            }.joined(separator: "\n")
            if wearableText.isEmpty { wearableText = context.status == "not_configured" ? "Private wearable storage needs configuration on the server." : "No summaries shared yet. Missing data is unknown." }
        } catch { message = error.localizedDescription }
    }
    func disconnect(_ source: String) async {
        guard let server else { return }
        wearableBusy = true; defer { wearableBusy = false }
        do {
            let data = try await server.request("/v1/wearables/\(source)", method: "DELETE")
            struct Result: Decodable { let message: String }
            message = try JSONDecoder().decode(Result.self, from: data).message
            if source == "apple_health" { healthPreview = nil }
            await refreshWearables()
        } catch { message = error.localizedDescription }
    }
}
