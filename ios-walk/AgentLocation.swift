import CoreLocation
import Foundation
import Observation

@MainActor @Observable
final class AgentLocation: NSObject, @preconcurrency CLLocationManagerDelegate {
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var authorizationWaiter: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var locationWaiter: CheckedContinuation<AgentLocationPoint?, Never>?
    @ObservationIgnored private var authorizationRequestID: UUID?
    @ObservationIgnored private var locationRequestID: UUID?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Called only after the user taps Allow agent analysis.
    func requestPermission() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                authorizationWaiter = continuation
                let requestID = UUID()
                authorizationRequestID = requestID
                manager.requestWhenInUseAuthorization()
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(8))
                    guard self?.authorizationRequestID == requestID else { return }
                    self?.finishAuthorization(self?.isAuthorized ?? false)
                }
            }
        @unknown default:
            return false
        }
    }

    /// Fetches one fresh fix for this measurement; no location history is retained.
    func currentPoint() async -> AgentLocationPoint? {
        guard isAuthorized else { return nil }
        return await withCheckedContinuation { continuation in
            locationWaiter = continuation
            let requestID = UUID()
            locationRequestID = requestID
            manager.requestLocation()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard self?.locationRequestID == requestID else { return }
                self?.finishLocation(nil)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard authorizationWaiter != nil else { return }
        finishAuthorization(isAuthorized)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= 100, abs(fix.timestamp.timeIntervalSinceNow) <= 10 else {
            finishLocation(nil)
            return
        }
        // Three decimals is roughly a 100 m grid; the exact GPS fix never leaves the phone.
        finishLocation(AgentLocationPoint(lat: (fix.coordinate.latitude * 1000).rounded() / 1000,
                                          lon: (fix.coordinate.longitude * 1000).rounded() / 1000))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishLocation(nil)
    }

    private var isAuthorized: Bool {
        [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus)
    }

    private func finishAuthorization(_ allowed: Bool) {
        authorizationWaiter?.resume(returning: allowed)
        authorizationWaiter = nil
        authorizationRequestID = nil
    }

    private func finishLocation(_ point: AgentLocationPoint?) {
        locationWaiter?.resume(returning: point)
        locationWaiter = nil
        locationRequestID = nil
    }
}
