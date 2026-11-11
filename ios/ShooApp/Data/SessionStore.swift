import Foundation

/// The device session after `POST /devices` (fase 13, D-alief-10).
///
/// - The token lives in the Keychain (`AfterFirstUnlockThisDeviceOnly`, SECURITY §3 P4); the app reads it
///   only from there.
/// - The extension can't read our Keychain, so the contract keys (contracts/app-group-keys.md) are
///   copied into the App Group, always through `AppGroup.Key`. Nothing else goes there.
/// - The guardian's avatar is kept in memory only; `GET /devices/me` brings it back (D-alief-C02).
final class SessionStore: @unchecked Sendable {
    let defaults: UserDefaults
    let keychain: KeychainItem
    let apiBaseURL: URL
    let aiBaseURL: URL?

    private let lock = NSLock()
    private var _guardian: GuardianInfo?
    private var _onlineCheckAllowed: Bool
    /// Empties in-memory copies of server data (the favicon cache, fase 22c) when what they show is no
    /// longer this phone's to see (P13).
    private let forgetCachedDataHandler: @Sendable () -> Void

    /// The keys this app writes. `extension.lastSeenAt` belongs to the extension and is left alone.
    /// The Protected "Akun Tertaut" switches go too: the extension reads them, so an old account's `false`
    /// would stop the next account's scans (fase 27h, F-A13).
    static let appKeys = [
        AppGroup.Key.deviceId, AppGroup.Key.deviceToken, AppGroup.Key.deviceMode, AppGroup.Key.deviceName,
        AppGroup.Key.guardianName, AppGroup.Key.apiBaseURL, AppGroup.Key.aiBaseURL,
        AppGroup.Key.statsChecked, AppGroup.Key.statsLastCheckedAt,
        LinkedAccountSettings.Key.autoSendLinks, LinkedAccountSettings.Key.shareWarnings,
        LinkedAccountSettings.Key.notifyLinkVerified,
    ]

    init(
        defaults: UserDefaults = AppGroup.defaults,
        keychain: KeychainItem = .deviceSession,
        apiBaseURL: URL = AppConfig.apiBaseURL,
        aiBaseURL: URL? = AppConfig.aiBaseURL,
        onlineCheckAllowed: Bool = false,
        forgetCachedData: @escaping @Sendable () -> Void = { CachedFaviconLoader.shared.clear() }
    ) {
        _onlineCheckAllowed = onlineCheckAllowed
        forgetCachedDataHandler = forgetCachedData
        self.defaults = defaults
        self.keychain = keychain
        self.apiBaseURL = apiBaseURL
        self.aiBaseURL = aiBaseURL
    }

    /// Bearer token for the API. `nil` before onboarding, after delete, or when a backup was restored
    /// onto another iPhone (the Keychain item never moves; the App Group copy is then ignored).
    /// Throws when the Keychain can't be read right now (locked before the first unlock).
    func readToken() throws -> String? { try keychain.read() }

    /// `readToken()` with a locked Keychain read as "no token" (tests, simple checks).
    var token: String? { try? readToken() }

    var deviceId: String? { defaults.string(forKey: AppGroup.Key.deviceId) }

    /// Protected: the guardian from the last join or `GET /devices/me`.
    var guardian: GuardianInfo? { lock.withLock { _guardian } }

    /// After `POST /devices`: Keychain first, so a failed write leaves no half session behind.
    /// One lock around every write, so a `clear()` from a 401 can't interleave with it.
    func save(_ registration: DeviceRegistration, name: String, mode: UserMode) throws {
        try lock.withLock {
            try keychain.write(registration.token)
            defaults.set(registration.deviceId, forKey: AppGroup.Key.deviceId)
            defaults.set(registration.token, forKey: AppGroup.Key.deviceToken)
            defaults.set(mode.rawValue, forKey: AppGroup.Key.deviceMode)
            defaults.set(name, forKey: AppGroup.Key.deviceName)
            defaults.removeObject(forKey: AppGroup.Key.guardianName)
            _guardian = nil
            writeBaseURLsLocked()
        }
        // A new device (registration, guardian → protected) sees other scans.
        forgetCachedData()
    }

    /// Also at every launch, so a new build's URLs reach the extension.
    func writeBaseURLs() {
        lock.withLock { writeBaseURLsLocked() }
    }

