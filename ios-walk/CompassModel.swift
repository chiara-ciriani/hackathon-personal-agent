import AVFoundation
import Foundation
import Observation
import os
import simd

nonisolated struct PipelineUpdate: Sendable {
    var info: StreamInfo
    var level: LevelInfo
    var estimate: DOAEstimate?
    var radar: RadarSnapshot          // τ = 20 s, for the Radar view
    var recent: RadarSnapshot         // τ = 2 s, "current dominant source" for Locate captures
    var powerSum: Double              // Σ mean-square of channel 0 over every buffer since the last update
    var powerCount: Int
    var fromARKit: Bool
}

/// Runs on the audio capture queue: levels + DOA per buffer, published to the UI at ~15 Hz.
nonisolated final class AnalysisPipeline: @unchecked Sendable {
    /// The only state shared with the main actor.
    let settings = OSAllocatedUnfairLock(initialState: DOASettings())
    let threshold = OSAllocatedUnfairLock(initialState: 0.5)
    let radarResetRequested = OSAllocatedUnfairLock(initialState: false)
    private let estimator: DOAEstimator
    private let motion: MotionTracker
    private let publish: @Sendable (PipelineUpdate) -> Void
    private var lastPublish = 0.0
    private var peakSincePublish: Float = -120
    private var radar = SectorRadar(timeConstant: 20)
    private var recent = SectorRadar(timeConstant: 2)
    private var powerSum = 0.0
    private var powerCount = 0
    private var lastFromARKit = false

    init(motion: MotionTracker, publish: @escaping @Sendable (PipelineUpdate) -> Void) throws {
        estimator = try DOAEstimator()
        self.motion = motion
        self.publish = publish
    }

    func handle(_ channels: [[Float]], _ info: StreamInfo) {
        var level = LevelInfo(channels)
        peakSincePublish = max(peakSincePublish, level.peakDB)
        powerSum += pow(10, Double(level.rmsDB) / 10)
        powerCount += 1

        let now = ProcessInfo.processInfo.systemUptime
        let (attitude, fromARKit) = motion.currentWithSource
        // Switching between CoreMotion (magnetic north) and ARKit (true north) rotates the world
        // frame by the declination, so the accumulated sectors would no longer line up.
        if radarResetRequested.withLock({ let r = $0; $0 = false; return r }) || fromARKit != lastFromARKit {
            radar.reset()
            recent.reset()
            lastFromARKit = fromARKit
        }

        var estimate: DOAEstimate?
        if channels.count >= 4 {
            estimate = estimator.process(channels, sampleRate: info.sampleRate, layoutTag: info.layoutTag,
                                         settings: settings.withLock { $0 }, attitude: attitude)
            let min = threshold.withLock { $0 }
            for w in estimator.windows {
                radar.add(w, threshold: min, time: now)
                recent.add(w, threshold: min, time: now)
            }
        }

        guard now - lastPublish >= 1.0 / 15 else { return }
        lastPublish = now
        level.peakDB = peakSincePublish
        peakSincePublish = -120
        radar.decay(to: now)
        recent.decay(to: now)
        publish(PipelineUpdate(info: info, level: level, estimate: estimate, radar: radar.snapshot(),
                               recent: recent.snapshot(), powerSum: powerSum, powerCount: powerCount,
                               fromARKit: fromARKit))
        powerSum = 0
        powerCount = 0
    }
}

nonisolated struct LogRow: Sendable {
    let time: Date
    let bearing: Double?
    let elevation: Double?
    let confidence: Double?
    let levelDB: Float?
    let abstained: Bool
    let phoneBearing: Double
    let threshold: Double
}

nonisolated enum AppMode: String, CaseIterable, Sendable {
    case compass = "Compass", radar = "Radar", locate = "Locate", walk = "Walk map"
}

/// Where a Locate capture's position comes from.
nonisolated enum PositionSource: String, CaseIterable, Sendable {
    case arkit = "ARKit", typed = "Type x/y", walked = "Walked line"
}

nonisolated struct BearingCapture: Identifiable, Sendable {
    let id = UUID()
    var position: SIMD2<Double>      // (east, north) metres
    var bearing: Double
    var confidence: Double
    var levelDBFS: Double?
    var time: Date
    var source: PositionSource
}

nonisolated struct LocatedSource: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var estimate: SourceEstimate
    var summary: String
}

nonisolated struct SavedWalk: Identifiable, Sendable {
    var url: URL
    var record: WalkRecord
    var id: String { record.walkID }
}

