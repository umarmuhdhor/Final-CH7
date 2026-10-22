import UserNotifications

/// The app's view of the notification permission (ON-05). Provisional and ephemeral count as allowed.
enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional, .ephemeral: self = .authorized
        case .denied: self = .denied
        default: self = .notDetermined
        }
    }
}

/// Asks for notifications just in time (SECURITY §3 P7). A protocol so tests and UI tests never see a system alert.
protocol NotificationPermission: Sendable {
    func status() async -> NotificationAuthorization
    /// Shows the system prompt (once per install) and returns the answer.
    func request() async -> NotificationAuthorization
}

/// The real permission, through `UNUserNotificationCenter`.
struct SystemNotificationPermission: NotificationPermission {
    func status() async -> NotificationAuthorization {
        NotificationAuthorization(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    func request() async -> NotificationAuthorization {
        do {
            // Pushes carry text and sound only (contracts/api.md "Push payloads"), so no badge.
            // The APNs registration follows in `AppEnvironment.registerForPushIfAllowed` (Guardian only, C14).
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.app.error("Notification permission request failed", error)
        }
        return await status()
    }
}

#if DEBUG
/// Fixed answer for UI tests and screenshots (`-UITestNotifications granted|denied`, DEBUG only).
@MainActor
final class FixedNotificationPermission: NotificationPermission {
    let answer: NotificationAuthorization
    private var asked = false

    init(answer: NotificationAuthorization) {
        self.answer = answer
    }

    func status() async -> NotificationAuthorization { asked ? answer : .notDetermined }

    func request() async -> NotificationAuthorization {
        asked = true
        return answer
    }
}
#endif

/// The small "Notifications are off" banner on Home (ON-05).
enum NotificationReminder {
    /// Only the Guardian gets pushes (contracts/api.md), so only the Guardian is reminded.
    static func isShown(status: NotificationAuthorization, mode: UserMode?) -> Bool {
        mode == .guardian && status != .authorized
    }
}
