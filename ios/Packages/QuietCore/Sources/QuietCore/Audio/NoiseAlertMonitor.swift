// Decides when it has been too loud for too long. Foundation only, so it runs in `swift test`.
//
// Levels are relative, uncalibrated dBFS, so the threshold is relative to the person: a baseline they
// mark as comfortable plus an offset. See docs/BACKGROUND_CAPTURE_AND_NOISE_ALERTS.md.
import Foundation

public struct NoiseAlert: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// The level stayed above the threshold for `seconds`; `overBaselineDb` is the latest excess.
        case sustainedLevel(overBaselineDb: Double, seconds: Double)
        /// Abrupt sounds: onsets per minute from the observation.
        case peaks(perMinute: Double)
    }
    public var t: Date
    public var reason: Reason
}

public struct NoiseAlertMonitor: Sendable {
    public struct Settings: Sendable, Equatable {
        /// How far above the baseline counts as too loud.
        public var offsetDb: Double = 10
        /// How long the level must stay above the threshold.
        public var sustainS: Double = 30
        /// Onsets per minute that trigger an alert on their own. Starting point; tune on a device.
        public var peaksPerMin: Double = 20
        /// The level must fall this far below the threshold before another alert can fire.
        public var rearmDb: Double = 5
        /// Minimum time between alerts.
        public var cooldownS: Double = 600
        /// A gap longer than this between observations (an interruption) restarts the sustain timer.
        public var maxGapS: Double = 15

        public init() {}
    }

    public var settings: Settings
    public private(set) var baselineDb: Double?
    private var aboveSince: Date?
    private var lastT: Date?
    private var armed = true
    private var lastAlert: Date?
    private var snoozedUntil: Date?

    public init(settings: Settings = Settings(), baselineDb: Double? = nil) {
        self.settings = settings; self.baselineDb = baselineDb
    }

    public var thresholdDb: Double? { baselineDb.map { $0 + settings.offsetDb } }

    /// "This feels comfortable": use this level as the baseline and start over.
    public mutating func setBaseline(_ db: Double) {
        baselineDb = db; aboveSince = nil; armed = true
    }

    public mutating func snooze(until t: Date) { snoozedUntil = t }

    /// The level the monitor compares: A-weighted when available.
    public static func level(of o: Observation) -> Double { o.levelAwDbfsRel ?? o.levelDbfsRel }

    /// Feed each 5 s observation in time order. Returns an alert when one should be shown.
    /// Without a baseline, the first observation becomes the baseline.
    public mutating func ingest(_ o: Observation) -> NoiseAlert? {
        let level = Self.level(of: o)
        defer { lastT = o.t }
        guard let threshold = thresholdDb else { setBaseline(level); return nil }
        if let lastT, o.t.timeIntervalSince(lastT) > settings.maxGapS { aboveSince = nil }

        let loud = level > threshold
        let peaky = o.peaksPerMin >= settings.peaksPerMin
        if loud { aboveSince = aboveSince ?? o.t.addingTimeInterval(-o.durationS) } else { aboveSince = nil }
        if !armed, level < threshold - settings.rearmDb, !peaky { armed = true }

        guard armed else { return nil }
        if let snoozedUntil, o.t < snoozedUntil { return nil }
        if let lastAlert, o.t.timeIntervalSince(lastAlert) < settings.cooldownS { return nil }

        let reason: NoiseAlert.Reason
        if let since = aboveSince, o.t.timeIntervalSince(since) >= settings.sustainS {
            reason = .sustainedLevel(overBaselineDb: level - (baselineDb ?? level), seconds: o.t.timeIntervalSince(since))
        } else if peaky {
            reason = .peaks(perMinute: o.peaksPerMin)
        } else { return nil }
        armed = false; lastAlert = o.t
        return NoiseAlert(t: o.t, reason: reason)
    }
}
