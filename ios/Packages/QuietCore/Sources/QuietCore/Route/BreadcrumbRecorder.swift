import Foundation

/// Turns 2 Hz pose samples into breadcrumbs: one crumb each time the user moved at least
/// `minSpacingM` on the floor plane since the last crumb.
///
/// Only poses with `tracking == .normal` and a position are accepted. When tracking has been
/// unusable for more than `maxGapS`, the current segment is closed: the next crumb starts
/// `segment + 1` and `needsZoneLabel` is raised so the UI can ask the user to name the area
/// (ARKit may have relocalised into a shifted frame, so the two segments are not joined).
public struct BreadcrumbRecorder: Sendable {
    public let sessionId: UUID
    public var minSpacingM: Double = 1.0
    public var maxGapS: TimeInterval = 30

    public private(set) var segment: Int
    public private(set) var nextSeq: Int
    public private(set) var lastCrumb: Crumb?
    public private(set) var needsZoneLabel = false

    private var lastNormalAt: Date?
    /// True once a segment is closed by a gap; the next accepted pose opens the new one.
    private var segmentClosed = false

    public init(sessionId: UUID, nextSeq: Int = 0, segment: Int = 0) {
        self.sessionId = sessionId
        self.nextSeq = nextSeq
        self.segment = segment
    }

    /// Feeds one pose. Returns a crumb when one is due.
    public mutating func ingest(_ pose: PoseSample) -> Crumb? {
        closeSegmentIfGapExceeded(at: pose.t)

        guard pose.tracking == .normal, let position = pose.position else { return nil }
        lastNormalAt = pose.t

        let startsSegment = segmentClosed || lastCrumb == nil
        if !startsSegment, let last = lastCrumb, position.distance(to: last.position) < minSpacingM {
            return nil
        }
        if segmentClosed {
            segment += 1
            segmentClosed = false
        }
        let crumb = Crumb(sessionId: sessionId, seq: nextSeq, segment: segment,
                          position: position, headingRad: pose.headingRad ?? lastCrumb?.headingRad ?? 0,
                          t: pose.t, tracking: .normal)
        nextSeq += 1
        lastCrumb = crumb
        return crumb
    }

    /// Call after the user named the area following a tracking gap.
    public mutating func acknowledgeZoneLabel() { needsZoneLabel = false }

    private mutating func closeSegmentIfGapExceeded(at t: Date) {
        guard !segmentClosed, lastCrumb != nil, let lastNormalAt,
              t.timeIntervalSince(lastNormalAt) > maxGapS else { return }
        segmentClosed = true
        needsZoneLabel = true
    }
}
