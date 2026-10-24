// Features layered on CompassModel without changing its capture/outbox/guidance core:
//   - capture mode choice (A = FOA + ARKit, C = mono + ARKit) and the classifier toggle
//   - Simulator mocks (synthesized frames, scripted walk)
//   - live level in words relative to the session median, and the 30 s dwell indicator
//   - last level per place for the place list and the minimap
//   - opt-in shared contributions (POST /v1/contributions)
//   - the hour-0 spike tests and a /healthz ping for Diagnostics
// CompassModel owns one instance (`model.companion`); CompassModel+Companion.swift feeds it.
import Foundation
import Observation
import QuietCore

/// Anything CompassModel can start and stop as its path tracker (ARKit on a device, a scripted walk in the Simulator).
protocol PathTracking: AnyObject {
    @MainActor func start() throws
    @MainActor func stop()
}

extension PathTracker: PathTracking {}

@MainActor @Observable
final class CompanionFeatures {
    enum Key {
        static let captureMode = "qc.captureMode"
        static let classifierEnabled = "qc.classifierEnabled"
        static let shareContributions = "qc.shareContributions"
    }

    /// Modes the app can run end to end today. Mode B (zones, no AR) needs position-less places, which
    /// CompassModel.markPlace does not accept yet.
    // TODO: offer .spatialZones once places can be marked by zone label (PlaceLocator.place(inZone:) and
    // ZoneRoute.stepsBack already exist in QuietCore).
    static let selectableModes: [CaptureMode] = [.spatialAR, .arLevels]

    var captureMode: CaptureMode {
        didSet { UserDefaults.standard.set(captureMode.rawValue, forKey: Key.captureMode) }
    }

    /// On-device sound classes (speech, music, …). Takes effect at the next start.
    var classifierEnabled: Bool {
        didSet { UserDefaults.standard.set(classifierEnabled, forKey: Key.classifierEnabled) }
    }

    /// Opt-in, off by default: after each 30 s measured dwell at a marked place, share one anonymous summary.
    var shareContributions: Bool {
        didSet { UserDefaults.standard.set(shareContributions, forKey: Key.shareContributions) }
    }

    let spikeRunner = SpikeRunner()

    // MARK: Live state (read by the views)

    private(set) var sessionMedian: Double?
    private(set) var dwell = DwellCounter.Status(placeId: nil, seconds: 0)
    private(set) var lastObservationByPlace: [UUID: QuietCore.Observation] = [:]
    private(set) var lastContributionText: String?
    private(set) var feedbackCount = 0

    @ObservationIgnored private var baseline = SessionLevelBaseline()
    @ObservationIgnored private var dwellCounter = DwellCounter()
    @ObservationIgnored private var recent: [QuietCore.Observation] = []
    @ObservationIgnored private var windowMaxFrameLevel: Double?
    @ObservationIgnored private var lastLevel: Double?

    init(defaults: UserDefaults = .standard) {
        let stored = defaults.string(forKey: Key.captureMode).flatMap(CaptureMode.init(rawValue:))
        captureMode = stored.flatMap { Self.selectableModes.contains($0) ? $0 : nil } ?? .arLevels
        classifierEnabled = defaults.object(forKey: Key.classifierEnabled) as? Bool ?? true
        shareContributions = defaults.object(forKey: Key.shareContributions) as? Bool ?? false
    }

    var levelWords: String { LevelDescription.relative(lastLevel, median: sessionMedian) }
    var liveLevel: Double? { lastLevel }

    // MARK: Factories used by CompassModel.start()

    func makeSource() -> FeatureSource {
        #if targetEnvironment(simulator)
        return MockFeatureSource()
        #else
        // TODO: mode A world-frame directions need the ARKit camera rotation; set
        // FOAFeatureSource.deviceToWorld once PathTracker exposes it. Until then DOA stays in the device frame.
        return CaptureFactory.makeSource(mode: captureMode, classifierEnabled: classifierEnabled)
        #endif
    }