@MainActor @Observable
final class CompassModel {
    var status = "Idle"
    var stream = StreamInfo()
    var level: LevelInfo?
    var estimate: DOAEstimate?
    var phoneBearing = 0.0
    var gravityCheck = 0.0
    var reference = ReferenceKind.unavailable

    var settings = DOASettings()
    var threshold = 0.5
    var rows: [LogRow] = []
    var csvURL: URL?
    var autoLog = false

    var mode = AppMode.compass
    var audioEvent = ""
    var radar = RadarSnapshot.empty
    var recentRadar = RadarSnapshot.empty
    var radarFromARKit = false

    // ARKit, shared by Locate and Walk map
    var ar = ARStatus()
    var locateMode = false { didSet { updateAR() } }

    // Locate
    var positionSource = PositionSource.arkit
    var typedEast = 0.0
    var typedNorth = 0.0
    var walkedMetres = 3.0
    var walkedBearing = 90.0
    var captures: [BearingCapture] = []
    var locateResult: Result<SourceEstimate, TriangulationFailure>?
    var located: [LocatedSource] = []
    var locateMessage = ""

    // Walk map
    var isRecording = false { didSet { updateAR() } }
    /// Take the Walk-map level from ARKit's own mic stream instead of AudioCapture.
    var arAudioFallback = false { didSet { restartAR() } }
    var arAudioLevelDB: Float?
    var walk: WalkRecord?
    var walkPath: [SIMD2<Double>] = []        // ARKit x/z crumbs every ~0.5 s while tracking is normal
    var walkMessage = ""
    var savedWalks: [SavedWalk] = []
    var replaying: WalkRecord?
    var replayTime = 0.0
    var field: SoundField?
    var mapPath: [SIMD2<Double>] = []
    var mapUser: SIMD2<Double>?

    @ObservationIgnored private var started = false
    @ObservationIgnored private var arTracker: ARTracker?
    @ObservationIgnored private var walkStart = Date()
    @ObservationIgnored private var walkPowerSum = 0.0
    @ObservationIgnored private var walkPowerCount = 0
    @ObservationIgnored private var walkTask: Task<Void, Never>?
    @ObservationIgnored private var replayTask: Task<Void, Never>?
    @ObservationIgnored private var capture: AudioCapture?
    @ObservationIgnored private var pipeline: AnalysisPipeline?
    @ObservationIgnored private let motion = MotionTracker()

    var showsArrow: Bool { (estimate?.confidence ?? 0) >= threshold && estimate != nil }
    /// Clockwise screen rotation of an "up" arrow so it points at the source.
    var arrowAngle: Double { (estimate?.bearingWorld ?? 0) - phoneBearing }

    func start() async {
        guard !started else { return }
        started = true

        // The model lives as long as the app, so capturing self strongly is fine.
        let pipeline: AnalysisPipeline
        do {
            pipeline = try AnalysisPipeline(motion: motion) { update in
                Task { @MainActor in self.apply(update) }
            }
        } catch {
            status = "DSP setup failed: \(error.localizedDescription)"
            return
        }
        self.pipeline = pipeline
        settingsChanged()

        motionReference = motion.start { attitude in
            Task { @MainActor in self.apply(attitude) }
        }
        reference = motionReference

        status = "Requesting microphone…"
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            status = "Microphone access denied. Enable it in Settings."
            return
        }

