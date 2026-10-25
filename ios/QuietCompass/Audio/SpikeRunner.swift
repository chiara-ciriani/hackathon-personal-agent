// Hour-0 feasibility tests, run from the Diagnostics screen (docs/IMPLEMENTATION_PLAN.md, steps 1–3).
//   foaAlone     FOA capture for ~10 s: channels, sample rate, buffers per second, mode support.
//   foaWithAR    ARSession (providesAudioData = false, .gravity) + FOA for `foaWithARSeconds`:
//                tracking changes, session errors, whether FOA buffers keep flowing.
//   gainControl  Guided tone-then-talk test. Compares the 1 kHz octave band with the tone alone and with
//                someone talking, in .measurement and in .default mode. Fails if the band dips > 3 dB.
import ARKit
import AVFoundation
import Foundation
import Observation
import enum QuietCore.OctaveBands
import struct QuietCore.RollingStats
import enum QuietCore.TrackingState
import UIKit
import os

public enum SpikeTest: String, CaseIterable, Sendable {
    case foaAlone, foaWithAR, gainControl

    public var title: String {
        switch self {
        case .foaAlone: "Spatial audio alone"
        case .foaWithAR: "Spatial audio with tracking"
        case .gainControl: "Automatic gain check"
        }
    }

    public var explanation: String {
        switch self {
        case .foaAlone: "Captures four-channel audio for about 10 seconds and reports what arrives."
        case .foaWithAR: "Runs spatial audio and camera tracking together and watches for problems."
        case .gainControl: "Play a steady 1 kHz tone, then talk near the phone. The tone should not get quieter."
        }
    }
}

public struct SpikeReport: Sendable {
    public var test: SpikeTest
    /// nil when the test could not reach a verdict (e.g. cancelled or unsupported in the Simulator).
    public var passed: Bool?
    public var lines: [String]

    public init(test: SpikeTest, passed: Bool?, lines: [String]) {
        self.test = test; self.passed = passed; self.lines = lines
    }
}

@MainActor @Observable
public final class SpikeRunner {
    public private(set) var isRunning = false
    public private(set) var reports: [SpikeReport] = []
    /// Instruction for the person running a guided test ("Start the tone now"); nil when none.
    public private(set) var prompt: String?
    /// Seconds left in the current step, for the UI.
    public private(set) var secondsLeft: Int?

    public var foaAloneSeconds = 10
    public var foaWithARSeconds = 60
    public var gainPhaseSeconds = 8
    /// Largest allowed drop of the 1 kHz band while someone talks.
    public var maxDipDb = 3.0

    @ObservationIgnored private let log = Logger(subsystem: "QuietCompass", category: "Spike")

    public init() {}

