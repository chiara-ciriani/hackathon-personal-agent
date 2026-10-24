import Foundation

public struct HealthMetric: Codable, Sendable, Identifiable {
    public var name: String
    public var value: Double
    public var unit: String
    public var day: String
    public var id: String { "\(name):\(day)" }
    public init(name: String, value: Double, unit: String, day: String) {
        self.name = name; self.value = value; self.unit = unit; self.day = day
    }
}

public struct HealthSummary: Codable, Sendable {
    public var source = "apple_health"
    public var capturedAt: Date
    public var metrics: [HealthMetric]
    public var note: String
    public init(capturedAt: Date, metrics: [HealthMetric], note: String) {
        self.capturedAt = capturedAt; self.metrics = metrics; self.note = note
    }
    enum CodingKeys: String, CodingKey { case source, metrics, note; case capturedAt = "captured_at" }
}

public enum SleepIntervals {
    /// Union, clipped to the reporting window. Overlapping devices and sleep stages never double count.
    public static func seconds(_ intervals: [DateInterval], within window: DateInterval) -> Double {
        let sorted = intervals.compactMap { interval -> DateInterval? in
            let start = max(interval.start, window.start), end = min(interval.end, window.end)
            return start < end ? DateInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        var end = window.start, total = 0.0
        for interval in sorted {
            let start = max(end, interval.start)
            if interval.end > start { total += interval.end.timeIntervalSince(start) }
            end = max(end, interval.end)
        }
        return total
    }
}
