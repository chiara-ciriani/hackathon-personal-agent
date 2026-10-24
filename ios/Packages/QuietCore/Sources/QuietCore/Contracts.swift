// Contracts v1. Mirrors contracts/quiet-compass.schema.json; change both together.
import Foundation

public let contractVersion = 1

public enum CaptureMode: String, Codable, Sendable, CaseIterable {
    /// FOA spatial audio + ARKit world tracking.
    case spatialAR = "A"
    /// FOA spatial audio + user-labelled zones (no AR session).
    case spatialZones = "B"
    /// ARKit world tracking + mono levels.
    case arLevels = "C"
}

public enum TrackingState: String, Codable, Sendable {
    case normal
    case limited
    case notAvailable = "not_available"
    case none
}

public enum Goal: String, Codable, Sendable, CaseIterable { case talk, rest, work }
public enum Verdict: String, Codable, Sendable, CaseIterable { case good, ok, bad }
public enum Feel: String, Codable, Sendable, CaseIterable { case calm, neutral, chaotic }
public enum PlaceTag: String, Codable, Sendable, CaseIterable {
    case seating
    case stepFree = "step_free"
    case authorized
}

public struct Position: Codable, Sendable, Hashable {
    public var x: Double
    public var z: Double
    public init(x: Double, z: Double) { self.x = x; self.z = z }

    public func distance(to other: Position) -> Double {
        let dx = x - other.x, dz = z - other.z
        return (dx * dx + dz * dz).squareRoot()
    }
}

public struct DeviceProfile: Codable, Sendable, Hashable {
    public var model: String
    public var osVersion: String
    public var captureMode: CaptureMode
    public var audioSessionMode: String
    public var sampleRateHz: Int
    public var appVersion: String

    public init(model: String, osVersion: String, captureMode: CaptureMode,
                audioSessionMode: String, sampleRateHz: Int, appVersion: String) {
        self.model = model; self.osVersion = osVersion; self.captureMode = captureMode
        self.audioSessionMode = audioSessionMode; self.sampleRateHz = sampleRateHz; self.appVersion = appVersion
    }

    enum CodingKeys: String, CodingKey {
        case model
        case osVersion = "os_version"
        case captureMode = "capture_mode"
        case audioSessionMode = "audio_session_mode"
        case sampleRateHz = "sample_rate_hz"
        case appVersion = "app_version"
    }
}

public struct Session: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String?
    public var startedAt: Date
    public var deviceProfile: DeviceProfile

    public init(id: UUID = UUID(), name: String? = nil, startedAt: Date = Date(), deviceProfile: DeviceProfile) {
        self.id = id; self.name = name; self.startedAt = startedAt; self.deviceProfile = deviceProfile
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case startedAt = "started_at"
        case deviceProfile = "device_profile"
    }
}

public struct SoundClass: Codable, Sendable, Hashable {
    public var label: String
    public var confidence: Double
    public init(label: String, confidence: Double) { self.label = label; self.confidence = confidence }
}

public struct DirectionEstimate: Codable, Sendable, Hashable {
    public enum Frame: String, Codable, Sendable { case world, device }
    public var frame: Frame
    public var azimuthDeg: Double
    public var elevationDeg: Double?
    /// 0 = ahead (−22.5°…22.5°), counting clockwise in 45° steps.
    public var sector: Int
    /// 1 − diffuseness after gating.
    public var confidence: Double

    public init(frame: Frame, azimuthDeg: Double, elevationDeg: Double?, sector: Int, confidence: Double) {
        self.frame = frame; self.azimuthDeg = azimuthDeg; self.elevationDeg = elevationDeg
        self.sector = sector; self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case frame, sector, confidence
        case azimuthDeg = "azimuth_deg"
        case elevationDeg = "elevation_deg"
    }
}

/// A 5-second aggregate of 1 s feature frames. Relative, uncalibrated dBFS — never dBA or SPL.
public struct Observation: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var sessionId: UUID
    public var t: Date
    public var durationS: Double
    public var position: Position?
    public var crumbId: UUID?
    public var placeId: UUID?
    public var levelDbfsRel: Double
    public var levelAwDbfsRel: Double?
    public var spreadDb: Double
    public var peaksPerMin: Double
    /// Octave bands centred 250, 500, 1k, 2k, 4k, 8k Hz.
    public var bandsDb: [Double]?
    public var speechShare: Double?
    public var classes: [SoundClass]
    public var doa: DirectionEstimate?
    public var tracking: TrackingState

    public init(id: UUID = UUID(), sessionId: UUID, t: Date, durationS: Double, position: Position?,
                crumbId: UUID?, placeId: UUID?, levelDbfsRel: Double, levelAwDbfsRel: Double?,
                spreadDb: Double, peaksPerMin: Double, bandsDb: [Double]?, speechShare: Double?,
                classes: [SoundClass], doa: DirectionEstimate?, tracking: TrackingState) {
        self.id = id; self.sessionId = sessionId; self.t = t; self.durationS = durationS
        self.position = position; self.crumbId = crumbId; self.placeId = placeId
        self.levelDbfsRel = levelDbfsRel; self.levelAwDbfsRel = levelAwDbfsRel
        self.spreadDb = spreadDb; self.peaksPerMin = peaksPerMin; self.bandsDb = bandsDb
        self.speechShare = speechShare; self.classes = classes; self.doa = doa; self.tracking = tracking
    }

    enum CodingKeys: String, CodingKey {
        case id, t, position, classes, doa, tracking
        case sessionId = "session_id"
        case durationS = "duration_s"
        case crumbId = "crumb_id"
        case placeId = "place_id"
        case levelDbfsRel = "level_dbfs_rel"
        case levelAwDbfsRel = "level_aw_dbfs_rel"
        case spreadDb = "spread_db"
        case peaksPerMin = "peaks_per_min"
        case bandsDb = "bands_db"
        case speechShare = "speech_share"
    }
}