    public func run(_ test: SpikeTest) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false; prompt = nil; secondsLeft = nil }
        let report: SpikeReport
        #if targetEnvironment(simulator)
        report = SpikeReport(test: test, passed: nil,
                             lines: ["The Simulator has no spatial microphones or camera tracking. Run this on an iPhone."])
        #else
        switch test {
        case .foaAlone: report = await runFOAAlone()
        case .foaWithAR: report = await runFOAWithAR()
        case .gainControl: report = await runGainControl()
        }
        #endif
        reports.removeAll { $0.test == test }
        reports.append(report)
        log.info("spike \(test.rawValue) passed=\(String(describing: report.passed)) \(report.lines.joined(separator: " | "))")
    }

    // MARK: - foaAlone

    private func runFOAAlone() async -> SpikeReport {
        guard await AudioSessionConfigurator.requestRecordPermission() else {
            return SpikeReport(test: .foaAlone, passed: false, lines: ["Microphone permission was not granted."])
        }
        let source = FOAFeatureSource()
        let frames = source.frames()
        let drain = Task.detached { var n = 0; for await _ in frames { n += 1 }; return n }
        var lines: [String] = []
        do {
            try await source.start(sessionMode: true)
        } catch {
            await source.stop()
            AudioSessionConfigurator.deactivate()
            drain.cancel()
            lines.append("FOA capture failed to start: \(error.localizedDescription)")
            lines.append("isMultichannelAudioModeSupported(.firstOrderAmbisonics): \(source.stats.multichannelModeSupported)")
            return SpikeReport(test: .foaAlone, passed: false, lines: lines)
        }
        let started = Date()
        await countdown(foaAloneSeconds, prompt: "Capturing spatial audio. Keep the phone still.")
        let elapsed = Date().timeIntervalSince(started)
        let stats = source.stats
        await source.stop()
        AudioSessionConfigurator.deactivate()
        let frameCount = await drain.value

        let bps = elapsed > 0 ? Double(stats.buffers) / elapsed : 0
        lines.append("isMultichannelAudioModeSupported(.firstOrderAmbisonics): \(stats.multichannelModeSupported)")
        lines.append("Audio session mode: \(source.sessionResult?.mode ?? "unknown"), route: \(source.sessionResult?.routeDescription ?? "unknown")")
        lines.append("Channels: \(stats.channels), sample rate: \(Int(stats.sampleRate)) Hz, interleaved: \(stats.interleaved)")
        lines.append(String(format: "Buffers: %d in %.1f s (%.1f per second)", stats.buffers, elapsed, bps))
        lines.append("Feature seconds produced: \(frameCount)")
        lines.append("Direction blocks: \(stats.doaBlocks), estimates: \(stats.doaEstimates)")
        let passed = stats.multichannelModeSupported && stats.channels == 4 && Int(stats.sampleRate) == 48_000 && stats.buffers > 0
        return SpikeReport(test: .foaAlone, passed: passed, lines: lines)
    }

    // MARK: - foaWithAR

    private func runFOAWithAR() async -> SpikeReport {
        guard ARWorldTrackingConfiguration.isSupported else {
            return SpikeReport(test: .foaWithAR, passed: false, lines: ["World tracking is not supported on this device."])
        }
        guard await AudioSessionConfigurator.requestRecordPermission() else {
            return SpikeReport(test: .foaWithAR, passed: false, lines: ["Microphone permission was not granted."])
        }
        var lines: [String] = []
        let watcher = SpikeARWatcher()
        let ar = ARSession()
        ar.delegateQueue = DispatchQueue(label: "QuietCompass.SpikeAR")
        ar.delegate = watcher
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.providesAudioData = false
        config.planeDetection = []
        config.isLightEstimationEnabled = false
        if let format = SpikeAR.lowestVideoFormat(ARWorldTrackingConfiguration.supportedVideoFormats) {
            config.videoFormat = format
            lines.append("Video format: \(Int(format.imageResolution.width))×\(Int(format.imageResolution.height)) @ \(format.framesPerSecond) fps")
        }
        ar.run(config, options: [.resetTracking, .removeExistingAnchors])
        // Give tracking a moment before audio starts, as the app does.
        try? await Task.sleep(for: .seconds(2))

        let source = FOAFeatureSource()
        let frames = source.frames()
        let drain = Task.detached { var n = 0; for await _ in frames { n += 1 }; return n }
        var foaError: String?
        do {
            try await source.start(sessionMode: true)
        } catch {
            foaError = error.localizedDescription
        }
        UIApplication.shared.isIdleTimerDisabled = true
        let started = Date()
        await countdown(foaWithARSeconds, prompt: "Walk slowly with the phone held up, camera forward.")
        let elapsed = Date().timeIntervalSince(started)
        let stats = source.stats
        await source.stop()
        AudioSessionConfigurator.deactivate()
        ar.pause()
        UIApplication.shared.isIdleTimerDisabled = false
        let frameCount = await drain.value
        let w = watcher.snapshot()

        if let foaError { lines.append("FOA failed to start: \(foaError)") }
        lines.append(String(format: "FOA buffers: %d in %.0f s (%.1f per second), channels %d, %d Hz",
                            stats.buffers, elapsed, elapsed > 0 ? Double(stats.buffers) / elapsed : 0,
                            stats.channels, Int(stats.sampleRate)))
        lines.append("Feature seconds produced: \(frameCount)")
        lines.append(String(format: "Tracking normal %.0f%% of frames (%d frames)", w.normalShare * 100, w.frames))
        lines.append("Tracking changes: " + (w.changes.isEmpty ? "none" : w.changes.joined(separator: ", ")))
        if !w.errors.isEmpty { lines.append("AR errors: " + w.errors.joined(separator: "; ")) }
        if w.interruptions > 0 { lines.append("AR interruptions: \(w.interruptions)") }
        let sensorFailure = w.errors.contains { $0.localizedCaseInsensitiveContains("sensor") }
        if sensorFailure { lines.append("A required sensor failed: spatial audio and tracking cannot run together.") }
        let audioHealthy = foaError == nil && stats.channels == 4 && Double(stats.buffers) / max(elapsed, 1) > 1
        let passed = audioHealthy && w.errors.isEmpty && w.normalShare >= 0.8
        lines.append(passed ? "Pick mode A." : (audioHealthy ? "Consider mode B (spatial audio + zones)." : "Consider mode C (tracking + mono levels)."))
        return SpikeReport(test: .foaWithAR, passed: passed, lines: lines)
    }

    // MARK: - gainControl

    private func runGainControl() async -> SpikeReport {
        guard await AudioSessionConfigurator.requestRecordPermission() else {
            return SpikeReport(test: .gainControl, passed: false, lines: ["Microphone permission was not granted."])
        }
        var lines: [String] = []
        var measurementDip: Double?
        for preferMeasurement in [true, false] {
            let label = preferMeasurement ? "measurement" : "default"
            switch await gainPass(preferMeasurement: preferMeasurement) {
            case .success(let r):
                lines.append(String(format: "%@ mode (session reports %@): tone alone %.1f dB, with talking %.1f dB (lowest 10%%), dip %.1f dB",
                                    label, r.sessionMode, r.toneDb, r.talkLowDb, r.dipDb))
                if preferMeasurement { measurementDip = r.dipDb }
            case .failure(let message):
                lines.append("\(label) mode: \(message)")
            }
        }
        guard let measurementDip else {
            return SpikeReport(test: .gainControl, passed: nil, lines: lines + ["No verdict: the measurement pass did not complete."])
        }
        let passed = measurementDip <= maxDipDb
        lines.append(passed ? "No gain pumping in measurement mode." : String(format: "The tone dipped more than %.0f dB: gain control is active.", maxDipDb))
        return SpikeReport(test: .gainControl, passed: passed, lines: lines)
    }

    private struct GainResult: Sendable { var sessionMode: String; var toneDb: Double; var talkLowDb: Double; var dipDb: Double }
    private enum GainOutcome: Sendable { case success(GainResult), failure(String) }

    private func gainPass(preferMeasurement: Bool) async -> GainOutcome {
        let source = FOAFeatureSource()
        let frames = source.frames()
        let collector = BandCollector()
        let drain = Task.detached {
            for await f in frames {
                if let b = f.bandsDb, b.count == OctaveBands.centres.count { collector.append(b[2], at: f.t) }
            }
        }
        do {
            try await source.start(sessionMode: preferMeasurement)
        } catch {
            await source.stop()
            drain.cancel()
            AudioSessionConfigurator.deactivate()
            return .failure("could not start capture: \(error.localizedDescription)")
        }
        let mode = source.sessionResult?.mode ?? "unknown"
        let modeName = preferMeasurement ? "measurement" : "default"
        await countdown(3, prompt: "\(modeName.capitalized) mode. Start a steady 1 kHz tone about 1 m from the phone. Nobody talks.")
        let toneStart = Date()
        await countdown(gainPhaseSeconds, prompt: "Tone only. Stay quiet.")
        let talkStart = Date()
        await countdown(gainPhaseSeconds, prompt: "Keep the tone on. Now talk loudly close to the phone.")
        let end = Date()
        await source.stop()
        AudioSessionConfigurator.deactivate()
        await drain.value

        let tone = collector.values(from: toneStart.addingTimeInterval(1), to: talkStart)
        let talk = collector.values(from: talkStart.addingTimeInterval(1), to: end)
        guard tone.count >= 3, talk.count >= 3 else {
            return .failure("not enough audio arrived (\(tone.count) + \(talk.count) seconds)")
        }
        let toneDb = SharedContribution.median(tone)
        let talkLow = RollingStats.percentile(talk, 0.1) ?? toneDb
        return .success(GainResult(sessionMode: mode, toneDb: toneDb, talkLowDb: talkLow, dipDb: max(0, toneDb - talkLow)))
    }

    // MARK: - Helpers

    private func countdown(_ seconds: Int, prompt text: String) async {
        prompt = text
        for s in stride(from: seconds, to: 0, by: -1) {
            secondsLeft = s
            try? await Task.sleep(for: .seconds(1))
        }
        secondsLeft = nil
    }
}

