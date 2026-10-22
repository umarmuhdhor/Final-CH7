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

    /// The keys this app writes. `extension.lastSeenAt` belongs to the extension and is left alone.
    static let appKeys = [
        AppGroup.Key.deviceId, AppGroup.Key.deviceToken, AppGroup.Key.deviceMode, AppGroup.Key.deviceName,
        AppGroup.Key.guardianName, AppGroup.Key.apiBaseURL, AppGroup.Key.aiBaseURL,
    ]

    init(
        defaults: UserDefaults = AppGroup.defaults,
        keychain: KeychainItem = .deviceSession,
        apiBaseURL: URL = AppConfig.apiBaseURL,
        aiBaseURL: URL? = AppConfig.aiBaseURL
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.apiBaseURL = apiBaseURL
        self.aiBaseURL = aiBaseURL
    }

    /// Bearer token for the API. `nil` before onboarding, after delete, or when a backup was restored
    /// onto another iPhone (the Keychain item never moves; the App Group copy is then ignored).
    var token: String? { keychain.read() }

    var deviceId: String? { defaults.string(forKey: AppGroup.Key.deviceId) }

    /// Protected: the guardian from the last join or `GET /devices/me`.
    var guardian: GuardianInfo? { lock.withLock { _guardian } }

    /// After `POST /devices`: Keychain first, so a failed write leaves no half session behind.
    func save(_ registration: DeviceRegistration, name: String, mode: UserMode) throws {
        try keychain.write(registration.token)
        defaults.set(registration.deviceId, forKey: AppGroup.Key.deviceId)
        defaults.set(registration.token, forKey: AppGroup.Key.deviceToken)
        defaults.set(mode.rawValue, forKey: AppGroup.Key.deviceMode)
        defaults.set(name, forKey: AppGroup.Key.deviceName)
        defaults.removeObject(forKey: AppGroup.Key.guardianName)
        lock.withLock { _guardian = nil }
        writeBaseURLs()
    }

    /// Also at every launch, so a new build's URLs reach the extension.
    func writeBaseURLs() {
        defaults.set(apiBaseURL.absoluteString, forKey: AppGroup.Key.apiBaseURL)
        if let aiBaseURL {
            defaults.set(aiBaseURL.absoluteString, forKey: AppGroup.Key.aiBaseURL)
        } else {
            defaults.removeObject(forKey: AppGroup.Key.aiBaseURL)
        }
    }

    /// After `PATCH /devices/me { name }` or a `GET /devices/me` with another name.
    func updateName(_ name: String) {
        defaults.set(name, forKey: AppGroup.Key.deviceName)
    }

    /// `nil` = no guardian (left, removed by the guardian, or never joined): EX-06 stops naming them.
    func setGuardian(_ guardian: GuardianInfo?) {
        lock.withLock { _guardian = guardian }
        if let guardian {
            defaults.set(guardian.name, forKey: AppGroup.Key.guardianName)
        } else {
            defaults.removeObject(forKey: AppGroup.Key.guardianName)
        }
    }

    /// Delete my data, session expired: the extension loses its session at once (P3, P13).
    func clear() {
        keychain.delete()
        for key in Self.appKeys { defaults.removeObject(forKey: key) }
        lock.withLock { _guardian = nil }
    }
}

extension KeychainItem {
    /// The app's device session. The service is the bundle id, so per-developer builds don't collide.
    static let deviceSession = KeychainItem(service: Bundle.main.bundleIdentifier ?? "Shoo", account: "device-session")
}
