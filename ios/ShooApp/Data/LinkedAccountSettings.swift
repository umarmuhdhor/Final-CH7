import Foundation
import Observation

/// PF-01 Protected "Akun Tertaut" switches, "Link terblokir" and the "Situs diperiksa" counter.
///
/// Kept in the App Group so the extension can read the switches and write the counter. The keys are
/// *proposed* (not yet in `ShooShared/AppGroup.swift` or contracts/app-group-keys.md, issue #183
/// for the lead): until the extension uses them the switches change nothing outside the app,
/// and "Situs diperiksa" shows "—". Swap `Key` for `AppGroup.Key` once the lead adds them there.
@MainActor
@Observable
final class LinkedAccountSettings {
    enum Key {
        /// Int, written by the extension: pages checked on this iPhone. Missing = not counted yet.
        static let statsChecked = "stats.checked"
        /// Bool, default `true`: "Kirim link secara otomatis", links checked here go to the guardian.
        static let autoSendLinks = "link.autoSend"
        /// Bool, default `true`: "Bagikan riwayat waspada", the guardian also sees warnings (blocked always).
        static let shareWarnings = "history.shareWarnings"
        /// Bool, default `true`: "Link terblokir", a push when the guardian verifies a link.
        static let notifyLinkVerified = "notify.linkVerified"

        static let all = [statsChecked, autoSendLinks, shareWarnings, notifyLinkVerified]
    }

    @ObservationIgnored private let defaults: UserDefaults

    var autoSendLinks: Bool {
        didSet { defaults.set(autoSendLinks, forKey: Key.autoSendLinks) }
    }

    var shareWarnings: Bool {
        didSet { defaults.set(shareWarnings, forKey: Key.shareWarnings) }
    }

    var notifyLinkVerified: Bool {
        didSet { defaults.set(notifyLinkVerified, forKey: Key.notifyLinkVerified) }
    }

    /// `nil` until the extension writes the counter.
    private(set) var checkedCount: Int?

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        autoSendLinks = defaults.object(forKey: Key.autoSendLinks) as? Bool ?? true
        shareWarnings = defaults.object(forKey: Key.shareWarnings) as? Bool ?? true
        notifyLinkVerified = defaults.object(forKey: Key.notifyLinkVerified) as? Bool ?? true
        checkedCount = defaults.object(forKey: Key.statsChecked) as? Int
    }

    /// The extension may have counted more pages since the screen opened.
    func refresh() {
        checkedCount = defaults.object(forKey: Key.statsChecked) as? Int
    }

    /// Delete account: nothing of this device stays behind (SECURITY §3 P3).
    func clear() {
        autoSendLinks = true
        shareWarnings = true
        notifyLinkVerified = true
        checkedCount = nil
        // After the resets above, whose `didSet` writes the defaults back.
        for key in Key.all { defaults.removeObject(forKey: key) }
    }
}
