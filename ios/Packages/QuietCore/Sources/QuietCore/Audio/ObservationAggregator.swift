// Aggregates 1 s FeatureFrames into 5 s Observations. Foundation only.
//
// Usage (app layer):
//   let agg = ObservationAggregator(sessionId: session.id,
//                                   placeLocator: { pos in store.placeId(near: pos) },
//                                   crumbLocator: { pos in tracker.latestCrumbId })
//   for await frame in source.frames() {
//       await agg.updatePose(tracker.latestPose)          // or call whenever a pose arrives
//       if let obs = await agg.ingest(frame) { outbox.enqueue(obs) }
//   }
// The locator closures are called on the actor; keep them cheap and thread-safe (@Sendable).
import Foundation

/// How long the user has been measuring the same place; the UI shows "measuring 12 s / 30 s".
public enum MeasurementConfidence: String, Sendable, Hashable {
    /// Under 15 s: too short to say anything.
    case low
    /// 15–30 s: indicative.
    case building
    /// 30 s or more: the rolling spread window is full.
    case ok

    public static let lowBelowSeconds: Double = 15
    public static let okFromSeconds: Double = 30

    public init(dwellSeconds s: Double) {
        self = s < Self.lowBelowSeconds ? .low : (s < Self.okFromSeconds ? .building : .ok)
    }
}

public struct DwellStatus: Sendable, Hashable {
    /// The place (or nil for "no place") the user has been in continuously.
    public var placeId: UUID?
    public var seconds: Double
    public var confidence: MeasurementConfidence
    /// Target for the progress display.
    public var targetSeconds: Double { MeasurementConfidence.okFromSeconds }
    /// e.g. "measuring 12 s / 30 s", or "measured 45 s".
    public var label: String {
        confidence == .ok ? "measured \(Int(seconds)) s" : "measuring \(Int(seconds)) s / \(Int(targetSeconds)) s"
    }
}

