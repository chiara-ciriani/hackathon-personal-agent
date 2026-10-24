// Seams between the audio track and the app/UI track. Keep these stable; change by agreement.
import Foundation

/// One second of computed audio features. Produced by a `FeatureSource`, aggregated into 5 s `Observation`s.
public struct FeatureFrame: Sendable, Hashable, Codable {
    public var t: Date
    /// 10·log10(mean(w²) + 1e-12) over the second (mean of eight 125 ms frames), relative dBFS.
    public var levelDbfs: Double
    /// Same after A-weighting; nil when not computed.
    public var levelAwDbfs: Double?
    /// The eight 125 ms frame levels in this second, needed for rolling L10/L90 and peak counts.
    public var shortFrameLevelsDbfs: [Double]
    /// Octave bands centred 250, 500, 1k, 2k, 4k, 8k Hz; nil when not computed.
    public var bandsDb: [Double]?
    /// Mean `speech` confidence from the sound classifier over the second; nil when the classifier is off.
    public var speechShare: Double?
    public var classes: [SoundClass]
    /// Direction of arrival; nil when the estimator abstained or the mode has no FOA.
    public var doa: DirectionEstimate?

    public init(t: Date, levelDbfs: Double, levelAwDbfs: Double?, shortFrameLevelsDbfs: [Double],
                bandsDb: [Double]?, speechShare: Double?, classes: [SoundClass], doa: DirectionEstimate?) {
        self.t = t; self.levelDbfs = levelDbfs; self.levelAwDbfs = levelAwDbfs
        self.shortFrameLevelsDbfs = shortFrameLevelsDbfs; self.bandsDb = bandsDb
        self.speechShare = speechShare; self.classes = classes; self.doa = doa
    }
}

/// Anything that produces feature frames: the FOA capture, the mono capture, or a mock replaying a trace.
public protocol FeatureSource: AnyObject, Sendable {
    /// Human-readable name for diagnostics, e.g. "FOA (AVCaptureSession)".
    var name: String { get }
    /// Starts capture. Throws when the device or permissions do not allow it.
    func start() async throws
    func stop() async
    /// A stream of frames; one consumer at a time.
    func frames() -> AsyncStream<FeatureFrame>
}

/// Where the user is when a frame is recorded. Supplied by the tracking layer.
public struct PoseSample: Sendable, Hashable {
    public var t: Date
    public var position: Position?
    public var headingRad: Double?
    public var tracking: TrackingState
    public init(t: Date, position: Position?, headingRad: Double?, tracking: TrackingState) {
        self.t = t; self.position = position; self.headingRad = headingRad; self.tracking = tracking
    }
}
