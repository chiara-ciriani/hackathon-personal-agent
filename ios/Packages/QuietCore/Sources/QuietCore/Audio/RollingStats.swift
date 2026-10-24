// Rolling level statistics over 125 ms frames. Foundation only.
//
// spread_db      = L10 − L90 over the last 30 s (240 frames). L10 is the level exceeded 10 % of the time
//                  (the 90th percentile), L90 the level exceeded 90 % of the time (the 10th percentile).
//                  Percentiles use linear interpolation between order statistics. Before 30 s of data
//                  exist, the statistic covers whatever is there (the UI shows a "measuring" state).
// peaks_per_min  = onsets per minute over the last 60 s (480 frames). A frame is "above" when its level
//                  exceeds the rolling median of the last 60 s (including itself) + 10 dB.
//                  We count ONSETS: a frame that is above while the previous frame was not. A single
//                  1 s door slam that stays above for 8 frames counts as one peak, not eight, which
//                  matches how people perceive "how often something jumps out". The rate is normalized
//                  by the covered duration (count · 60 / seconds covered), so it is noisy until the
//                  window fills; it is 0 with fewer than `minimumSecondsForPeaks` of data.
import Foundation

public struct RollingStats: Sendable {
    public struct Configuration: Sendable, Hashable {
        public var frameDuration: Double = LevelMeter.frameDuration
        public var spreadWindowSeconds: Double = 30
        public var peakWindowSeconds: Double = 60
        public var peakThresholdAboveMedianDb: Double = 10
        public var minimumSecondsForPeaks: Double = 5
        public init() {}
    }

    public let configuration: Configuration
    private let spreadCapacity: Int
    private let peakCapacity: Int
    /// Ring of the most recent levels, sized for the longer (peak) window.
    private var levels: [Double]
    private var head = 0          // next write index
    private var count = 0
    /// Frame indices (monotonic) at which an onset occurred.
    private var onsets: [Int] = []
    private var frameIndex = 0
    private var previousAbove = false
    private var scratch: [Double] = []

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        spreadCapacity = max(1, Int((configuration.spreadWindowSeconds / configuration.frameDuration).rounded()))
        peakCapacity = max(1, Int((configuration.peakWindowSeconds / configuration.frameDuration).rounded()))
        levels = [Double](repeating: 0, count: max(spreadCapacity, peakCapacity))
        scratch.reserveCapacity(levels.count)
    }

    public var framesSeen: Int { frameIndex }

    public mutating func append(_ levelDb: Double) {
        levels[head] = levelDb
        head = (head + 1) % levels.count
        count = min(count + 1, levels.count)

        let window = recent(peakCapacity)
        let threshold = (Self.percentile(window, 0.5, scratch: &scratch) ?? levelDb)
            + configuration.peakThresholdAboveMedianDb
        let above = levelDb > threshold
        if above && !previousAbove { onsets.append(frameIndex) }
        previousAbove = above

        frameIndex += 1
        let oldest = frameIndex - peakCapacity
        if let first = onsets.first, first < oldest {
            onsets.removeAll { $0 < oldest }
        }
    }

    public mutating func append(contentsOf levelsDb: [Double]) {
        for l in levelsDb { append(l) }
    }

    /// L10 − L90 over the spread window; 0 with fewer than two frames.
    public var spreadDb: Double {
        var s: [Double] = []
        let r = recent(spreadCapacity)
        guard r.count >= 2,
              let l10 = Self.percentile(r, 0.9, scratch: &s),
              let l90 = Self.percentile(r, 0.1, scratch: &s) else { return 0 }
        return max(0, l10 - l90)
    }

    /// Onsets per minute over the peak window.
    public var peaksPerMinute: Double {
        let covered = Double(min(frameIndex, peakCapacity)) * configuration.frameDuration
        guard covered >= configuration.minimumSecondsForPeaks else { return 0 }
        return Double(onsets.count) * 60 / covered
    }

    /// Seconds of data in the spread window (caps at 30 s).
    public var spreadCoverageSeconds: Double {
        Double(min(count, spreadCapacity)) * configuration.frameDuration
    }

    public mutating func reset() {
        head = 0; count = 0; frameIndex = 0; previousAbove = false
        onsets.removeAll()
    }

    /// The most recent `n` levels (oldest first), at most `count`.
    private func recent(_ n: Int) -> ArraySlice<Double> {
        let k = min(n, count)
        guard k > 0 else { return [] }
        var out = [Double]()
        out.reserveCapacity(k)
        let cap = levels.count
        var i = (head - k + cap) % cap
        for _ in 0..<k { out.append(levels[i]); i = (i + 1) % cap }
        return out[...]
    }

    /// Linear-interpolated percentile q ∈ [0, 1]; nil for an empty input.
    public static func percentile<C: Collection>(_ values: C, _ q: Double, scratch: inout [Double]) -> Double?
    where C.Element == Double {
        guard !values.isEmpty else { return nil }
        scratch.removeAll(keepingCapacity: true)
        scratch.append(contentsOf: values)
        scratch.sort()
        let pos = q * Double(scratch.count - 1)
        let lo = Int(pos.rounded(.down)), hi = min(lo + 1, scratch.count - 1)
        let frac = pos - Double(lo)
        return scratch[lo] + (scratch[hi] - scratch[lo]) * frac
    }

    public static func percentile(_ values: [Double], _ q: Double) -> Double? {
        var s: [Double] = []
        return percentile(values, q, scratch: &s)
    }
}