    /// The person's answer (`DataConsent`). The extension calls `/analyze` only with `aiBaseURL`, so without
    /// the key no page leaves the phone for a check and nothing reaches DeepSeek. No new contract key needed.
    func setOnlineCheck(allowed: Bool) {
        lock.withLock {
            _onlineCheckAllowed = allowed
            if hasSessionLocked { writeBaseURLsLocked() }
        }
    }

    /// After `PATCH /devices/me { name }` or a `GET /devices/me` with another name.
    /// A no-op once the session is gone: a late answer never brings data back after delete (P13).
    func updateName(_ name: String) {
        lock.withLock { updateNameLocked(name) }
    }

    /// `nil` = no guardian (left, removed by the guardian, or never joined): EX-06 stops naming them.
    func setGuardian(_ guardian: GuardianInfo?) {
        let lostGuardian = lock.withLock { setGuardianLocked(guardian) }
        // Left the family, or the guardian removed this phone. Not on a guardian's every
        // `GET /devices/me` (never had one).
        if lostGuardian { forgetCachedData() }
    }

    /// `GET /devices/me`: name and guardian, only while `usedToken` is still the session's token. One lock
    /// around the check and the writes, so a switch to a new device ("Punya kode undangan?") can't land
    /// between them and get the old device's profile (fase 27h, F-A12). `false` = not written.
    @discardableResult
    func applyProfile(name: String, guardian: GuardianInfo?, ifToken usedToken: String) -> Bool {
        let result = lock.withLock { () -> (applied: Bool, lostGuardian: Bool) in
            guard (try? keychain.read()) == usedToken else { return (false, false) }
            updateNameLocked(name)
            return (true, setGuardianLocked(guardian))
        }
        if result.lostGuardian { forgetCachedData() }
        return result.applied
    }

    private func updateNameLocked(_ name: String) {
        guard hasSessionLocked else { return }
        defaults.set(name, forKey: AppGroup.Key.deviceName)
    }

    /// `true` when a guardian this phone had is now gone.
    private func setGuardianLocked(_ guardian: GuardianInfo?) -> Bool {
        guard guardian == nil || hasSessionLocked else { return false }
        let hadGuardian = _guardian != nil || defaults.string(forKey: AppGroup.Key.guardianName) != nil
        _guardian = guardian
        if let guardian {
            defaults.set(guardian.name, forKey: AppGroup.Key.guardianName)
        } else {
            defaults.removeObject(forKey: AppGroup.Key.guardianName)
        }
        return hadGuardian && guardian == nil
    }

    /// Delete my data, session expired: the extension loses its session at once (P3, P13).
    func clear() {
        lock.withLock {
            keychain.delete()
            for key in Self.appKeys { defaults.removeObject(forKey: key) }
            _guardian = nil
        }
        forgetCachedData()
    }

    /// Also from `ApiRepository.removeMember`. Outside `lock`: the
    /// cache has its own.
    func forgetCachedData() { forgetCachedDataHandler() }

    private var hasSessionLocked: Bool { defaults.string(forKey: AppGroup.Key.deviceId) != nil }

    private func writeBaseURLsLocked() {
        // Release builds only ever hand the extension HTTPS endpoints (P5); plain HTTP is `wrangler dev`.
        if Self.isAllowed(apiBaseURL) {
            defaults.set(apiBaseURL.absoluteString, forKey: AppGroup.Key.apiBaseURL)
        } else {
            defaults.removeObject(forKey: AppGroup.Key.apiBaseURL)
        }
        if _onlineCheckAllowed, let aiBaseURL, Self.isAllowed(aiBaseURL) {
            defaults.set(aiBaseURL.absoluteString, forKey: AppGroup.Key.aiBaseURL)
        } else {
            defaults.removeObject(forKey: AppGroup.Key.aiBaseURL)
        }
    }

    static func isAllowed(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        #if DEBUG
        return url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host() ?? "")
        #else
        return false
        #endif
    }
}

extension KeychainItem {
    /// The app's device session. The service is the bundle id, so per-developer builds don't collide.
    static let deviceSession = KeychainItem(service: Bundle.main.bundleIdentifier ?? "Shoo", account: "device-session")
}
