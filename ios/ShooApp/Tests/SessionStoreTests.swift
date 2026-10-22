import Foundation
import Security
import Testing
@testable import Shoo

/// Fase 13: the device session in the Keychain + App Group (contracts/app-group-keys.md, SECURITY §3 P4).
struct SessionStoreTests {
    private func makeStore(ai: URL? = URL(string: "https://ai.shoo.test")) -> (SessionStore, UserDefaults, String) {
        let suite = "test.session.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SessionStore(
            defaults: defaults,
            keychain: KeychainItem(service: "test.\(UUID().uuidString)", account: "device-session"),
            apiBaseURL: URL(string: "https://api.shoo.test")!,
            aiBaseURL: ai
        )
        return (store, defaults, suite)
    }

    private let registration = DeviceRegistration(deviceId: "dev_mom", token: "shoo_abc", avatarId: "avatar_03")

    @Test func saveWritesEveryContractKey() throws {
        let (store, defaults, suite) = makeStore()
        defer { store.clear(); UserDefaults.standard.removePersistentDomain(forName: suite) }
        try store.save(registration, name: "Mom", mode: .protected)
        #expect(defaults.string(forKey: AppGroup.Key.deviceId) == "dev_mom")
        #expect(defaults.string(forKey: AppGroup.Key.deviceToken) == "shoo_abc")
        #expect(defaults.string(forKey: AppGroup.Key.deviceMode) == "protected")
        #expect(defaults.string(forKey: AppGroup.Key.deviceName) == "Mom")
        #expect(defaults.string(forKey: AppGroup.Key.apiBaseURL) == "https://api.shoo.test")
        #expect(defaults.string(forKey: AppGroup.Key.aiBaseURL) == "https://ai.shoo.test")
        #expect(defaults.object(forKey: AppGroup.Key.guardianName) == nil)
        #expect(store.token == "shoo_abc")
        #expect(store.deviceId == "dev_mom")
    }

    @Test func onlyContractKeysAreWritten() throws {
        let (store, defaults, suite) = makeStore()
        defer { store.clear(); UserDefaults.standard.removePersistentDomain(forName: suite) }
        try store.save(registration, name: "Mom", mode: .protected)
        store.setGuardian(GuardianInfo(deviceId: "dev_me", name: "Adhella", avatarId: "avatar_01"))
        let written = Set(defaults.persistentDomain(forName: suite)?.keys.map { $0 } ?? [])
        #expect(written.isSubset(of: Set(SessionStore.appKeys)))
    }

    @Test func missingAIServiceIsNotWritten() throws {
        let (store, defaults, suite) = makeStore(ai: nil)
        defer { store.clear(); UserDefaults.standard.removePersistentDomain(forName: suite) }
        defaults.set("https://old.example", forKey: AppGroup.Key.aiBaseURL)
        try store.save(registration, name: "Mom", mode: .protected)
        #expect(defaults.object(forKey: AppGroup.Key.aiBaseURL) == nil)
    }

    /// P4: the token never syncs to iCloud Keychain or moves to another iPhone with a backup.
    @Test func tokenIsStoredThisDeviceOnly() throws {
        let (store, _, suite) = makeStore()
        defer { store.clear(); UserDefaults.standard.removePersistentDomain(forName: suite) }
        try store.save(registration, name: "Mom", mode: .protected)
        #expect(store.keychain.storedAccessibility() == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    @Test func renameRewritesDeviceName() throws {
        let (store, defaults, suite) = makeStore()
        defer { store.clear(); UserDefaults.standard.removePersistentDomain(forName: suite) }
        try store.save(registration, name: "Mom", mode: .protected)
        store.updateName("Ibu")
        #expect(defaults.string(forKey: AppGroup.Key.deviceName) == "Ibu")
    }

    @Test func guardianNameIsSetAndCleared() throws {
        let (store, defaults, suite) = makeStore()
        defer { store.clear(); UserDefaults.standard.removePersistentDomain(forName: suite) }
        try store.save(registration, name: "Mom", mode: .protected)
        let guardian = GuardianInfo(deviceId: "dev_me", name: "Adhella", avatarId: "avatar_01")
        store.setGuardian(guardian)
        #expect(defaults.string(forKey: AppGroup.Key.guardianName) == "Adhella")
        #expect(store.guardian == guardian)
        store.setGuardian(nil)
        #expect(defaults.object(forKey: AppGroup.Key.guardianName) == nil)
        #expect(store.guardian == nil)
    }

    @Test func clearRemovesTheSessionButNotTheHeartbeat() throws {
        let (store, defaults, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        try store.save(registration, name: "Mom", mode: .protected)
        store.setGuardian(GuardianInfo(deviceId: "dev_me", name: "Adhella", avatarId: "avatar_01"))
        let heartbeat = Date()
        defaults.set(heartbeat, forKey: AppGroup.Key.extensionLastSeenAt)
        store.clear()
        #expect(store.token == nil)
        for key in SessionStore.appKeys { #expect(defaults.object(forKey: key) == nil, "\(key)") }
        #expect(defaults.object(forKey: AppGroup.Key.extensionLastSeenAt) as? Date == heartbeat)
    }

    /// A restored backup brings the App Group copy but not the Keychain item: the app does not use it.
    @Test func appGroupCopyAloneIsNotASession() {
        let (store, defaults, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        defaults.set("shoo_restored", forKey: AppGroup.Key.deviceToken)
        #expect(store.token == nil)
    }
}
