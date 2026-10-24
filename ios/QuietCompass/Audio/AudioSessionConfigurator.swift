// Configures AVAudioSession for measurement-grade capture (.record + .measurement = AGC/voice processing off).
import AVFoundation
import os

public enum AudioSessionConfigurator {
    static let log = Logger(subsystem: "QuietCompass", category: "AudioSession")

    public struct Result: Sendable {
        /// "measurement" or "default"; store it in DeviceProfile.audioSessionMode.
        public var mode: String
        public var sampleRate: Double
        public var routeDescription: String
    }

    /// One setCategory(_:mode:options:) call, then activation. Falls back to `.default` mode.
    @discardableResult
    public static func configure(preferMeasurement: Bool = true) throws -> Result {
        let session = AVAudioSession.sharedInstance()
        var modeName = "measurement"
        do {
            guard preferMeasurement else { throw CocoaError(.featureUnsupported) }
            try session.setCategory(.record, mode: .measurement, options: [])
        } catch {
            log.error("measurement mode failed (\(error.localizedDescription)); falling back to default")
            try session.setCategory(.record, mode: .default, options: [])
            modeName = "default"
        }
        try? session.setPreferredSampleRate(48_000)
        try session.setActive(true)
        let route = describeRoute(session.currentRoute)
        log.info("audio session active: mode=\(modeName) sr=\(session.sampleRate) route=\(route)")
        return Result(mode: modeName, sampleRate: session.sampleRate, routeDescription: route)
    }

    public static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    public static func describeRoute(_ route: AVAudioSessionRouteDescription) -> String {
        route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
    }

    /// Microphone permission (iOS 17+ API).
    public static func requestRecordPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
