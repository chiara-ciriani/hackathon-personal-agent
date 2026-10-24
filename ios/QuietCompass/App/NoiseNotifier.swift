// Shows noise alerts as local notifications, also while the app is open.
import UIKit
import UserNotifications
import QuietCore

final class NoiseNotifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    // @unchecked: no mutable state; the notification center is thread-safe.
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    /// Asked when a session starts with alerts on, not at launch.
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    @MainActor func post(_ alert: NoiseAlert) {
        let content = UNMutableNotificationContent()
        content.title = "It's loud here"
        content.body = Self.text(for: alert)
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "noise-alert", content: content, trigger: nil))
        if UIApplication.shared.applicationState == .active {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    static func text(for alert: NoiseAlert) -> String {
        switch alert.reason {
        case .sustainedLevel(let over, let seconds):
            "It's been about \(Int(over.rounded())) dB above your comfortable level for \(Int(seconds)) s. Consider a quieter spot."
        case .peaks(let perMinute):
            "Lots of sudden sounds (\(Int(perMinute.rounded())) a minute). Consider a quieter spot."
        }
    }

    // Show the banner even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }
}
