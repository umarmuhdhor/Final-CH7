import Foundation
import UserNotifications

/// GD-06: what a push opens, and the APNs token as the backend stores it. Pure, so tests cover every payload.
/// Links (`shoo://scan/{id}`, `shoo://activity`, `shoo://join`) are parsed by `DeepLink`.
enum NotificationRouter {
    /// `scanId` of a contract push (`{ "aps": …, "scanId": "…" }`), only when it is a plain id (T15):
    /// it ends up in a URL path (`GET /scans/{id}`).
    static func scanId(userInfo: [AnyHashable: Any]) -> String? {
        guard let id = userInfo["scanId"] as? String, APIClient.isPlainSegment(id) else { return nil }
        return id
    }

    /// The device token as lowercase hex, for `PATCH /devices/me { apnsToken }`.
    static func hex(token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}

/// P13: pushes already on the lock screen / in Notification Center carry a family member's name and score.
/// They go when the data they point at goes (delete, remove, disconnect, session end, D-alief-C18).
enum DeliveredPushes {
    @MainActor
    static func clear() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
