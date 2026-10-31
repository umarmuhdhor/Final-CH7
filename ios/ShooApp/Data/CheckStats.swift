import Foundation

/// What the extension has checked on this iPhone (Activity empty states, PR-05): how many pages and
/// when the last one was. Numbers and a time only, never addresses.
///
/// The keys are *proposed* (issue #183, `stats.lastCheckedAt` added there): not yet in
/// `ShooShared/AppGroup.swift` or contracts/app-group-keys.md. Until the extension writes them both
/// are nil and Activity falls back to "Safari extension on". Swap `Key` for `AppGroup.Key` once the
/// lead adds them. `stats.checked` is the same key PF-01 reads for "Situs diperiksa".
struct CheckStats: Equatable, Sendable {
    enum Key {
        /// Int, written by the extension: pages checked on this iPhone, all verdicts.
        static let checked = "stats.checked"
        /// Date, written by the extension: when it last checked a page.
        static let lastCheckedAt = "stats.lastCheckedAt"
    }

    /// nil until the extension writes the counter.
    var checked: Int?
    var lastCheckedAt: Date?

    static func current(defaults: UserDefaults = AppGroup.defaults) -> CheckStats {
        CheckStats(
            checked: defaults.object(forKey: Key.checked) as? Int,
            lastCheckedAt: defaults.object(forKey: Key.lastCheckedAt) as? Date
        )
    }

    /// Delete my data: nothing of this device stays behind (SECURITY §3 P3).
    static func clear(defaults: UserDefaults = AppGroup.defaults) {
        defaults.removeObject(forKey: Key.checked)
        defaults.removeObject(forKey: Key.lastCheckedAt)
    }
}