public actor ObservationAggregator {
    public typealias PlaceLocator = @Sendable (Position?) -> UUID?
    public typealias CrumbLocator = @Sendable (Position?) -> UUID?

    public let sessionId: UUID
    public let framesPerObservation: Int
    private let placeLocator: PlaceLocator
    private let crumbLocator: CrumbLocator

    private var stats = RollingStats()
    private var window: [FeatureFrame] = []
    private var latestPose: PoseSample?

    private var dwellPlaceId: UUID?
    private var dwellStart: Date?
    private var lastFrameTime: Date?
    /// A gap longer than this between frames resets dwell and the rolling stats.
    public let maximumGapSeconds: Double = 3

    public init(sessionId: UUID, framesPerObservation: Int = 5,
                placeLocator: @escaping PlaceLocator = { _ in nil },
                crumbLocator: @escaping CrumbLocator = { _ in nil }) {
        self.sessionId = sessionId
        self.framesPerObservation = max(1, framesPerObservation)
        self.placeLocator = placeLocator
        self.crumbLocator = crumbLocator
    }

    public func updatePose(_ pose: PoseSample?) {
        latestPose = pose
    }

    /// Adds one 1 s frame; returns an Observation every `framesPerObservation` frames.
    public func ingest(_ frame: FeatureFrame) -> Observation? {
        if let last = lastFrameTime, frame.t.timeIntervalSince(last) > maximumGapSeconds {
            stats.reset()
            window.removeAll()
            dwellStart = nil
        }
        lastFrameTime = frame.t
        stats.append(contentsOf: frame.shortFrameLevelsDbfs)
        window.append(frame)

        let tracking: TrackingState = latestPose?.tracking ?? TrackingState.none
        let position = tracking == .normal ? latestPose?.position : nil
        let placeId = placeLocator(position)
        if dwellStart == nil || placeId != dwellPlaceId {
            dwellPlaceId = placeId
            dwellStart = frame.t.addingTimeInterval(-1)   // the frame covers the second before t
        }

        guard window.count >= framesPerObservation else { return nil }
        defer { window.removeAll(keepingCapacity: true) }
        return makeObservation(window, position: position, placeId: placeId, tracking: tracking)
    }

    /// How long the user has been at `placeId` (nil = current place, whatever it is).
    public func currentDwell(placeId: UUID? = nil) -> DwellStatus {
        guard let start = dwellStart, let last = lastFrameTime else {
            return DwellStatus(placeId: placeId ?? dwellPlaceId, seconds: 0, confidence: .low)
        }
        if let placeId, placeId != dwellPlaceId {
            return DwellStatus(placeId: placeId, seconds: 0, confidence: .low)
        }
        let s = max(0, last.timeIntervalSince(start))
        return DwellStatus(placeId: dwellPlaceId, seconds: s, confidence: MeasurementConfidence(dwellSeconds: s))
    }

    /// Restarts dwell (e.g. when the user taps "measure here").
    public func resetDwell() {
        dwellStart = nil
    }

    /// Rolling stats right now, for a live meter.
    public var liveSpreadDb: Double { stats.spreadDb }
    public var livePeaksPerMinute: Double { stats.peaksPerMinute }

    // MARK: - Aggregation

    private func makeObservation(_ frames: [FeatureFrame], position: Position?, placeId: UUID?,
                                 tracking: TrackingState) -> Observation {
        let end = frames.last!.t
        let level = min(0, LevelMeter.powerMeanDb(frames.map(\.levelDbfs)) ?? LevelMeter.db(power: 0))
        let aw = frames.compactMap(\.levelAwDbfs)
        let levelAw = aw.count == frames.count ? LevelMeter.powerMeanDb(aw).map { min(0, $0) } : nil

        return Observation(
            sessionId: sessionId, t: end, durationS: Double(frames.count),
            position: position, crumbId: crumbLocator(position), placeId: placeId,
            levelDbfsRel: level, levelAwDbfsRel: levelAw,
            spreadDb: stats.spreadDb, peaksPerMin: stats.peaksPerMinute,
            bandsDb: Self.meanBands(frames), speechShare: Self.meanSpeech(frames),
            classes: Self.topClasses(frames), doa: Self.bestDoa(frames), tracking: tracking)
    }

    /// Power mean per band over frames that have bands; nil when none do.
    static func meanBands(_ frames: [FeatureFrame]) -> [Double]? {
        let all = frames.compactMap(\.bandsDb).filter { $0.count == OctaveBands.centres.count }
        guard !all.isEmpty else { return nil }
        return (0..<OctaveBands.centres.count).map { b in
            min(0, LevelMeter.powerMeanDb(all.map { $0[b] }) ?? LevelMeter.db(power: 0))
        }
    }

    static func meanSpeech(_ frames: [FeatureFrame]) -> Double? {
        let v = frames.compactMap(\.speechShare)
        guard !v.isEmpty else { return nil }
        return min(1, max(0, v.reduce(0, +) / Double(v.count)))
    }

    /// Top 3 labels by mean confidence over the window (a label missing from a frame counts as 0 there).
    static func topClasses(_ frames: [FeatureFrame]) -> [SoundClass] {
        var sums: [String: Double] = [:]
        for f in frames { for c in f.classes { sums[c.label, default: 0] += c.confidence } }
        let n = Double(max(1, frames.count))
        return sums.map { SoundClass(label: $0.key, confidence: min(1, max(0, $0.value / n))) }
            .sorted { $0.confidence != $1.confidence ? $0.confidence > $1.confidence : $0.label < $1.label }
            .prefix(3).map { $0 }
    }

    /// The most confident non-nil DOA in the window.
    static func bestDoa(_ frames: [FeatureFrame]) -> DirectionEstimate? {
        frames.compactMap(\.doa).max { $0.confidence < $1.confidence }
    }
}
