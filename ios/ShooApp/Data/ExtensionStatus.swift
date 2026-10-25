import Foundation
import SafariServices

/// Safari extension Active/Off (ON-04, PR-04, GD-01, PF-01).
/// Sources:
/// - Safari's own switch (iOS 26.2+, `SFSafariExtensionManager`): Off the moment it is switched off,
///   Active as soon as it is on, without waiting for a page load.
/// - The extension's heartbeat `AppGroup.Key.extensionLastSeenAt`, the only signal before iOS 26.2.
///   Window: `AppGroup.extensionActiveWindow` (D-alief-23).
/// EX-01: `AppGroup.Key.extensionAllSites == false` (Safari access narrowed to some sites) is Off too.
enum ExtensionStatus: Equatable, Sendable {
    /// `lastSeen` is nil when Safari reports the switch on but no page has loaded since.
    case active(lastSeen: Date?)
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
    /// (contracts/app-group-keys.md). `enabled` missing (before iOS 26.2, or Safari can't tell): the
    /// heartbeat decides alone.
    static func evaluate(lastSeen: Date?, allSites: Bool? = nil, enabled: Bool? = nil, now: Date = Date()) -> ExtensionStatus {
        // Switched off in Settings: a heartbeat from before still sits in the App Group.
        if enabled == false { return .off(lastSeen: lastSeen) }
        // A recent heartbeat from a page Shoo may read does not mean it can protect every site.
        if allSites == false { return .off(lastSeen: lastSeen) }
        if enabled == true { return .active(lastSeen: lastSeen) }
        guard let lastSeen else { return .off(lastSeen: nil) }
        let age = now.timeIntervalSince(lastSeen)
        // A heartbeat from the future (clock change) still counts as recent.
        return age < AppGroup.extensionActiveWindow ? .active(lastSeen: lastSeen) : .off(lastSeen: lastSeen)
    }

    /// Reads the heartbeat and the Safari access from the App Group, with Safari's switch if known.
    static func current(defaults: UserDefaults = AppGroup.defaults, enabled: Bool? = nil, now: Date = Date()) -> ExtensionStatus {
        evaluate(
            lastSeen: defaults.object(forKey: AppGroup.Key.extensionLastSeenAt) as? Date,
            allSites: defaults.object(forKey: AppGroup.Key.extensionAllSites) as? Bool,
            enabled: enabled,
            now: now
        )
    }

    /// `current()` with Safari's switch asked first (every screen that shows the status).
    static func load() async -> ExtensionStatus {
        current(enabled: await safariSwitch())
    }

    /// Safari's switch for Shoo's extension, or nil before iOS 26.2 or when Safari can't tell.
    static func safariSwitch() async -> Bool? {
        guard #available(iOS 26.2, *), let identifier = ExtensionSetup.extensionIdentifier else { return nil }
        return await withCheckedContinuation { continuation in
            SFSafariExtensionManager.getStateOfExtension(withIdentifier: identifier) { state, error in
                if let error { Log.app.error("Reading the Safari extension state failed", error) }
                continuation.resume(returning: state?.isEnabled)
            }
        }
    }
}
