import Foundation
import Observation

/// Dependencies every screen reads from the SwiftUI environment:
/// `@Environment(AppEnvironment.self) private var env`.
@Observable
final class AppEnvironment {
    let repository: any ShooRepository
    let settings: AppSettings
    let router: Router
    let notifications: any NotificationPermission
    /// Keychain token + App Group keys. `nil` with `MockRepository` (previews, UI tests): fixtures never
    /// touch the real App Group.
    @ObservationIgnored let session: SessionStore?
    /// Safari extension Active/Off right now (heartbeat in the App Group).
    @ObservationIgnored let extensionStatus: () -> ExtensionStatus
    /// The server no longer knows our token (401), or the Keychain has none (backup restored onto
    /// another iPhone). `RootView` then shows "Session expired" (fase 13 step 4).
    private(set) var sessionExpired = false

    init(
        repository: any ShooRepository,
        settings: AppSettings,
        router: Router = Router(),
        notifications: any NotificationPermission = SystemNotificationPermission(),
        session: SessionStore? = nil,
        extensionStatus: @escaping () -> ExtensionStatus = { ExtensionStatus.current() }
    ) {
        self.repository = repository
        self.settings = settings
        self.router = router
        self.notifications = notifications
        self.session = session
        self.extensionStatus = extensionStatus
    }

