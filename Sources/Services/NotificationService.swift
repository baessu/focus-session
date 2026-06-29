import Foundation
import UserNotifications
import Observation

/// Schedules the "time's up" local notification and presents it as a banner
/// even when the app is frontmost. One pending request at a time.
@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let completionID = "focus.session.completion"
    private var didRequestAuth = false

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        guard !didRequestAuth else { return }
        didRequestAuth = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Pre-schedules the completion alert `seconds` from now.
    func scheduleCompletion(after seconds: TimeInterval, taskName: String) {
        cancelCompletion()
        guard seconds >= 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time's up"
        let trimmed = taskName.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = trimmed.isEmpty
            ? "Your focus session reached its goal."
            : "“\(trimmed)” — your focus time is complete."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: completionID, content: content, trigger: trigger)
        center.add(request)
    }

    func cancelCompletion() {
        center.removePendingNotificationRequests(withIdentifiers: [completionID])
    }

    // Show the banner + sound even while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
