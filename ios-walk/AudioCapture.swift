import AVFoundation
import Accelerate
import CoreMedia

// Audio-only AVCaptureSession that asks for First Order Ambisonics (FOA) and hands
// deinterleaved Float samples to a handler on its own serial queue.
//
// Confirmed against Apple docs (developer.apple.com, Oct 2026):
//   AVCaptureDeviceInput.isMultichannelAudioModeSupported(_:)        iOS 18+
//   AVCaptureDeviceInput.multichannelAudioMode = .firstOrderAmbisonics iOS 18+
//   AVCaptureAudioDataOutput.spatialAudioChannelLayoutTag             iOS 26+
//     In FOA mode it MUST be kAudioChannelLayoutTag_Stereo or
//     (kAudioChannelLayoutTag_HOA_ACN_SN3D | 4); otherwise startRunning() raises
//     NSInvalidArgumentException (an ObjC exception Swift cannot catch).
// NOT confirmed: that FOA works in a session with no camera input. The debug panel
// shows what actually arrives, so the first run answers this.

/// What the capture pipeline actually delivers. Shown verbatim in the debug panel.
nonisolated struct StreamInfo: Sendable, Equatable {
    var foaSupported: Bool?          // nil until the input was checked
    var foaRequested = false
    var sessionRunning = false
    var channelCount = 0
    var sampleRate = 0.0
    var formatText = "-"
    var layoutTag: AudioChannelLayoutTag = 0
    var layoutText = "-"
}

/// Levels in dBFS. Relative and uncalibrated: not SPL, never dBA.
nonisolated struct LevelInfo: Sendable {
    var rmsDB: Float                 // channel 0 (W when FOA)
    var peakDB: Float                // channel 0
    var perChannelDB: [Float]

    init(_ channels: [[Float]]) {
        perChannelDB = channels.map { $0.isEmpty ? -120 : Self.dB(vDSP.rootMeanSquare($0)) }
        rmsDB = perChannelDB.first ?? -120
        peakDB = channels.first.map { $0.isEmpty ? -120 : Self.dB(vDSP.maximumMagnitude($0)) } ?? -120
    }

    static func dB(_ x: Float) -> Float { 20 * log10(max(x, 1e-6)) }
}

nonisolated enum CaptureError: LocalizedError {
    case noMicrophone, cannotAddInput, cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noMicrophone: "No audio capture device"
        case .cannotAddInput: "Session refused the microphone input"
        case .cannotAddOutput: "Session refused the audio data output"
        }
    }
}