    func makeTracker(onPose: @escaping @MainActor @Sendable (PoseSample) -> Void,
                     onFailure: @escaping @MainActor @Sendable (String) -> Void) -> PathTracking {
        #if targetEnvironment(simulator)
        return MockPathTracker(onPose: onPose)
        #else
        return PathTracker(onPose: onPose, onFailure: onFailure)
        #endif
    }

    /// Audio session mode and sample rate for the DeviceProfile.
    static func audioSessionInfo(of source: FeatureSource) -> (mode: String, sampleRate: Double) {
        if let foa = source as? FOAFeatureSource, let r = foa.sessionResult { return (r.mode, r.sampleRate) }
        if let mono = source as? MonoFeatureSource, let r = mono.sessionResult { return (r.mode, r.sampleRate) }
        #if targetEnvironment(simulator)
        return ("simulated", 48_000)
        #else
        return ("unknown", 48_000)
        #endif
    }

    func beginSession() {
        baseline = SessionLevelBaseline()
        dwellCounter = DwellCounter()
        dwell = DwellCounter.Status(placeId: nil, seconds: 0)
        recent = []
        lastObservationByPlace = [:]
        lastContributionText = nil
        windowMaxFrameLevel = nil
        lastLevel = nil
        sessionMedian = nil
        feedbackCount = 0
        retryQueue = []
        attemptsById = [:]
    }

    // MARK: Inputs (from CompassModel+Companion)

    /// One 1 s frame. Returns a finished 30 s window at a place when one completes.
    func ingest(frame: FeatureFrame, placeId: UUID?) -> DwellCounter.Window? {
        lastLevel = frame.levelDbfs
        baseline.append(frame.levelDbfs)
        sessionMedian = baseline.count >= 10 ? baseline.median : nil
        let peak = frame.shortFrameLevelsDbfs.max() ?? frame.levelDbfs
        let (status, window, restarted) = dwellCounter.ingest(t: frame.t, placeId: placeId)
        if restarted { windowMaxFrameLevel = nil }
        windowMaxFrameLevel = max(windowMaxFrameLevel ?? peak, peak)
        dwell = status
        guard var window else { return nil }
        window.maxFrameLevelDbfs = windowMaxFrameLevel
        windowMaxFrameLevel = nil
        return window
    }

    func record(_ observation: QuietCore.Observation) {
        if let pid = observation.placeId { lastObservationByPlace[pid] = observation }
        recent.append(observation)
        let cutoff = observation.t.addingTimeInterval(-180)
        recent.removeAll { $0.t < cutoff }
    }

    /// Builds the contribution for a finished window (median of that place's observations in it).
    func contribution(for window: DwellCounter.Window, place: Place, profile: DeviceProfile) -> SharedContribution? {
        let samples = recent.filter { $0.placeId == place.id && $0.t > window.start && $0.t <= window.end.addingTimeInterval(5) }
            .map { SharedContribution.WindowSample(levelDbfs: $0.levelDbfsRel, spreadDb: $0.spreadDb,
                                                   peaksPerMin: $0.peaksPerMin, durationSeconds: $0.durationS) }
        #if targetEnvironment(simulator)
        let source: SharedContribution.Source = .simulated
        #else
        let source: SharedContribution.Source = .device
        #endif
        return SharedContribution.make(area: (id: SharedContribution.areaId(forPlace: place.id), name: place.label),
                                       endingAt: window.end, samples: samples,
                                       maxFrameLevelDbfs: window.maxFrameLevelDbfs,
                                       captureProfile: DeviceProfileBuilder.captureProfileLabel(profile),
                                       source: source)
    }

    func setContributionText(_ text: String) { lastContributionText = text }

    // MARK: Contribution retries (in memory; contributions are optional and never block the outbox)