        loadWalks()
        let capture = AudioCapture(handler: { channels, info in pipeline.handle(channels, info) },
                                   onEvent: { event, running in
                                       Task { @MainActor in self.audioEvent(event, running: running) }
                                   })
        self.capture = capture
        status = "Starting capture…"
        do {
            stream = try await capture.start()
            status = stream.sessionRunning ? "Listening" : "Capture session did not start"
        } catch {
            status = "Capture failed: \(error.localizedDescription)"
        }
    }

    func settingsChanged() {
        let current = settings
        let min = threshold
        pipeline?.settings.withLock { $0 = current }
        pipeline?.threshold.withLock { $0 = min }
    }

    func restartAudio() { capture?.restart() }

    private func audioEvent(_ event: String, running: Bool) {
        audioEvent = event
        stream.sessionRunning = running
    }

    private func apply(_ update: PipelineUpdate) {
        stream = update.info
        level = update.level
        estimate = update.estimate
        radar = update.radar
        recentRadar = update.recent
        radarFromARKit = update.fromARKit
        if isRecording, !arAudioFallback {
            walkPowerSum += update.powerSum
            walkPowerCount += update.powerCount
        }
    }

    private func apply(_ attitude: Attitude) {
        // While ARKit runs, its orientation (true north) replaces CoreMotion's everywhere.
        let current = motion.currentWithSource
        phoneBearing = current.attitude.phoneBearing
        gravityCheck = current.attitude.gravityCheck
        reference = current.fromARKit ? .arkitTrueNorth : motionReference
    }

    @ObservationIgnored private var motionReference = ReferenceKind.unavailable

    // MARK: - Radar

    func resetRadar() {
        pipeline?.radarResetRequested.withLock { $0 = true }
    }

    // MARK: - ARKit

    /// Runs ARKit while Locate mode is on or a walk is recording, never otherwise.
    private func updateAR() {
        let wanted = locateMode || isRecording
        if wanted, arTracker == nil {
            var onPower: ARTracker.PowerHandler?
            if arAudioFallback {
                onPower = { @Sendable power in
                    Task { @MainActor in self.applyARPower(power) }
                    return
                }
            }
            arTracker = ARTracker(motion: motion, onPower: onPower) { status in
                Task { @MainActor in self.apply(status) }
            }
            arTracker?.start()
        } else if !wanted, let tracker = arTracker {
            tracker.stop()
            arTracker = nil
        }
    }

    private func restartAR() {
        arTracker?.stop()
        arTracker = nil
        updateAR()
    }

    private func applyARPower(_ power: Double) {
        arAudioLevelDB = Float(10 * log10(max(power, 1e-12)))
        if isRecording, arAudioFallback {
            walkPowerSum += power
            walkPowerCount += 1
        }
    }

    private func apply(_ status: ARStatus) {
        ar = status
        if isRecording, let p = status.position, walkPath.last.map({ simd_distance($0, p) > 0.05 }) ?? true {
            walkPath.append(p)
            if replaying == nil { mapPath = walkPath; mapUser = p }
        }
        if status.kind == .unsupported || status.kind == .failed, positionSource == .arkit {
            positionSource = .typed
            locateMessage = "\(status.detail): type positions instead"
        }
    }

    // MARK: - Locate

    /// Stores {position, bearing of the current dominant source, confidence, level, time}.
    func captureBearing() {
        guard let bearing = recentRadar.dominantBearing else {
            locateMessage = "No confident direction in the last 2 s. Keep the source playing, hold still."
            return
        }
        let position: SIMD2<Double>
        switch positionSource {
        case .arkit:
            guard ar.isNormal, let p = ar.position else {
                locateMessage = "ARKit position not available (\(ar.detail)). Wait, or switch to typed/walked position."
                return
            }
            position = ARFrameMath.eastNorth(x: p.x, z: p.y)
        case .typed:
            position = SIMD2(typedEast, typedNorth)
        case .walked:
            position = captures.last.map { $0.position + walkedMetres * Compass.unit(walkedBearing) } ?? .zero
        }
        captures.append(BearingCapture(position: position, bearing: bearing,
                                       confidence: recentRadar.dominantConfidence ?? 0,
                                       levelDBFS: recentRadar.dominantLevelDBFS, time: Date(), source: positionSource))
        locateMessage = String(format: "Captured %.0f° (%@) at (%.1f, %.1f) m", bearing, Compass.point(bearing),
                               position.x, position.y)
        relocate()
    }

    func removeCapture(_ id: UUID) {
        captures.removeAll { $0.id == id }
        relocate()
    }

    func clearCaptures() {
        captures.removeAll()
        locateResult = nil
        locateMessage = ""
    }

    func saveSource() {
        guard case .success(let e) = locateResult else { return }
        let name = "Source \(located.count + 1)"
        located.append(LocatedSource(name: name, estimate: e, summary: "\(name): \(Triangulation.describe(e))"))
        clearCaptures()
    }

    private func relocate() {
        let rays = captures.map { BearingRay(origin: $0.position, bearing: $0.bearing, confidence: $0.confidence) }
        locateResult = rays.count >= 2 ? Triangulation.locate(rays) : nil
    }

    // MARK: - Walk map

    func startWalk() {
        stopReplay()
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        walkStart = Date()
        walk = WalkRecord(walkID: "walk-" + stamp.string(from: walkStart), device: Self.deviceName,
                          startedAt: Self.iso.string(from: walkStart), samples: [])
        walkPath = []
        mapPath = []
        mapUser = nil
        field = nil
        walkPowerSum = 0
        walkPowerCount = 0
        walkMessage = "Recording: walk slowly, phone held camera-forward"
        isRecording = true
        walkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.emitWalkSample()
            }
        }
    }

    func stopWalk() {
        walkTask?.cancel()
        walkTask = nil
        isRecording = false
        guard let walk, !walk.samples.isEmpty else {
            walkMessage = "Nothing saved: no sample had normal tracking and audio"
            return
        }
        do {
            let url = try Self.walksFolder().appendingPathComponent(walk.walkID + ".json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(walk).write(to: url, options: .atomic)
            walkMessage = "Saved \(walk.samples.count) samples"
            loadWalks()
        } catch {
            walkMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    /// Every 2 s: {t, x, z, level_dbfs, tracking}. Skipped while tracking is not normal.
    private func emitWalkSample() {
        guard isRecording, walk != nil else { return }
        let power = walkPowerCount > 0 ? walkPowerSum / Double(walkPowerCount) : 0
        walkPowerSum = 0
        walkPowerCount = 0
        guard ar.isNormal, let p = ar.position else {
            walkMessage = "Tracking limited: \(ar.detail). Sample skipped."
            return
        }
        guard power > 0 else {
            walkMessage = "No audio level: sample skipped"
            return
        }
        let t = Date().timeIntervalSince(walkStart)
        walk?.samples.append(WalkSample(t: t, x: p.x, z: p.y, levelDBFS: 10 * log10(power), tracking: "normal"))
        walkMessage = "Recording: \(walk?.samples.count ?? 0) samples"
        if replaying == nil, let walk {
            field = SoundField.build(samples: walk.fieldSamples(upTo: t), path: walkPath, user: p)
            mapPath = walkPath
            mapUser = p
        }
    }

    /// Animates a saved walk on the map at 10× speed.
    func replay(_ record: WalkRecord) {
        stopReplay()
        replaying = record
        replayTime = 0
        let end = record.samples.last?.t ?? 0
        replayTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.replayTime = min(end, self.replayTime + 1)          // 1 s of walk per 0.1 s
                self.showReplayFrame(record, at: self.replayTime)
                if self.replayTime >= end { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopReplay() {
        replayTask?.cancel()
        replayTask = nil
        replaying = nil
    }

    private func showReplayFrame(_ record: WalkRecord, at t: Double) {
        let shown = record.samples.filter { $0.t <= t }
        mapPath = shown.map { SIMD2($0.x, $0.z) }
        mapUser = mapPath.last
        field = SoundField.build(samples: record.fieldSamples(upTo: t), path: mapPath, user: mapUser)
    }

    func loadWalks() {
        guard let folder = try? Self.walksFolder(),
              let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        savedWalks = urls.filter { $0.pathExtension == "json" }
            .compactMap { url in
                (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(WalkRecord.self, from: $0) }
                    .map { SavedWalk(url: url, record: $0) }
            }
            .sorted { $0.record.startedAt > $1.record.startedAt }
    }

    private static func walksFolder() throws -> URL {
        let folder = URL.documentsDirectory.appendingPathComponent("walks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static var deviceName: String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(machine) iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    // MARK: - Log

    func logNow() {
        rows.append(LogRow(time: Date(), bearing: estimate?.bearingWorld, elevation: estimate?.elevation,
                           confidence: estimate?.confidence, levelDB: level?.rmsDB, abstained: !showsArrow,
                           phoneBearing: phoneBearing, threshold: threshold))
        writeCSV()
    }

    func clearLog() {
        rows.removeAll()
        writeCSV()
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func writeCSV() {
        func num(_ v: Double?, _ digits: Int = 1) -> String { v.map { String(format: "%.\(digits)f", $0) } ?? "" }
        var csv = "unix_time,iso_time,azimuth_world_deg,elevation_deg,confidence,level_dbfs_rel_W,abstained,phone_bearing_deg,threshold\n"
        for r in rows {
            csv += [num(r.time.timeIntervalSince1970, 3), Self.iso.string(from: r.time), num(r.bearing),
                    num(r.elevation), num(r.confidence, 3), num(r.levelDB.map(Double.init)),
                    r.abstained ? "1" : "0", num(r.phoneBearing), num(r.threshold, 2)]
                .joined(separator: ",") + "\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quiet-compass-log.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            csvURL = url
        } catch {
            status = "CSV write failed: \(error.localizedDescription)"
        }
    }
}
