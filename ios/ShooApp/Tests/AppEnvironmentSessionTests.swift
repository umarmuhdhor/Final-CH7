import Foundation
import Testing
@testable import Shoo

/// Fase 13: `AppEnvironment` with the real repository — registration, foreground sync, session expiry.
@MainActor
struct AppEnvironmentSessionTests {
    private static let registered = HostStubProtocol.Reply.json(
        201, #"{"deviceId":"dev_new","token":"shoo_fresh_token","avatarId":"avatar_05"}"#
    )
    private static let ok = HostStubProtocol.Reply.json(200, #"{"ok":true}"#)
    private static let profile = HostStubProtocol.Reply.json(
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

    @Test func noHeartbeatOnlyRefreshesTheProfile() async {
        let server = StubServer()
        server.reply { _ in Self.profile }
        let env = environment(server: server, mode: .guardian)
        await env.sceneBecameActive()
        #expect(server.requests.map(\.method) == ["GET"])
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

    @Test func releaseTalksToTheCloudWorker() {
        #if DEBUG
        #expect(AppConfig.apiBaseURL.absoluteString == "http://localhost:8787")
        #else
        #expect(AppConfig.apiBaseURL.absoluteString == "https://shoo-api.afindo-mi01.workers.dev")
        #endif
        #expect(AppConfig.aiBaseURL == nil)
    }
}
