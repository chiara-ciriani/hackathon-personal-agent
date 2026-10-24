// Builds the DeviceProfile that tags every session. Levels are only compared within one profile.
import Foundation
import QuietCore

enum DeviceProfileBuilder {
    static func make(captureMode: CaptureMode, audioSessionMode: String, sampleRate: Double) -> DeviceProfile {
        DeviceProfile(model: modelIdentifier(), osVersion: osVersion(), captureMode: captureMode,
                      audioSessionMode: audioSessionMode, sampleRateHz: Int(sampleRate.rounded()),
                      appVersion: appVersion())
    }

    /// e.g. "iPhone17,1" on a device, "Simulator iPhone17,1" in the Simulator.
    static func modelIdentifier() -> String {
        #if targetEnvironment(simulator)
        if let id = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return "Simulator \(id)" }
        return "Simulator"
        #else
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.isEmpty ? "iPhone" : machine
        #endif
    }

    static func osVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
                                  : "\(v.majorVersion).\(v.minorVersion)"
    }

    static func appVersion(bundle: Bundle = .main) -> String {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }

    /// The `quality.capture_profile` string of a shared contribution: model + capture mode + audio session mode.
    static func captureProfileLabel(_ profile: DeviceProfile) -> String {
        captureProfileLabel(model: profile.model, captureMode: profile.captureMode.rawValue,
                            audioSessionMode: profile.audioSessionMode)
    }

    static func captureProfileLabel(model: String, captureMode: String, audioSessionMode: String) -> String {
        "\(model)/mode-\(captureMode)/\(audioSessionMode)"
    }
}
