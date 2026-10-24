// Opt-in anonymous sound summary for the shared layer (product brief, "Example contribution shape").
// Off by default. It carries a coarse area id, a 5-minute time bucket and a relative, uncalibrated level
// summary. No audio, no route, no session id, no personal preferences.
import Foundation

struct SharedContribution: Codable, Sendable, Hashable, Identifiable {
    enum Source: String, Codable, Sendable { case device, simulated }

    struct Measurement: Codable, Sendable, Hashable {
        /// Always "relative_uncalibrated": these are dBFS from one phone, never dBA or SPL.
        var kind: String = "relative_uncalibrated"
        var rmsDbfs: Double
        var frameLevelSpreadDb: Double
        var peaksPerMin: Double?
        var calibrated: Bool = false

        enum CodingKeys: String, CodingKey {
            case kind, calibrated
            case rmsDbfs = "rms_dbfs"
            case frameLevelSpreadDb = "frame_level_spread_db"
            case peaksPerMin = "peaks_per_min"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(kind, forKey: .kind)
            try c.encode(rmsDbfs, forKey: .rmsDbfs)
            try c.encode(frameLevelSpreadDb, forKey: .frameLevelSpreadDb)
            try c.encode(peaksPerMin, forKey: .peaksPerMin)   // explicit null when unknown
            try c.encode(calibrated, forKey: .calibrated)
        }
    }

    struct Quality: Codable, Sendable, Hashable {
        /// Model + capture mode + audio session mode, e.g. "iPhone17,1/mode-A/measurement".
        var captureProfile: String
        var clippingDetected: Bool

        enum CodingKeys: String, CodingKey {
            case captureProfile = "capture_profile"
            case clippingDetected = "clipping_detected"
        }
    }

    static let schemaVersion = "0.1"
    /// A 1 s level at or above this (relative dBFS) is treated as possible clipping.
    static let clippingThresholdDbfs = -1.0

    var id: UUID
    var schemaVersion: String = SharedContribution.schemaVersion
    var areaId: String
    var areaName: String?
    var lat: Double?
    var lon: Double?
    var timeBucket: Date
    var durationSeconds: Double
    var measurement: Measurement
    var quality: Quality
    var source: Source

    enum CodingKeys: String, CodingKey {
        case id, lat, lon, measurement, quality, source
        case schemaVersion = "schema_version"
        case areaId = "area_id"
        case areaName = "area_name"
        case timeBucket = "time_bucket"
        case durationSeconds = "duration_seconds"
    }