nonisolated final class AudioCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    typealias Handler = @Sendable (_ channels: [[Float]], _ info: StreamInfo) -> Void
    /// Session events (interrupted, resumed, runtime error) as text for the status line.
    typealias EventHandler = @Sendable (_ event: String, _ running: Bool) -> Void

    // Everything below is touched only on `queue` (configuration and delegate callbacks).
    let queue = DispatchQueue(label: "quietcompass.audio")
    private let handler: Handler
    private let onEvent: EventHandler
    private var observers: [NSObjectProtocol] = []
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private var info = StreamInfo()
    private var lastFormat: CMFormatDescription?

    init(handler: @escaping Handler, onEvent: @escaping EventHandler = { _, _ in }) {
        self.handler = handler
        self.onEvent = onEvent
        super.init()
    }

    /// Restart after an interruption (e.g. if starting ARKit's camera stopped this session).
    func restart() {
        queue.async {
            if !self.session.isRunning { self.session.startRunning() }
            self.onEvent(self.session.isRunning ? "Audio restarted" : "Audio restart failed", self.session.isRunning)
        }
    }

    /// ARKit runs its own capture session for the camera. Whether an audio-only session keeps
    /// running alongside it is unverified, so interruptions are reported instead of silently
    /// freezing the level and direction.
    private func observeSession() {
        let center = NotificationCenter.default
        let interrupted = center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session,
                                             queue: nil) { [weak self] note in
            let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
            self?.onEvent("Audio interrupted (reason \(reason.map(String.init) ?? "?"))", false)
        }
        let ended = center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session,
                                       queue: nil) { [weak self] _ in
            self?.onEvent("Audio interruption ended", true)
        }
        let failed = center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session,
                                        queue: nil) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            self?.onEvent("Audio runtime error \(error?.code ?? 0); tap Restart audio", false)
        }
        observers = [interrupted, ended, failed]
    }

    func start() async throws -> StreamInfo {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try self.configureAndRun()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func configureAndRun() throws -> StreamInfo {
        guard let mic = AVCaptureDevice.default(for: .audio) else { throw CaptureError.noMicrophone }
        let input = try AVCaptureDeviceInput(device: mic)

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CaptureError.cannotAddInput
        }
        session.addInput(input)

        // Checked after addInput: support may depend on the input being attached to a session.
        let foa = input.isMultichannelAudioModeSupported(.firstOrderAmbisonics)
        info.foaSupported = foa
        if foa { input.multichannelAudioMode = .firstOrderAmbisonics }

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CaptureError.cannotAddOutput
        }
        session.addOutput(output)
        if foa {
            // 4 channels, ACN order (W, Y, Z, X), SN3D normalisation, i.e. "AmbiX".
            output.spatialAudioChannelLayoutTag = kAudioChannelLayoutTag_HOA_ACN_SN3D | 4
        }
        info.foaRequested = foa
        output.setSampleBufferDelegate(self, queue: queue)
        session.commitConfiguration()

        observeSession()
        session.startRunning()   // blocking; we are on `queue`, not main
        info.sessionRunning = session.isRunning
        return info
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let format = sampleBuffer.formatDescription,
              let asbd = format.audioStreamBasicDescription else { return }

        if format !== lastFormat {
            lastFormat = format
            info.sessionRunning = true
            info.channelCount = Int(asbd.mChannelsPerFrame)
            info.sampleRate = asbd.mSampleRate
            info.formatText = Self.describe(asbd)
            (info.layoutTag, info.layoutText) = Self.describeLayout(format)
        }

        guard let channels = Self.channels(of: sampleBuffer, asbd: asbd), !channels.isEmpty else { return }
        handler(channels, info)
    }

    // MARK: - Sample extraction

    /// One Float array per channel, scaled to -1...1. Handles interleaved and
    /// non-interleaved LPCM in Float32, Int16 or Int32. Returns nil for anything else
    /// (the format string in the debug panel then tells you what arrived).
    static func channels(of buffer: CMSampleBuffer, asbd: AudioStreamBasicDescription) -> [[Float]]? {
        guard asbd.mFormatID == AudioFormatID(kAudioFormatLinearPCM) else { return nil }
        let isFloat = asbd.mFormatFlags & AudioFormatFlags(kAudioFormatFlagIsFloat) != 0
        let bytes = Int(asbd.mBitsPerChannel) / 8
        guard (isFloat && bytes == 4) || (!isFloat && (bytes == 2 || bytes == 4)) else { return nil }

        let total = Int(asbd.mChannelsPerFrame)
        var out = [[Float]](repeating: [], count: total)
        do {
            try buffer.withAudioBufferList { list, _ in
                var first = 0   // index of the first channel held by the current AudioBuffer
                for audioBuffer in list {
                    // Each AudioBuffer holds mNumberChannels interleaved channels
                    // (1 per buffer when the stream is non-interleaved).
                    let n = Int(audioBuffer.mNumberChannels)
                    defer { first += n }
                    guard let data = audioBuffer.mData, n > 0 else { continue }
                    let frames = Int(audioBuffer.mDataByteSize) / (bytes * n)
                    for c in 0..<n where first + c < total {
                        var dst = [Float](repeating: 0, count: frames)
                        if isFloat {
                            let p = data.assumingMemoryBound(to: Float.self)
                            for i in 0..<frames { dst[i] = p[i * n + c] }
                        } else if bytes == 2 {
                            let p = data.assumingMemoryBound(to: Int16.self)
                            for i in 0..<frames { dst[i] = Float(p[i * n + c]) / 32_768 }
                        } else {
                            let p = data.assumingMemoryBound(to: Int32.self)
                            for i in 0..<frames { dst[i] = Float(p[i * n + c]) / 2_147_483_648 }
                        }
                        out[first + c] = dst
                    }
                }
            }
        } catch {
            return nil
        }
        return out
    }

    // MARK: - Debug descriptions

    static func describe(_ a: AudioStreamBasicDescription) -> String {
        let isFloat = a.mFormatFlags & AudioFormatFlags(kAudioFormatFlagIsFloat) != 0
        let nonInterleaved = a.mFormatFlags & AudioFormatFlags(kAudioFormatFlagIsNonInterleaved) != 0
        let id = a.mFormatID == AudioFormatID(kAudioFormatLinearPCM) ? "LPCM" : fourCC(a.mFormatID)
        return "\(id) \(isFloat ? "Float" : "Int")\(a.mBitsPerChannel) "
            + (nonInterleaved ? "non-interleaved" : "interleaved")
            + " \(a.mChannelsPerFrame)ch"
    }

    static func describeLayout(_ format: CMFormatDescription) -> (AudioChannelLayoutTag, String) {
        guard let layout = CMAudioFormatDescriptionGetChannelLayout(format, sizeOut: nil) else {
            return (0, "no layout attached")
        }
        let tag = layout.pointee.mChannelLayoutTag
        let known: [(AudioChannelLayoutTag, String)] = [
            (kAudioChannelLayoutTag_HOA_ACN_SN3D | 4, "HOA_ACN_SN3D|4 (AmbiX W,Y,Z,X)"),
            (kAudioChannelLayoutTag_HOA_ACN_N3D | 4, "HOA_ACN_N3D|4 (W,Y,Z,X, N3D)"),
            (kAudioChannelLayoutTag_Ambisonic_B_Format, "Ambisonic_B_Format (FuMa W,X,Y,Z)"),
            (kAudioChannelLayoutTag_Stereo, "Stereo"),
            (kAudioChannelLayoutTag_Mono, "Mono"),
        ]
        var name = known.first { $0.0 == tag }?.1 ?? "layout id \(tag >> 16), \(tag & 0xFFFF) ch"
        if tag == kAudioChannelLayoutTag_UseChannelDescriptions {
            // Variable-length C array that follows the struct header.
            let count = Int(layout.pointee.mNumberChannelDescriptions)
            let offset = MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions) ?? 0
            let descriptions = UnsafeRawPointer(layout).advanced(by: offset)
                .assumingMemoryBound(to: AudioChannelDescription.self)
            let labels = (0..<count).map { String(descriptions[$0].mChannelLabel) }
            name = "channel labels [\(labels.joined(separator: ","))]"
        }
        return (tag, String(format: "0x%08X ", tag) + name)
    }

    private static func fourCC(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