    struct WaitingContribution: Sendable { var contribution: SharedContribution; var label: String; var attempts: Int }
    static let maxRetryQueue = 20
    static let maxAttempts = 3
    @ObservationIgnored private var retryQueue: [WaitingContribution] = []
    @ObservationIgnored private var attemptsById: [UUID: Int] = [:]

    /// Queues a failed contribution; returns false when it has used up its attempts.
    func keepForRetry(_ contribution: SharedContribution, label: String) -> Bool {
        let attempts = (attemptsById[contribution.id] ?? 0) + 1
        attemptsById[contribution.id] = attempts
        guard attempts < Self.maxAttempts else { return false }
        retryQueue.append(WaitingContribution(contribution: contribution, label: label, attempts: attempts))
        if retryQueue.count > Self.maxRetryQueue { retryQueue.removeFirst(retryQueue.count - Self.maxRetryQueue) }
        return true
    }

    /// Removes and returns the queued contributions; any that fail again come back through keepForRetry.
    func takeRetryableContributions() -> [WaitingContribution] {
        defer { retryQueue = [] }
        return retryQueue
    }

    // MARK: Diagnostics

    /// GET {origin}/healthz without a token (PhoneServer only sends /v1 paths).
    static func pingHealth(origin: URL) async -> String {
        var request = URLRequest(url: origin.appending(path: "healthz"))
        request.timeoutInterval = 10
        let start = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            struct Health: Decodable { var ok: Bool }
            guard code == 200, (try? JSONDecoder().decode(Health.self, from: data))?.ok == true else {
                return "The server answered \(code), not ok."
            }
            return String(format: "Server is up (%.0f ms)", Date().timeIntervalSince(start) * 1000)
        } catch {
            return "Can't reach the server: \(error.localizedDescription)"
        }
    }
}

/// Counts how long the user has stayed at the same marked place (or nowhere), from 1 s frames, and emits a
/// window every 30 s of uninterrupted dwell at a place. A gap of more than 3 s between frames restarts it,
/// matching ObservationAggregator.maximumGapSeconds.
struct DwellCounter: Sendable {
    struct Status: Sendable, Hashable {
        var placeId: UUID?
        var seconds: Double
        var confidence: MeasurementConfidence { MeasurementConfidence(dwellSeconds: seconds) }
        var targetSeconds: Double { MeasurementConfidence.okFromSeconds }
        /// "measuring 12 s / 30 s", or "measured 45 s" (same wording as QuietCore.DwellStatus).
        var label: String {
            confidence == .ok ? "measured \(Int(seconds)) s" : "measuring \(Int(seconds)) s / \(Int(targetSeconds)) s"
        }
    }

    struct Window: Sendable, Hashable {
        var placeId: UUID
        var start: Date
        var end: Date
        var maxFrameLevelDbfs: Double?
    }

    static let maximumGapSeconds = 3.0
    private var placeId: UUID?
    private var dwellStart: Date?
    private var windowStart: Date?
    private var lastT: Date?

    /// Returns the status, a finished window (if any), and whether the dwell restarted on this frame.
    mutating func ingest(t: Date, placeId pid: UUID?) -> (Status, Window?, Bool) {
        var restarted = false
        if let lastT, t.timeIntervalSince(lastT) > Self.maximumGapSeconds { dwellStart = nil }
        if dwellStart == nil || pid != placeId {
            placeId = pid
            dwellStart = t.addingTimeInterval(-1)   // the frame covers the second before t
            windowStart = dwellStart
            restarted = true
        }
        lastT = t
        let seconds = max(0, t.timeIntervalSince(dwellStart ?? t))
        var window: Window?
        if let pid, let ws = windowStart, t.timeIntervalSince(ws) >= MeasurementConfidence.okFromSeconds {
            window = Window(placeId: pid, start: ws, end: t, maxFrameLevelDbfs: nil)
            windowStart = t
        }
        return (Status(placeId: pid, seconds: seconds), window, restarted)
    }
}