    init(id: UUID = UUID(), areaId: String, areaName: String?, lat: Double? = nil, lon: Double? = nil,
         time: Date, durationSeconds: Double, measurement: Measurement, quality: Quality, source: Source) {
        self.id = id
        self.areaId = areaId
        self.areaName = areaName.map { String($0.prefix(80)) }   // the server caps area_name at 80
        self.lat = lat.map(Self.roundCoordinate)
        self.lon = lon.map(Self.roundCoordinate)
        self.timeBucket = Self.timeBucket(for: time)
        self.durationSeconds = durationSeconds
        self.measurement = measurement
        self.quality = quality
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        schemaVersion = try c.decode(String.self, forKey: .schemaVersion)
        areaId = try c.decode(String.self, forKey: .areaId)
        areaName = try c.decodeIfPresent(String.self, forKey: .areaName)
        lat = try c.decodeIfPresent(Double.self, forKey: .lat)
        lon = try c.decodeIfPresent(Double.self, forKey: .lon)
        let bucket = try c.decode(String.self, forKey: .timeBucket)
        guard let date = Self.bucketFormatter.date(from: bucket) else {
            throw DecodingError.dataCorruptedError(forKey: .timeBucket, in: c, debugDescription: "Invalid time_bucket \(bucket)")
        }
        timeBucket = date
        durationSeconds = try c.decode(Double.self, forKey: .durationSeconds)
        measurement = try c.decode(Measurement.self, forKey: .measurement)
        quality = try c.decode(Quality.self, forKey: .quality)
        source = try c.decode(Source.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(areaId, forKey: .areaId)
        try c.encode(areaName, forKey: .areaName)          // explicit nulls: the field set is fixed
        try c.encode(lat.map(Self.roundCoordinate), forKey: .lat)
        try c.encode(lon.map(Self.roundCoordinate), forKey: .lon)
        try c.encode(Self.bucketString(timeBucket), forKey: .timeBucket)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(measurement, forKey: .measurement)
        try c.encode(quality, forKey: .quality)
        try c.encode(source, forKey: .source)
    }

    // MARK: - Area ids

    /// "place:<uuid>" for a marked place (indoor; lat/lon stay nil).
    static func areaId(forPlace id: UUID) -> String { "place:" + id.uuidString.lowercased() }

    /// "zone:<slug>" for a user-named zone (mode B).
    static func areaId(forZone zone: String) -> String { "zone:" + slug(zone) }

    static func slug(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var out = ""
        for scalar in folded.unicodeScalars {
            if scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
            } else if !out.isEmpty && !out.hasSuffix("-") {
                out.append("-")
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "unnamed" : String(out.prefix(100))
    }

    // MARK: - Coarsening

    /// Three decimals (about 100 m of latitude).
    static func roundCoordinate(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    /// Floors to the start of the 5-minute UTC bucket.
    static func timeBucket(for date: Date) -> Date {
        let s = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: (s / 300).rounded(.down) * 300)
    }

    /// "2026-10-24T17:05:00Z"
    static func bucketString(_ date: Date) -> String {
        bucketFormatter.string(from: timeBucket(for: date))
    }

    nonisolated(unsafe) private static let bucketFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: - Building from a dwell window

    /// One window's input: what the observations of a 30 s dwell measured. Kept free of QuietCore types
    /// so it can be unit-tested on its own.
    struct WindowSample: Sendable, Hashable {
        var levelDbfs: Double
        var spreadDb: Double
        var peaksPerMin: Double?
        var durationSeconds: Double
    }

    /// Medians of the window's observations. Returns nil for an empty window.
    static func make(area: (id: String, name: String?), endingAt time: Date, samples: [WindowSample],
                     maxFrameLevelDbfs: Double?, captureProfile: String, source: Source) -> SharedContribution? {
        guard !samples.isEmpty else { return nil }
        let peaks = samples.compactMap(\.peaksPerMin)
        let measurement = Measurement(rmsDbfs: round1(median(samples.map(\.levelDbfs))),
                                      frameLevelSpreadDb: round1(median(samples.map(\.spreadDb))),
                                      peaksPerMin: peaks.isEmpty ? nil : round1(median(peaks)))
        let clipping = (maxFrameLevelDbfs ?? -120) >= clippingThresholdDbfs
        return SharedContribution(areaId: area.id, areaName: area.name, time: time,
                                  durationSeconds: samples.reduce(0) { $0 + $1.durationSeconds },
                                  measurement: measurement,
                                  quality: Quality(captureProfile: captureProfile, clippingDetected: clipping),
                                  source: source)
    }

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        let mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
    }

    static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
}

/// POST /v1/contributions body.
struct ContributionSubmission: Codable, Sendable {
    var contractVersion = 1
    var contribution: SharedContribution
    var shareConsent = false
    enum CodingKeys: String, CodingKey {
        case contribution
        case contractVersion = "contract_version"
        case shareConsent = "share_consent"
    }
}

/// POST /v1/contributions response.
struct ContributionResult: Codable, Sendable, Hashable {
    enum Status: String, Codable, Sendable { case accepted, withheld, rejected }
    var status: Status
    var reason: String?
    var areaId: String?
    var timeBucket: String?

    enum CodingKeys: String, CodingKey {
        case status, reason
        case areaId = "area_id"
        case timeBucket = "time_bucket"
    }

    /// Calm, plain-language status for the UI.
    var displayText: String {
        switch status {
        case .accepted: "Shared"
        case .withheld: "Kept back for now" + (reason.map { " (\($0))" } ?? "")
        case .rejected: "Not shared" + (reason.map { " (\($0))" } ?? "")
        }
    }
}
