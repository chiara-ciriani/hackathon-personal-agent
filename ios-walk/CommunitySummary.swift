import Foundation
import os

/// Only numeric acoustic features enter this accumulator. No audio or room positions are retained.
nonisolated final class CommunityAccumulator: @unchecked Sendable {
    struct State: Sendable {
        var energy = 0.0
        var samples = 0
        var levels: [Double] = []
        var first: Double?
        var last: Double?
        var rate = 0.0
        var channels = 0
        var invalid = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func add(level: Double, peak: Double, samples: Int, rate: Double, channels: Int, time: Double) {
        state.withLock { s in
            guard samples > 0, level.isFinite, peak.isFinite, rate > 0, channels > 0 else { s.invalid = true; return }
            if let last = s.last, time - last > 2 { s.invalid = true }
            if s.first == nil { s.first = time; s.rate = rate; s.channels = channels }
            if s.rate != rate || s.channels != channels || peak >= -1 { s.invalid = true }
            s.energy += pow(10, level / 10) * Double(samples)
            s.samples += samples
            if s.levels.count < 10000 { s.levels.append(level) } else { s.invalid = true }
            s.last = time
        }
    }

    func summary(now: Double) throws -> (rms: Double, spread: Double, rate: Double, channels: Int) {
        try state.withLock { s in
            guard !s.invalid, s.samples > 0, let first = s.first, let last = s.last,
                  last - first >= 9, now - last < 2 else {
                throw AgentConnectionError("Capture was interrupted or clipped. Try again in a quieter spot.")
            }
            let rms = 10 * log10(s.energy / Double(s.samples))
            guard rms > -119, rms <= 0 else { throw AgentConnectionError("No microphone signal. Check permissions and try again.") }
            let levels = s.levels.sorted()
            let spread = levels[Int(Double(levels.count - 1) * 0.9)] - levels[Int(Double(levels.count - 1) * 0.1)]
            return (rms, min(60, spread), s.rate, s.channels)
        }
    }
}

nonisolated enum CommunityPayload {
    static func data(id: UUID, at date: Date, lat: Double, lon: Double,
                     rms: Double, spread: Double, profile: String) throws -> Data {
        let latitude = (lat * 1000).rounded() / 1000
        let longitude = (lon * 1000).rounded() / 1000
        let bucket = Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 300) * 300)
        let contribution: [String: Any] = [
            "id": id.uuidString, "schema_version": "0.1",
            "area_id": String(format: "cell:%.3f,%.3f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude),
            "area_name": NSNull(), "lat": latitude, "lon": longitude,
            "time_bucket": ISO8601DateFormatter().string(from: bucket), "duration_seconds": 10,
            "measurement": ["kind": "relative_uncalibrated", "rms_dbfs": rms,
                            "frame_level_spread_db": spread, "peaks_per_min": NSNull(), "calibrated": false],
            "quality": ["capture_profile": profile, "clipping_detected": false], "source": "device",
        ]
        return try JSONSerialization.data(withJSONObject: ["contract_version": 1, "share_consent": true,
                                                           "contribution": contribution], options: [.sortedKeys])
    }
}
