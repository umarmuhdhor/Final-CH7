import Foundation
import Testing
import UIKit
@testable import Shoo

/// Fase 13: `AppEnvironment` with the real repository — registration, foreground sync, session expiry.
@MainActor
struct AppEnvironmentSessionTests {
    private nonisolated static let registered = HostStubProtocol.Reply.json(
        201, #"{"deviceId":"dev_new","token":"shoo_fresh_token","avatarId":"avatar_05"}"#
    )
    private nonisolated static let ok = HostStubProtocol.Reply.json(200, #"{"ok":true}"#)
    private nonisolated static let profile = HostStubProtocol.Reply.json(
        200, #"{"deviceId":"dev_new","name":"Rina","avatarId":"avatar_05","mode":"guardian","language":"en","guardian":null}"#
    )

    private func environment(
        server: StubServer, language: AppLanguage = .english, mode: UserMode? = nil,
        extensionStatus: @escaping () -> ExtensionStatus = { .off(lastSeen: nil) }
    ) -> AppEnvironment {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test.settings.\(UUID().uuidString)")!)
        settings.language = language
        if let mode { settings.chooseMode(mode) }
        return AppEnvironment(
            repository: server.repository(), settings: settings, session: server.session, extensionStatus: extensionStatus
        )
    }

    @Test func demoUsesFixturesAndTouchesNoSession() {
        let server = StubServer(token: nil)
        let env = environment(server: server)
        env.startDemo()
        #expect(env.repository is MockRepository)
        #expect(env.session == nil)
        #expect(env.settings.demoMode)
        #expect(server.session.defaults.string(forKey: AppGroup.Key.deviceId) == nil)
    }

    @Test func demoIsNotOfferedToARegisteredDevice() {
        let server = StubServer(token: "shoo_token")
        let env = environment(server: server, mode: .guardian)
        env.startDemo()
        #expect(!(env.repository is MockRepository))
        #expect(!env.settings.demoMode)
    }

    @Test func registrationSavesTheSessionBeforeTheMode() async throws {
        let server = StubServer(token: nil)
        server.reply { _ in Self.registered }
        let env = environment(server: server)
        _ = try await env.register(name: "Rina", mode: .guardian)
        #expect(env.settings.mode == .guardian)
        #expect(server.session.token == "shoo_fresh_token")
        let defaults = server.session.defaults
        #expect(defaults.string(forKey: AppGroup.Key.deviceId) == "dev_new")
        #expect(defaults.string(forKey: AppGroup.Key.deviceToken) == "shoo_fresh_token")
        #expect(defaults.string(forKey: AppGroup.Key.deviceMode) == "guardian")
        #expect(defaults.string(forKey: AppGroup.Key.deviceName) == "Rina")
        #expect(defaults.string(forKey: AppGroup.Key.apiBaseURL) == "https://api.shoo.test")
        // English is the server default: no PATCH.
        #expect(server.requests.map(\.path) == ["/devices"])
    }

    /// QA 2026-11-11 #6: reinstalled, the Keychain still holds the old token. That device is deleted with its
    /// own token before the new one registers, so it stops holding a family place.
    @Test func reinstallDeletesTheEarlierDeviceFirst() async throws {
        let server = StubServer(token: "shoo_old_install")
        server.reply { $0.path == "/devices" ? Self.registered : Self.ok }
        let env = environment(server: server)
        _ = try await env.register(name: "Rina", mode: .protected)
        let requests = server.requests
        #expect(requests.map { "\($0.method) \($0.path)" } == ["DELETE /devices/me", "POST /devices"])
        #expect(requests.first?.headers["Authorization"] == "Bearer shoo_old_install")
        #expect(server.session.token == "shoo_fresh_token")
        #expect(env.settings.mode == .protected)
        #expect(server.unauthorizedCount == 0)
    }

    /// The old device is already gone (401 / 404) or the server fails: the new device registers anyway,
    /// and no "Session expired" shows for the old token.
    @Test(arguments: [
        HostStubProtocol.Reply.json(401, #"{"error":{"code":"unauthorized","message":"gone"}}"#),
        .json(404, #"{"error":{"code":"not_found","message":"gone"}}"#),
        .json(500, #"{"error":{"code":"internal","message":"boom"}}"#),
    ])
    func reinstallStillRegistersWhenTheOldDeviceCantBeDeleted(reply: HostStubProtocol.Reply) async throws {
        let server = StubServer(token: "shoo_old_install")
        server.reply { $0.path == "/devices" ? Self.registered : reply }
        let env = environment(server: server)
        _ = try await env.register(name: "Rina", mode: .guardian)
        #expect(server.requests.map(\.path) == ["/devices/me", "/devices"])
        #expect(server.session.token == "shoo_fresh_token")
        #expect(env.settings.mode == .guardian)
        #expect(!env.sessionExpired)
        #expect(server.unauthorizedCount == 0)
    }

    @Test func indonesianAppTellsTheServerRightAway() async throws {
        let server = StubServer(token: nil)
        server.reply { $0.path == "/devices" ? Self.registered : Self.ok }
        let env = environment(server: server, language: .indonesian)
        _ = try await env.register(name: "Rina", mode: .protected)
        let patch = try #require(server.requests.last)
        #expect(patch.method == "PATCH" && patch.path == "/devices/me")
        #expect(patch.json?["language"] as? String == "id")
        #expect(patch.headers["Authorization"] == "Bearer shoo_fresh_token")
    }

    @Test func languageSyncFailureDoesNotUndoRegistration() async throws {
        let server = StubServer(token: nil)
        server.reply { $0.path == "/devices" ? Self.registered : .offline() }
        let env = environment(server: server, language: .indonesian)
        _ = try await env.register(name: "Rina", mode: .protected)
        #expect(env.settings.mode == .protected)
    }

    @Test func failedRegistrationSavesNothing() async {
        let server = StubServer(token: nil)
        server.reply { _ in .offline() }
        let env = environment(server: server)
        await #expect(throws: RepositoryError.network) { _ = try await env.register(name: "Rina", mode: .guardian) }
        #expect(env.settings.mode == nil)
        #expect(server.session.token == nil)
    }

    @Test func foregroundSendsTheHeartbeatAndRefreshesTheProfile() async throws {
        let server = StubServer()
        server.reply { $0.method == "PATCH" ? Self.ok : Self.profile }
        let now = Date()
        let seen = now.addingTimeInterval(-600)
        let env = environment(server: server, mode: .guardian, extensionStatus: { .active(lastSeen: seen) })
        await env.sceneBecameActive(now: now)
        #expect(server.requests.map(\.path) == ["/devices/me", "/devices/me"])
        let text = try #require(server.requests.first?.json?["extensionLastSeenAt"] as? String)
        #expect(abs(try #require(ISO8601DateFormatter().date(from: text)).timeIntervalSince(seen)) < 1)
        #expect(server.session.defaults.string(forKey: AppGroup.Key.deviceName) == "Rina")
    }

    @Test func heartbeatFromTheFutureIsSentAsNow() async throws {
        let server = StubServer()
        server.reply { $0.method == "PATCH" ? Self.ok : Self.profile }
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        let env = environment(server: server, mode: .guardian, extensionStatus: { .active(lastSeen: now.addingTimeInterval(3600)) })
        await env.sceneBecameActive(now: now)
        let text = try #require(server.requests.first?.json?["extensionLastSeenAt"] as? String)
        #expect(ISO8601DateFormatter().date(from: text) == now)
    }

    /// PF-01: the first activation also sends the model and iOS version; after that, no heartbeat only refreshes.
    @Test func noHeartbeatOnlyRefreshesTheProfile() async {
        let server = StubServer()
        server.reply { $0.method == "PATCH" ? Self.ok : Self.profile }
        let env = environment(server: server, mode: .guardian)
        await env.sceneBecameActive()
        #expect(server.requests.map(\.method) == ["PATCH", "GET"])
        let first = server.requests.first?.json
        #expect(first?["deviceModel"] is String)
        #expect(first?["osVersion"] is String)
        #expect(first?["extensionLastSeenAt"] == nil)
        await env.sceneBecameActive()
        #expect(server.requests.map(\.method) == ["PATCH", "GET", "GET"])
    }

    @Test func foregroundBeforeRegistrationCallsNothing() async {
        let server = StubServer(token: nil)
        let env = environment(server: server)
        await env.sceneBecameActive()
        #expect(server.requests.isEmpty)
    }

    @Test func unauthorizedShowsSessionExpiredAndClearsTheSession() async throws {
        let server = StubServer()
        server.reply { _ in .json(401, #"{"error":{"code":"unauthorized","message":"Unknown token"}}"#) }
        let env = environment(server: server, mode: .protected)
        let expiry = SessionExpiry()
        expiry.environment = env
        let configuration = APIClient.configuration()
        configuration.protocolClasses = [HostStubProtocol.self]
        let session = server.session
        let client = APIClient(
            baseURL: server.baseURL, configuration: configuration, token: { try session.readToken() },
            onUnauthorized: { expiry.report(usedToken: $0) }
        )
        await #expect(throws: RepositoryError.self) { _ = try await ApiRepository(client: client, session: session).me() }
        for _ in 0..<50 where !env.sessionExpired { try await Task.sleep(for: .milliseconds(20)) }
        #expect(env.sessionExpired)
        #expect(server.session.token == nil)
        #expect(server.session.defaults.object(forKey: AppGroup.Key.deviceToken) == nil)
    }

    /// A 401 answering a request sent with an older token never ends the current session.
    @Test func lateUnauthorizedForAnOldTokenIsIgnored() {
        let server = StubServer()
        let env = environment(server: server, mode: .guardian)
        env.handleUnauthorized(usedToken: "shoo_previous_session")
        #expect(!env.sessionExpired)
        #expect(server.session.token == "shoo_test_token_123")
        env.handleUnauthorized(usedToken: "shoo_test_token_123")
        #expect(env.sessionExpired)
    }

    @Test func registeredWithoutKeychainTokenIsExpired() {
        let server = StubServer(token: nil)
        let env = environment(server: server, mode: .guardian)
        server.session.defaults.set("shoo_from_backup", forKey: AppGroup.Key.deviceToken)
        env.checkStoredSession()
        #expect(env.sessionExpired)
        #expect(server.session.defaults.object(forKey: AppGroup.Key.deviceToken) == nil)
    }

    @Test func storedSessionIsKeptAndItsURLsRefreshed() {
        let server = StubServer()
        server.session.defaults.removeObject(forKey: AppGroup.Key.apiBaseURL)
        let env = environment(server: server, mode: .guardian)
        env.checkStoredSession()
        #expect(!env.sessionExpired)
        #expect(server.session.defaults.string(forKey: AppGroup.Key.apiBaseURL) == "https://api.shoo.test")
    }

    @Test func startAgainIsAFreshInstall() {
        let server = StubServer()
        let env = environment(server: server, mode: .protected)
        env.settings.onboardingCompleted = true
        env.markSessionExpired()
        env.restartOnboarding()
        #expect(!env.sessionExpired)
        #expect(env.settings.mode == nil)
        #expect(!env.settings.onboardingCompleted)
        #expect(server.session.token == nil)
    }

    @Test func unusableAppGroupTokenIsRemovedEvenBeforeRegistration() {
        let server = StubServer(token: nil)
        let env = environment(server: server)
        server.session.defaults.set("shoo_from_backup", forKey: AppGroup.Key.deviceToken)
        server.session.defaults.set("dev_old", forKey: AppGroup.Key.deviceId)
        env.checkStoredSession()
        #expect(!env.sessionExpired)
        #expect(server.session.defaults.object(forKey: AppGroup.Key.deviceToken) == nil)
        #expect(server.session.defaults.object(forKey: AppGroup.Key.deviceId) == nil)
    }

    @Test func unauthorizedBeforeTheModeIsSavedStillDropsTheToken() {
        let server = StubServer()
        let env = environment(server: server)
        env.markSessionExpired()
        #expect(!env.sessionExpired)
        #expect(server.session.token == nil)
    }

    @Test func notRegisteredNeverExpires() {
        let server = StubServer(token: nil)
        let env = environment(server: server)
        env.markSessionExpired()
        #expect(!env.sessionExpired)
    }

    @Test func uiTestsGetTheMockAndTheAppGetsTheAPI() {
        #expect(AppEnvironment.live(arguments: ["-UITestMock", "YES"], registerForPush: {}).repository is MockRepository)
        #expect(AppEnvironment.live(arguments: ["-UITestMock", "YES"], registerForPush: {}).session == nil)
        #expect(AppEnvironment.live(arguments: [], registerForPush: {}).repository is ApiRepository)
    }

    /// Fase 23a K2: UI tests stop the endless shield animations (`-UITestReduceMotion YES`, Debug only).
    @Test func uiTestReduceMotionIsOnlyForTheArgument() {
        defer { UIView.setAnimationsEnabled(true) }
        let still = AppEnvironment.live(arguments: ["-UITestMock", "YES", "-UITestReduceMotion", "YES"], registerForPush: {})
        #if DEBUG
        #expect(still.reducesMotionForUITests)
        #expect(!UIView.areAnimationsEnabled)
        #else
        #expect(!still.reducesMotionForUITests)
        #endif
        UIView.setAnimationsEnabled(true)
        #expect(!AppEnvironment.live(arguments: ["-UITestMock", "YES"], registerForPush: {}).reducesMotionForUITests)
        #expect(!AppEnvironment.live(arguments: ["-UITestMock", "YES", "-UITestReduceMotion", "NO"], registerForPush: {}).reducesMotionForUITests)
        #expect(UIView.areAnimationsEnabled)
    }

    /// Only a Debug build in the simulator uses localhost; on a real iPhone localhost is the phone.
    @Test func releaseTalksToTheCloudWorker() {
        #if DEBUG && targetEnvironment(simulator)
        #expect(AppConfig.apiBaseURL.absoluteString == "http://localhost:8787")
        #else
        #expect(AppConfig.apiBaseURL.absoluteString == "https://shoo-api.afindo-mi01.workers.dev")
        #endif
        // Only Release builds hand the AI Worker to the extension (#82).
        #if DEBUG
        #expect(AppConfig.aiBaseURL == nil)
        #else
        #expect(AppConfig.aiBaseURL?.absoluteString == "https://shoo-ai.afindo-mi01.workers.dev")
        #expect(AppConfig.aiBaseURL.map(SessionStore.isAllowed) == true)
        #endif
    }

    /// PF-01 "Punya kode undangan?": the server makes a new protected device; the app swaps to its session.
    @Test func joiningAnotherFamilySwapsToTheNewProtectedSession() async throws {
        let server = StubServer()
        server.reply {
            $0.path == "/devices/me/protected"
                ? .json(201, #"{"deviceId":"dev_p","token":"shoo_protected_token","avatarId":"avatar_05","guardian":{"deviceId":"dev_g","name":"Budi","avatarId":"avatar_04"}}"#)
                : Self.ok
        }
        let env = environment(server: server, mode: .guardian)
        env.settings.familyModeOn = true
        let guardian = try await env.becomeProtected(code: "123456", name: "Rina")
        #expect(guardian.name == "Budi")
        #expect(server.session.token == "shoo_protected_token")
        #expect(server.session.guardian?.deviceId == "dev_g")
        #expect(server.session.defaults.string(forKey: AppGroup.Key.deviceId) == "dev_p")
        #expect(server.session.defaults.string(forKey: AppGroup.Key.deviceMode) == "protected")
        #expect(env.settings.mode == .protected)
        #expect(!env.settings.familyModeOn)
        let request = try #require(server.requests.first { $0.path == "/devices/me/protected" })
        #expect(request.method == "POST")
    }

    private nonisolated static let switched = HostStubProtocol.Reply.json(
        201, #"{"deviceId":"dev_p","token":"shoo_protected_token","avatarId":"avatar_05","guardian":{"deviceId":"dev_g","name":"Budi","avatarId":"avatar_04"}}"#
    )

    /// Fase 27h (F-A3, K10): while "Punya kode undangan?" is in flight the server has already swapped the device,
    /// so another request sent with the old token gets 401. That answer belongs to the old session: the new
    /// one is saved and "Session expired" never shows.
    @Test func oldTokenUnauthorizedDuringTheSwitchKeepsTheNewSession() async throws {
        let server = StubServer()
        let gate = ReplyGate()
        server.reply { request in
            guard request.path == "/devices/me/protected" else { return Self.ok }
            gate.hold()
            return Self.switched
        }
        let env = environment(server: server, mode: .guardian)
        let switching = Task { try await env.becomeProtected(code: "123456", name: "Rina") }
        await gate.arrival()
        env.handleUnauthorized(usedToken: "shoo_test_token_123")
        gate.open()
        _ = try await switching.value
        #expect(!env.sessionExpired)
        #expect(server.session.token == "shoo_protected_token")
        #expect(server.session.defaults.string(forKey: AppGroup.Key.deviceId) == "dev_p")
        #expect(env.settings.mode == .protected)
    }

    /// K10: the switch flag lives only while the request runs. A failed switch (here a 500) leaves the old
    /// session, and its next 401 shows "Session expired" as usual.
    @Test func failedSwitchStillLetsTheNextUnauthorizedExpire() async throws {
        let server = StubServer()
        server.reply { _ in .json(500, #"{"error":{"code":"internal","message":"Something went wrong"}}"#) }
        let env = environment(server: server, mode: .guardian)
        await #expect(throws: RepositoryError.self) { try await env.becomeProtected(code: "123456", name: "Rina") }
        env.handleUnauthorized(usedToken: "shoo_test_token_123")
        #expect(env.sessionExpired)
    }

    /// Fase 27h (F-A8, K10): a second registration in the same launch (after "Delete my data") is a new device on
    /// the server, so its first activation sends the model, iOS version and time zone again.
    @Test func registeringAgainInTheSameLaunchSendsTheDeviceInfoAgain() async throws {
        let server = StubServer(token: nil)
        server.reply { request in
            switch (request.method, request.path) {
            case ("POST", "/devices"): Self.registered
            case ("GET", _): Self.profile
            default: Self.ok
            }
        }
        let env = environment(server: server)
        _ = try await env.register(name: "Rina", mode: .guardian)
        await env.sceneBecameActive()
        // "Delete my data" (ProfileModel.deleteMyData): gone on the server, then a fresh install here.
        try await env.repository.deleteMe()
        env.settings.reset()
        _ = try await env.register(name: "Rina", mode: .guardian)
        let afterSecondRegistration = server.requests.count
        await env.sceneBecameActive()
        let sent = server.requests.dropFirst(afterSecondRegistration).filter { $0.method == "PATCH" }.compactMap(\.json)
        #expect(sent.contains { $0["deviceModel"] is String && $0["osVersion"] is String && $0["timeZone"] is String })
    }

    /// Fase 27h (F-N7, K10): a 401 for another request with the same token can land before `DELETE /devices/me`
    /// answers. The delete still ends in onboarding, not on "Session expired".
    @Test func unauthorizedDuringDeleteEndsInOnboarding() async throws {
        let server = StubServer()
        let gate = ReplyGate()
        server.reply { request in
            guard request.method == "DELETE" else { return Self.ok }
            gate.hold()
            return Self.ok
        }
        let env = environment(server: server, mode: .protected)
        env.settings.onboardingCompleted = true
        let linkedSuite = "test.linked.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: linkedSuite) }
        let profile = ProfileModel(
            repository: env.repository, settings: env.settings,
            linked: LinkedAccountSettings(defaults: UserDefaults(suiteName: linkedSuite)!)
        )
        profile.onSessionEnd = { env.returnToOnboardingAfterDelete() }
        let deleting = Task { await profile.deleteMyData() }
        await gate.arrival()
        env.handleUnauthorized(usedToken: "shoo_test_token_123")
        gate.open()
        #expect(await deleting.value)
        #expect(!env.sessionExpired)
        #expect(env.settings.mode == nil)
        #expect(!env.settings.onboardingCompleted)
    }

    @Test func joiningWhileProtectingSomeoneKeepsTheGuardianSession() async throws {
        let server = StubServer()
        server.reply { _ in .json(409, #"{"error":{"code":"has_members","message":"Disconnect the people you protect first"}}"#) }
        let env = environment(server: server, mode: .guardian)
        await #expect(throws: RepositoryError.self) { try await env.becomeProtected(code: "123456", name: "Rina") }
        #expect(server.session.token == "shoo_test_token_123")
        #expect(env.settings.mode == .guardian)
    }
}
