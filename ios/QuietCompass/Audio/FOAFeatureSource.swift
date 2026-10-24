// Modes A/B: first-order ambisonics from the built-in mics via AVCaptureSession (iOS 26 spatial capture).
// Levels/bands come from the W (omni) channel; DOA from all four channels.
import AVFoundation
import CoreMedia
import QuietCore
import os

/// Counters the spike harness and Diagnostics screen read.
public struct CaptureStats: Sendable {
    public var buffers = 0
    public var channels = 0
    public var sampleRate: Double = 0
    public var interleaved = false
    public var multichannelModeSupported = false
    public var lastBufferMidTime: Date?
    public var doaBlocks = 0
    public var doaEstimates = 0
    public var lastAbstention: String?
    public var lastWBandDb: [Double]?
}

public enum FOACaptureError: Error, LocalizedError {
    case noMicrophone, ambisonicsUnsupported, cannotAddInput, cannotAddOutput
    public var errorDescription: String? {
        switch self {
        case .noMicrophone: "No built-in microphone"
        case .ambisonicsUnsupported: "First-order ambisonics capture is not supported on this device"
        case .cannotAddInput: "Could not add the microphone input"
        case .cannotAddOutput: "Could not add the audio data output"
        }
    }
}

public final class FOAFeatureSource: NSObject, FeatureSource, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    // @unchecked: all mutable DSP state lives on `queue` (the delegate queue); `stats` is lock-guarded.
    public let name = "FOA (AVCaptureSession)"
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "QuietCompass.FOAFeatureSource")
    private let classifier: SoundClassifier?
    private let statsLock = OSAllocatedUnfairLock(initialState: CaptureStats())
    private let log = Logger(subsystem: "QuietCompass", category: "FOA")

    private var extractor: LevelFeatureExtractor?
    private var doa: FOADirectionEstimator?
    private var latestDoa: DirectionEstimate?
    private var continuation: AsyncStream<FeatureFrame>.Continuation?
    private var configured = false

    /// Axis calibration applied before DOA; set before start() (or it takes effect on the next start).
    public var calibration: FOAAxisCalibration = .identity
    public var doaConfiguration = FOADirectionConfiguration()
    /// Mode A: returns device→world rotation (ambisonic axes) at a given time, built from the ARKit camera
    /// transform. nil (mode B) keeps DOA in the device frame.
    public var deviceToWorld: (@Sendable (Date) -> Matrix3?)?
    /// Raw blocks for the calibration flow / bench (called on the capture queue).
    public var onDirectionBlock: (@Sendable (FOADirectionBlock) -> Void)?
    /// Raw omni samples for the gain-control spike (called on the capture queue).
    public var onOmniSamples: (@Sendable (UnsafeBufferPointer<Float>, Double) -> Void)?
    public private(set) var sessionResult: AudioSessionConfigurator.Result?

    public init(classifier: SoundClassifier? = nil) {
        self.classifier = classifier
        super.init()
    }

    public var stats: CaptureStats { statsLock.withLock { $0 } }

    public func frames() -> AsyncStream<FeatureFrame> {
        let (stream, cont) = AsyncStream<FeatureFrame>.makeStream(bufferingPolicy: .bufferingNewest(32))
        queue.sync { continuation?.finish(); continuation = cont }
        return stream
    }

    public func start(sessionMode preferMeasurement: Bool) async throws {
        sessionResult = try AudioSessionConfigurator.configure(preferMeasurement: preferMeasurement)
        if !configured { try configure() }
        let cal = calibration, cfg = doaConfiguration
        queue.sync {
            extractor = nil   // created on first buffer, once the sample rate is known
            doa = FOADirectionEstimator(configuration: cfg, calibration: cal)
            latestDoa = nil
        }
        statsLock.withLock { $0 = CaptureStats(multichannelModeSupported: $0.multichannelModeSupported) }
        // startRunning blocks; keep it off the main actor.
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async { self.session.startRunning(); c.resume() }
        }
    }

    public func start() async throws { try await start(sessionMode: true) }

    public func stop() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async {
                self.session.stopRunning()
                self.continuation?.finish()
                self.continuation = nil
                c.resume()
            }
        }
        classifier?.stop()
    }

    private func configure() throws {
        guard let mic = AVCaptureDevice.default(for: .audio) else { throw FOACaptureError.noMicrophone }
        let input = try AVCaptureDeviceInput(device: mic)
        // VERIFY: iOS 26 API names — AVCaptureDeviceInput.isMultichannelAudioModeSupported(_:) and
        // .multichannelAudioMode = .firstOrderAmbisonics (WWDC25 "Enhance your app's audio recording capabilities").
        let supported = input.isMultichannelAudioModeSupported(.firstOrderAmbisonics)
        statsLock.withLock { $0.multichannelModeSupported = supported }
        guard supported else { throw FOACaptureError.ambisonicsUnsupported }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.automaticallyConfiguresApplicationAudioSession = false
        guard session.canAddInput(input) else { throw FOACaptureError.cannotAddInput }
        session.addInput(input)
        input.multichannelAudioMode = .firstOrderAmbisonics
        guard session.canAddOutput(output) else { throw FOACaptureError.cannotAddOutput }
        session.addOutput(output)
        // VERIFY: property name/type on iOS 26; expects AudioChannelLayoutTag. Confirm buffers arrive as
        // 4 channels in ACN order (W, Y, Z, X) with SN3D normalization — run the axis calibration.
        output.spatialAudioChannelLayoutTag = kAudioChannelLayoutTag_HOA_ACN_SN3D | 4
        output.setSampleBufferDelegate(self, queue: queue)
        configured = true
    }

    // MARK: - Delegate (runs on `queue`)

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard let fmt = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee else { return }
        let channels = Int(asbd.mChannelsPerFrame)
        let sr = asbd.mSampleRate
        let frames = sampleBuffer.numSamples
        guard channels > 0, frames > 0 else { return }

        guard let planar = Self.floatChannels(sampleBuffer, asbd: asbd, frames: frames) else {
            log.error("unsupported sample format flags=\(asbd.mFormatFlags) bits=\(asbd.mBitsPerChannel)")
            return
        }

        // Timestamps: presentation time is on the session's sync clock; convert to host time.
        let pts = sampleBuffer.presentationTimeStamp
        let hostPts = CMSyncConvertTime(pts, from: session.synchronizationClock ?? CMClockGetHostTimeClock(),
                                        to: CMClockGetHostTimeClock())
        let start = Self.date(forHostSeconds: hostPts.seconds)
        let mid = start.addingTimeInterval(0.5 * Double(frames) / sr)

        statsLock.withLock {
            $0.buffers += 1; $0.channels = channels; $0.sampleRate = sr
            $0.interleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            $0.lastBufferMidTime = mid
        }

        // Omni = W = channel 0 in ACN order (also correct for a 1-channel fallback).
        let w = planar[0]
        w.withUnsafeBufferPointer { onOmniSamples?($0, sr); classifier?.feed($0, sampleRate: sr) }

        if channels >= 4, var est = doa {
            let blocks = est.append(acn: Array(planar[0..<4]))
            doa = est
            for b in blocks {
                onDirectionBlock?(b)
                statsLock.withLock {
                    $0.doaBlocks += 1
                    if b.estimate != nil { $0.doaEstimates += 1 }
                    $0.lastAbstention = b.abstention?.rawValue
                }
                if var e = b.estimate {
                    if let rot = deviceToWorld?(mid) { e = DirectionMath.toWorld(e, deviceToWorld: rot) }
                    // Keep the most confident estimate of the current second.
                    if latestDoa == nil || e.confidence > latestDoa!.confidence { latestDoa = e }
                }
            }
        }

        if extractor == nil || extractor!.sampleRate != sr {
            extractor = LevelFeatureExtractor(sampleRate: sr, spectrum: VDSPPowerSpectrum())
        }
        guard var ex = extractor else { return }
        let seconds = ex.append(w, startTime: start)
        extractor = ex
        for s in seconds {
            statsLock.withLock { $0.lastWBandDb = s.bandsDb }
            let snap = classifier?.takeSnapshot()
            continuation?.yield(s.featureFrame(speechShare: snap?.speech, classes: snap?.top ?? [], doa: latestDoa))
            latestDoa = nil
        }
    }

    /// Converts the sample buffer to one Float array per channel, handling interleaved and
    /// non-interleaved layouts, Float32 and Int16.
    static func floatChannels(_ sb: CMSampleBuffer, asbd: AudioStreamBasicDescription, frames: Int) -> [[Float]]? {
        let channels = Int(asbd.mChannelsPerFrame)
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isNonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        guard (isFloat && asbd.mBitsPerChannel == 32) || (!isFloat && asbd.mBitsPerChannel == 16) else { return nil }
        var out = [[Float]](repeating: [Float](repeating: 0, count: frames), count: channels)
        do {
            try sb.withAudioBufferList { abl, _ in
                for (bi, buffer) in abl.enumerated() {
                    guard let data = buffer.mData else { continue }
                    let chInBuf = Int(buffer.mNumberChannels)
                    let n = min(frames, Int(buffer.mDataByteSize) / max(1, chInBuf * Int(asbd.mBitsPerChannel / 8)))
                    for f in 0..<n {
                        for c in 0..<chInBuf {
                            let ch = isNonInterleaved ? bi : c
                            guard ch < channels else { continue }
                            let idx = f * chInBuf + c
                            out[ch][f] = isFloat
                                ? data.assumingMemoryBound(to: Float.self)[idx]
                                : Float(data.assumingMemoryBound(to: Int16.self)[idx]) / 32768
                        }
                    }
                }
            }
        } catch {
            return nil
        }
        return out
    }

    static func date(forHostSeconds s: Double) -> Date {
        let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        return Date().addingTimeInterval(s - now)
    }
}
