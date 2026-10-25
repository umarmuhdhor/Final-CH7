import Foundation

/// Safari extension Active/Off (ON-04, PR-04, GD-01, PF-01).
/// Source: the extension's heartbeat `AppGroup.Key.extensionLastSeenAt` — the only allowed signal
/// (ios/ShooApp/CLAUDE.md). Window: `AppGroup.extensionActiveWindow` (D-alief-23).
/// EX-01: `AppGroup.Key.extensionAllSites == false` (Safari access narrowed to some sites) is Off too.
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

    /// Pure rule, testable without the App Group. `allSites` missing means unknown: counts as `true`
    /// (contracts/app-group-keys.md).
    static func evaluate(lastSeen: Date?, allSites: Bool? = nil, now: Date = Date()) -> ExtensionStatus {
        guard let lastSeen else { return .off(lastSeen: nil) }
        // A recent heartbeat from a page Shoo may read does not mean it can protect every site.
        if allSites == false { return .off(lastSeen: lastSeen) }
        let age = now.timeIntervalSince(lastSeen)
        // A heartbeat from the future (clock change) still counts as recent.
        return age < AppGroup.extensionActiveWindow ? .active(lastSeen: lastSeen) : .off(lastSeen: lastSeen)
    }

    /// Reads the heartbeat and the Safari access from the App Group.
    static func current(defaults: UserDefaults = AppGroup.defaults, now: Date = Date()) -> ExtensionStatus {
        evaluate(
            lastSeen: defaults.object(forKey: AppGroup.Key.extensionLastSeenAt) as? Date,
            allSites: defaults.object(forKey: AppGroup.Key.extensionAllSites) as? Bool,
            now: now
        )
    }
}
