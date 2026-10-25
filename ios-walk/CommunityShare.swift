import AVFoundation
import CoreLocation
import Foundation
import Observation

@MainActor @Observable
final class CommunityShare: NSObject, @preconcurrency CLLocationManagerDelegate {
    var sharing = false
    var secondsLeft = 0
    var message = ""
    var mapURL: URL?
    @ObservationIgnored private let location = CLLocationManager()
    @ObservationIgnored private var fix: CLLocation?
    @ObservationIgnored private var locationError: String?
    @ObservationIgnored private var capture: AudioCapture?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let profileID = UUID().uuidString
    @ObservationIgnored private var pending: Data?
    @ObservationIgnored private let session = URLSession(configuration: .ephemeral, delegate: NoAgentRedirect(), delegateQueue: nil)

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func share(model: CompassModel) {
        guard !sharing else { return }
        sharing = true; mapURL = nil
        task = Task {
            defer { capture?.stop(); capture = nil; location.stopUpdatingLocation(); sharing = false; secondsLeft = 0 }
            do {
                // A failed upload retries these exact bytes, never a fabricated or repeated capture.
                if pending == nil {
                    model.stopSensors()
                    guard await AVCaptureDevice.requestAccess(for: .audio) else {
                        throw AgentConnectionError("Allow microphone access in Settings to measure sound.")
                    }
                    fix = nil; locationError = nil
                    message = "Getting your location. The room map is paused."
                    location.requestWhenInUseAuthorization()
                    location.startUpdatingLocation()
                    for _ in 0..<25 {
                        try Task.checkCancellation()
                        if let error = locationError { throw AgentConnectionError(error) }
                        if let fix, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 100,
                           abs(fix.timestamp.timeIntervalSinceNow) < 10 { break }
                        try await Task.sleep(for: .seconds(1))
                    }
                    guard let fix, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 100,
                          abs(fix.timestamp.timeIntervalSinceNow) < 10 else {
                        throw AgentConnectionError("Could not get a recent location within 100 m. Try outdoors.")
                    }
                    let lat = fix.coordinate.latitude, lon = fix.coordinate.longitude
                    guard (37.6...37.85).contains(lat), (-122.55 ... -122.3).contains(lon) else {
                        throw AgentConnectionError("The community map currently covers San Francisco.")
                    }
                    let accumulator = CommunityAccumulator()
                    let audio = AudioCapture(handler: { channels, info in
                        let level = LevelInfo(channels)
                        accumulator.add(level: Double(level.rmsDB), peak: Double(level.peakDB),
                                        samples: channels.first?.count ?? 0, rate: info.sampleRate,
                                        channels: channels.count, time: ProcessInfo.processInfo.systemUptime)
                    })
                    capture = audio
                    _ = try await audio.start()
                    try Task.checkCancellation()
                    for remaining in stride(from: 30, through: 1, by: -1) {
                        secondsLeft = remaining; message = "Measuring sound. Audio stays on your phone."
                        try await Task.sleep(for: .seconds(1))
                    }
                    audio.stop(); capture = nil
                    let summary = try accumulator.summary(now: ProcessInfo.processInfo.systemUptime)
                    let profile = "qc-community-v1:\(profileID):\(Int(summary.rate)):\(summary.channels)"
                    pending = try CommunityPayload.data(id: UUID(), at: Date(), lat: lat, lon: lon,
                                                        rms: summary.rms, spread: summary.spread, profile: profile)
                }
                try Task.checkCancellation()
                message = "Sharing the sound summary…"
                var request = URLRequest(url: AgentProtocol.origin.appendingPathComponent("api/community"))
                request.httpMethod = "POST"; request.timeoutInterval = 15
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = pending
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw AgentConnectionError("Could not upload. Tap Measure and share to retry the same summary.")
                }
                let status = result["status"] as? String
                if status == "rejected" {
                    pending = nil
                    throw AgentConnectionError("This summary was rejected or expired. Measure again.")
                }
                guard status == "accepted" || status == "withheld" else { throw AgentConnectionError("Unexpected server response.") }
                pending = nil
                if let receipt = result["access_receipt"] as? String,
                   receipt.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil {
                    var url = URLComponents(url: AgentProtocol.origin.appendingPathComponent("map-access"), resolvingAgainstBaseURL: false)!
                    url.fragment = "receipt=" + receipt; mapURL = url.url
                }
                message = status == "accepted"
                    ? "Shared. Other contributors can see this sound summary on the community map."
                    : "Summary received. It stays hidden until enough matching measurements are shared. You can measure again."
            } catch {
                message = Task.isCancelled ? "Sharing stopped. Microphone off." : error.localizedDescription
            }
        }
    }

    func cancel() { task?.cancel(); capture?.stop(); location.stopUpdatingLocation() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { fix = locations.last }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code != .locationUnknown { locationError = "Location unavailable. Allow location access in Settings." }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if [.denied, .restricted].contains(manager.authorizationStatus) { locationError = "Allow location access in Settings to share." }
    }
}