/// Thread-safe list of (time, 1 kHz band level).
private final class BandCollector: Sendable {
    private struct Sample: Sendable { var t: Date; var db: Double }
    private let lock = OSAllocatedUnfairLock<[Sample]>(initialState: [])
    func append(_ v: Double, at t: Date) { lock.withLock { $0.append(Sample(t: t, db: v)) } }
    func values(from: Date, to: Date) -> [Double] {
        lock.withLock { $0.filter { $0.t >= from && $0.t <= to }.map(\.db) }
    }
}

/// Collects tracking changes and errors from the spike's ARSession (on its delegate queue).
private final class SpikeARWatcher: NSObject, ARSessionDelegate, @unchecked Sendable {
    // @unchecked: all state is inside `lock`.
    struct Snapshot: Sendable { var frames = 0; var normalFrames = 0; var changes: [String] = []; var errors: [String] = []; var interruptions = 0
        var normalShare: Double { frames > 0 ? Double(normalFrames) / Double(frames) : 0 }
    }
    private let lock = OSAllocatedUnfairLock(initialState: Snapshot())
    private let start = Date()

    func snapshot() -> Snapshot { lock.withLock { $0 } }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let (state, _) = SpikeAR.trackingState(frame.camera.trackingState)
        lock.withLock { s in
            s.frames += 1
            if state == .normal { s.normalFrames += 1 }
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let (state, reason) = SpikeAR.trackingState(camera.trackingState)
        let label = String(format: "%.0fs %@", Date().timeIntervalSince(start), reason.map { "\(state.rawValue)(\($0))" } ?? state.rawValue)
        lock.withLock { $0.changes.append(label) }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        lock.withLock { $0.errors.append(error.localizedDescription) }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        lock.withLock { $0.interruptions += 1 }
    }
}

/// AR helpers for the spike (the app's own tracking lives in App/PathTracker.swift).
enum SpikeAR {
    /// The format with the lowest frame rate that is still ≥ 30 fps, then the smallest resolution.
    static func lowestVideoFormat(_ formats: [ARConfiguration.VideoFormat]) -> ARConfiguration.VideoFormat? {
        formats.filter { $0.framesPerSecond >= 30 }.min { a, b in
            if a.framesPerSecond != b.framesPerSecond { return a.framesPerSecond < b.framesPerSecond }
            return a.imageResolution.width * a.imageResolution.height < b.imageResolution.width * b.imageResolution.height
        }
    }

    static func trackingState(_ state: ARCamera.TrackingState) -> (TrackingState, String?) {
        switch state {
        case .normal: return (.normal, nil)
        case .notAvailable: return (.notAvailable, nil)
        case .limited(let reason):
            switch reason {
            case .initializing: return (.limited, "initializing")
            case .excessiveMotion: return (.limited, "excessiveMotion")
            case .insufficientFeatures: return (.limited, "insufficientFeatures")
            case .relocalizing: return (.limited, "relocalizing")
            @unknown default: return (.limited, nil)
            }
        }
    }
}