    /// The app at launch: `ApiRepository` against `AppConfig.apiBaseURL`. UI tests and screenshots pass
    /// `-UITestMock YES` (Debug only) to get the fixtures of `MockRepository` instead.
    @MainActor
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        #if DEBUG
        if Self.value(after: "-UITestReset", in: arguments) == "YES" {
            AppSettings.clear(defaults: .standard)
        }
        let usesMock = Self.value(after: "-UITestMock", in: arguments) == "YES"
        #else
        let usesMock = false
        #endif
        let settings = AppSettings()
        let repository: any ShooRepository
        let session: SessionStore?
        let expiry = SessionExpiry()
        if usesMock {
            let scenario = Self.value(after: "-mock.scenario", in: arguments)
                .flatMap(MockRepository.Scenario.init(rawValue:)) ?? .standard
            repository = MockRepository(mode: settings.mode ?? .guardian, scenario: scenario)
            session = nil
        } else {
            let store = SessionStore()
            let client = APIClient(
                baseURL: AppConfig.apiBaseURL,
                token: { try store.readToken() },
                onUnauthorized: { expiry.report() }
            )
            repository = ApiRepository(client: client, session: store)
            session = store
        }
        var notifications: any NotificationPermission = SystemNotificationPermission()
        var extensionStatus: () -> ExtensionStatus = { ExtensionStatus.current() }
        #if DEBUG
        // UI tests: no system alert, and the extension counts as on without a real heartbeat.
        switch Self.value(after: "-UITestNotifications", in: arguments) {
        case "granted": notifications = FixedNotificationPermission(answer: .authorized)
        case "denied": notifications = FixedNotificationPermission(answer: .denied)
        default: break
        }
        if Self.value(after: "-UITestExtensionActive", in: arguments) == "YES" {
            extensionStatus = { .active(lastSeen: Date()) }
        }
        #endif
        let environment = AppEnvironment(
            repository: repository, settings: settings, notifications: notifications, session: session,
            extensionStatus: extensionStatus
        )
        expiry.environment = environment
        environment.checkStoredSession()
        #if DEBUG
        // UI gate for the "Session expired" screen: `-debug.sessionExpired YES`.
        if Self.value(after: "-debug.sessionExpired", in: arguments) == "YES" {
            environment.markSessionExpired()
        }
        // Screenshots for the UI gate: `-debug.tab activity`, `-debug.profile YES`.
        if let tab = Self.value(after: "-debug.tab", in: arguments).flatMap(AppTab.init(rawValue:)) {
            environment.router.selectedTab = tab
        }
        environment.router.isProfilePresented = Self.value(after: "-debug.profile", in: arguments) == "YES"
        // Detail (fase 03): `-debug.detail <scanId>` opens it on the selected tab.
        if let scanId = Self.value(after: "-debug.detail", in: arguments) {
            environment.router.showDetail(scanId: scanId)
        }
        #endif
        return environment
    }

    /// ON-03: registers the device and saves the mode for good. The repository then answers as this
    /// device (the mock adopts the name, avatar and mode; the API knows them from the token).
    @MainActor
    func register(name: String, mode: UserMode) async throws -> DeviceRegistration {
        let registration = try await repository.registerDevice(name: name, mode: mode, apnsToken: nil)
        // Keychain + App Group before the mode is saved: a relaunch never finds a mode without a session.
        do {
            try session?.save(registration, name: name, mode: mode)
        } catch {
            // Keychain refused (full, locked): no half session. The unused device on the server holds
            // only a name and expires with the inactive-device cleanup (handoff fase 13).
            session?.clear()
            Log.app.error("Session save failed", error)
            throw RepositoryError.network
        }
        settings.chooseMode(mode)
        // `POST /devices` has no language; the server defaults to English (pushes are localized, D-alief-05).
        if settings.language != .english {
            do {
                try await repository.updateMe(DeviceUpdate(language: settings.language.code))
            } catch {
                // Profile sends it again when `me().language` differs (D-alief-A19).
                Log.app.error("Language sync after registration failed", error)
            }
        }
        return registration
    }

    /// Every time the app comes to the foreground (contracts/api.md `extensionLastSeenAt`): tells the
    /// server the extension's last heartbeat (GD-03 "Not connected"), then refreshes name + guardian
    /// in the App Group from `GET /devices/me`.
    @MainActor
    func sceneBecameActive(now: Date = Date()) async {
        guard settings.mode != nil, !sessionExpired else { return }
        if let lastSeen = extensionStatus().lastSeen {
            do {
                // The server refuses times in the future (clock changes).
                try await repository.updateMe(DeviceUpdate(extensionLastSeenAt: min(lastSeen, now)))
            } catch {
                guard !error.isCancellation else { return }
                Log.app.error("Extension heartbeat sync failed", error)
            }
        }
        do {
            _ = try await repository.me()
        } catch {
            guard !error.isCancellation else { return }
            Log.app.error("Profile refresh failed", error)
        }
    }

    /// A registered device whose token is gone (backup restored onto another iPhone: the Keychain item
    /// is `ThisDeviceOnly`) can't call the API. The App Group copy is not trusted then (P4).
    @MainActor
    func checkStoredSession() {
        guard let session else { return }
        let token: String?
        do {
            token = try session.readToken()
        } catch {
            // Keychain not readable yet (before the first unlock): decide on the next launch.
            return
        }
        guard token != nil else {
            // Never leave a token the app can't use in the App Group, registered or not.
            session.clear()
            if settings.mode != nil { markSessionExpired() }
            return
        }
        if settings.mode != nil { session.writeBaseURLs() }
    }

    @MainActor
    func markSessionExpired() {
        // A dead token goes in every case; the screen only for a registered device.
        session?.clear()
        guard settings.mode != nil, !sessionExpired else { return }
        Log.app.info("Session expired")
        sessionExpired = true
    }

    /// "Start again" on the Session expired screen: a fresh install (onboarding from the start).
    @MainActor
    func restartOnboarding() {
        session?.clear()
        router.reset()
        settings.reset()
        sessionExpired = false
    }

    /// After ON-05: the tabs replace onboarding.
    @MainActor
    func finishOnboarding() {
        settings.onboardingCompleted = true
    }

    /// For SwiftUI previews: fixtures, no latency, onboarding done.
    static func preview(mode: UserMode = .guardian, language: AppLanguage = .english) -> AppEnvironment {
        let defaults = UserDefaults(suiteName: "preview.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.chooseMode(mode)
        settings.language = language
        settings.onboardingCompleted = true
        return AppEnvironment(repository: MockRepository(mode: mode, latency: .zero), settings: settings)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

/// Hands a 401 from any URLSession thread to the environment on the main actor.
final class SessionExpiry: @unchecked Sendable {
    weak var environment: AppEnvironment?

    func report() {
        Task { @MainActor [weak self] in self?.environment?.markSessionExpired() }
    }
}