public struct Crumb: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var sessionId: UUID
    public var seq: Int
    public var segment: Int
    public var position: Position
    public var headingRad: Double
    public var t: Date
    public var tracking: TrackingState

    public init(id: UUID = UUID(), sessionId: UUID, seq: Int, segment: Int = 0, position: Position,
                headingRad: Double, t: Date, tracking: TrackingState) {
        self.id = id; self.sessionId = sessionId; self.seq = seq; self.segment = segment
        self.position = position; self.headingRad = headingRad; self.t = t; self.tracking = tracking
    }

    enum CodingKeys: String, CodingKey {
        case id, seq, segment, position, t, tracking
        case sessionId = "session_id"
        case headingRad = "heading_rad"
    }
}

public struct Place: Codable, Sendable, Identifiable, Hashable {
    public enum Source: String, Codable, Sendable { case user, organizer, seed }
    public var id: UUID
    public var sessionId: UUID
    public var label: String
    public var position: Position?
    public var crumbId: UUID?
    public var zone: String?
    public var tags: [PlaceTag]
    public var source: Source
    public var createdAt: Date

    public init(id: UUID = UUID(), sessionId: UUID, label: String, position: Position?, crumbId: UUID?,
                zone: String? = nil, tags: [PlaceTag] = [], source: Source = .user, createdAt: Date = Date()) {
        self.id = id; self.sessionId = sessionId; self.label = label; self.position = position
        self.crumbId = crumbId; self.zone = zone; self.tags = tags; self.source = source; self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, label, position, zone, tags, source
        case sessionId = "session_id"
        case crumbId = "crumb_id"
        case createdAt = "created_at"
    }
}

public struct Feedback: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var sessionId: UUID
    public var placeId: UUID
    public var goal: Goal
    public var verdict: Verdict
    public var feel: Feel?
    public var t: Date

    public init(id: UUID = UUID(), sessionId: UUID, placeId: UUID, goal: Goal, verdict: Verdict,
                feel: Feel?, t: Date = Date()) {
        self.id = id; self.sessionId = sessionId; self.placeId = placeId
        self.goal = goal; self.verdict = verdict; self.feel = feel; self.t = t
    }

    enum CodingKeys: String, CodingKey {
        case id, goal, verdict, feel, t
        case sessionId = "session_id"
        case placeId = "place_id"
    }
}

public struct Guidance: Codable, Sendable, Hashable {
    public enum Status: String, Codable, Sendable { case active, arrived, cancelled }
    public var sessionId: UUID
    public var targetPlaceId: UUID
    public var targetLabel: String
    public var status: Status
    public var reason: String?
    public var updatedAt: Date

    public init(sessionId: UUID, targetPlaceId: UUID, targetLabel: String, status: Status,
                reason: String?, updatedAt: Date) {
        self.sessionId = sessionId; self.targetPlaceId = targetPlaceId; self.targetLabel = targetLabel
        self.status = status; self.reason = reason; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case status, reason
        case sessionId = "session_id"
        case targetPlaceId = "target_place_id"
        case targetLabel = "target_label"
        case updatedAt = "updated_at"
    }
}

// MARK: - Request envelopes

public struct SessionUpsert: Codable, Sendable {
    public var contractVersion = QuietCore.contractVersion
    public var session: Session
    public init(session: Session) { self.session = session }
    enum CodingKeys: String, CodingKey { case session; case contractVersion = "contract_version" }
}

public struct ObservationBatch: Codable, Sendable {
    public var contractVersion = QuietCore.contractVersion
    public var observations: [Observation]
    public init(observations: [Observation]) { self.observations = observations }
    enum CodingKeys: String, CodingKey { case observations; case contractVersion = "contract_version" }
}

public struct CrumbBatch: Codable, Sendable {
    public var contractVersion = QuietCore.contractVersion
    public var crumbs: [Crumb]
    public init(crumbs: [Crumb]) { self.crumbs = crumbs }
    enum CodingKeys: String, CodingKey { case crumbs; case contractVersion = "contract_version" }
}

public struct PlaceBatch: Codable, Sendable {
    public var contractVersion = QuietCore.contractVersion
    public var places: [Place]
    public init(places: [Place]) { self.places = places }
    enum CodingKeys: String, CodingKey { case places; case contractVersion = "contract_version" }
}

public struct FeedbackBatch: Codable, Sendable {
    public var contractVersion = QuietCore.contractVersion
    public var feedback: [Feedback]
    public init(feedback: [Feedback]) { self.feedback = feedback }
    enum CodingKeys: String, CodingKey { case feedback; case contractVersion = "contract_version" }
}

public struct GuidanceStatusUpdate: Codable, Sendable {
    public var contractVersion = QuietCore.contractVersion
    public var status: Guidance.Status
    public init(status: Guidance.Status) { self.status = status }
    enum CodingKeys: String, CodingKey { case status; case contractVersion = "contract_version" }
}

public struct IngestResult: Codable, Sendable {
    public var accepted: Int
    public var duplicates: Int
}

// MARK: - JSON coding

public enum ContractJSON {
    /// ISO 8601 UTC with fractional seconds and a Z suffix, as the schema requires.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, enc in
            var container = enc.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let raw = try dec.singleValueContainer().decode(String.self)
            if let date = formatter.date(from: raw) ?? plainFormatter.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath,
                                                    debugDescription: "Invalid ISO 8601 date: \(raw)"))
        }
        return decoder
    }

    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
