import Foundation

/// Safari extension Active/Off (ON-04, PR-04, GD-01, PF-01).
/// Source: the extension's heartbeat `AppGroup.Key.extensionLastSeenAt` — the only allowed signal
/// (ios/ShooApp/CLAUDE.md). Window: `AppGroup.extensionActiveWindow` (D-alief-23).
enum ExtensionStatus: Equatable, Sendable {
    case active(lastSeen: Date)
    case off(lastSeen: Date?)

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var lastSeen: Date? {
        switch self {
        case .active(let date): date
        case .off(let date): date
        }
    }

    /// Pure rule, testable without the App Group.
    static func evaluate(lastSeen: Date?, now: Date = Date()) -> ExtensionStatus {
        guard let lastSeen else { return .off(lastSeen: nil) }
        let age = now.timeIntervalSince(lastSeen)
        // A heartbeat from the future (clock change) still counts as recent.
        return age < AppGroup.extensionActiveWindow ? .active(lastSeen: lastSeen) : .off(lastSeen: lastSeen)
    }

    /// Reads the heartbeat from the App Group.
    static func current(defaults: UserDefaults = AppGroup.defaults, now: Date = Date()) -> ExtensionStatus {
        evaluate(lastSeen: defaults.object(forKey: AppGroup.Key.extensionLastSeenAt) as? Date, now: now)
    }
}
