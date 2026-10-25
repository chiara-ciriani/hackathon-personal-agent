// Turns relative levels into words. Levels are uncalibrated dBFS from one phone, so the app never shows
// them as absolute numbers to the user; it compares them with the median of the current session.
import Foundation

enum LevelDescription {
    /// Words for a level relative to the session median. Thresholds in dB.
    static func relative(_ level: Double?, median: Double?) -> String {
        guard let level else { return "Listening…" }
        guard let median else { return "Getting a feel for this place" }
        let d = level - median
        switch d {
        case ..<(-6): return "Much quieter than usual here"
        case ..<(-2): return "A bit quieter than usual here"
        case ...2: return "About usual for this session"
        case ...6: return "A bit louder than usual here"
        default: return "Much louder than usual here"
        }
    }

    /// Short form for lists and the map.
    static func short(_ level: Double?, median: Double?) -> String {
        guard let level, let median else { return "not measured" }
        let d = level - median
        switch d {
        case ..<(-6): return "much quieter"
        case ..<(-2): return "quieter"
        case ...2: return "usual"
        case ...6: return "louder"
        default: return "much louder"
        }
    }

    /// Meter position 0…1 for a level relative to the median (±12 dB maps to the ends; median at 0.5).
    static func meterFraction(_ level: Double?, median: Double?) -> Double {
        guard let level, let median else { return 0.5 }
        return min(1, max(0, 0.5 + (level - median) / 24))
    }

    static func age(since date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        switch s {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(s / 60)) min ago"
        default: return "\(Int(s / 3600)) h ago"
        }
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
    }

    static func distance(_ metres: Double) -> String {
        metres < 1 ? "less than a metre" : (metres < 10 ? String(format: "%.0f m", metres) : "\(Int((metres / 5).rounded() * 5)) m")
    }

    static func walkMinutes(_ minutes: Double) -> String {
        minutes < 1 ? "under a minute's walk" : "about \(Int(minutes.rounded())) min walk"
    }
}

/// Rolling median of the session's 1 s levels (last 30 minutes), the reference for "louder"/"quieter".
struct SessionLevelBaseline: Sendable {
    let capacity: Int
    private var values: [Double] = []

    init(capacity: Int = 1800) { self.capacity = capacity }

    mutating func append(_ level: Double) {
        values.append(level)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    var median: Double? { LevelDescription.median(values) }
    var count: Int { values.count }
}
