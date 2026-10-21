import Foundation

/// Shared storage between the app and its extensions. See contracts/app-group-keys.md.
enum AppGroup {
    static let id = "group.com.shoo.app"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }

    enum Key {
        static let deviceId = "device.id"
        static let deviceToken = "device.token"
        static let deviceMode = "device.mode"
        static let deviceName = "device.name"
        static let guardianName = "guardian.name"
        static let extensionLastSeenAt = "extension.lastSeenAt"
        static let apiBaseURL = "api.baseURL"
        static let aiBaseURL = "ai.baseURL"
    }

    /// Heartbeat older than this means the extension is treated as Off.
    static let extensionActiveWindow: TimeInterval = 60 * 60 * 24
}

enum UserMode: String, Codable {
    case guardian
    case protected
}
