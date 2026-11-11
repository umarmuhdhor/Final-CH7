import Foundation
import Observation
import UIKit

/// Dependencies every screen reads from the SwiftUI environment:
/// `@Environment(AppEnvironment.self) private var env`.
@Observable
final class AppEnvironment {
    private(set) var repository: any ShooRepository
    let settings: AppSettings
    let router: Router
    let notifications: any NotificationPermission
    /// Keychain token + App Group keys. `nil` with `MockRepository` (previews, UI tests): fixtures never
    /// touch the real App Group.
    @ObservationIgnored private(set) var session: SessionStore?
    /// Safari extension Active/Off right now (Safari's switch + heartbeat in the App Group).
    @ObservationIgnored let extensionStatus: () async -> ExtensionStatus
    /// The server no longer knows our token (401), or the Keychain has none (backup restored onto
    /// another iPhone). `RootView` then shows "Session expired" (fase 13 step 4).
    private(set) var sessionExpired = false
    @ObservationIgnored private var isSyncingForeground = false
    /// Asks iOS for the APNs token; the answer comes back through `AppDelegate`.
    @ObservationIgnored private let registerForPush: @MainActor () -> Void
    /// The token the server has (or is getting) from this launch: the same one is not sent twice.
    @ObservationIgnored private var sentPushToken: String?
    /// PF-01: model and iOS version go to the server once per launch.
    @ObservationIgnored private var sentDeviceInfo = false
    /// Bumped by `register`: a token send that started for the old device can't mark the new one as sent.
    @ObservationIgnored private var pushTokenEpoch = 0
    /// EX-03 (#49): the Dynamic Island's push tokens for the backend. Started at the first activation.
    @ObservationIgnored private var liveActivityTokens: LiveActivityTokens?
    /// UI tests (`-UITestReduceMotion YES`, Debug only): no endless shield animation keeping the app busy,
    /// so XCUITest finds it idle (fase 23a K2). Not for screenshots or the accessibility audit.
    @ObservationIgnored private(set) var reducesMotionForUITests = false
    /// Builds the real backend when the demo ends. `nil` in previews and tests that don't leave a demo.
    @ObservationIgnored fileprivate var makeLiveBackend: (() -> (repository: any ShooRepository, session: SessionStore))?
    /// ON-01: the brand splash over the first screen (`LaunchSplash`). It lives as long as the process, so a
    /// cold launch shows it and a return from the background does not.
    var launchSplash: LaunchSplashPhase = .showing
    /// UI tests: how long the splash stays before it fades (`-UITestSplashSeconds`, Debug only).
    @ObservationIgnored private(set) var launchSplashHold: Double?

    init(
        repository: any ShooRepository,
        settings: AppSettings,
        router: Router = Router(),
        notifications: any NotificationPermission = SystemNotificationPermission(),
        session: SessionStore? = nil,
        extensionStatus: @escaping () async -> ExtensionStatus = { await ExtensionStatus.load() },
        registerForPush: @escaping @MainActor () -> Void = {}
    ) {
        self.registerForPush = registerForPush
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
    static func live(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        registerForPush: @escaping @MainActor () -> Void
    ) -> AppEnvironment {
        #if DEBUG
        if Self.value(after: "-UITestReset", in: arguments) == "YES" {
            AppSettings.clear(defaults: .standard)
        }
        let usesMockFixtures = Self.value(after: "-UITestMock", in: arguments) == "YES"
        #else
        let usesMockFixtures = false
        #endif
        let settings = AppSettings()
        let usesMock = usesMockFixtures || settings.demoMode
        let repository: any ShooRepository
        let session: SessionStore?
        let expiry = SessionExpiry()
        let makeLiveBackend: () -> (repository: any ShooRepository, session: SessionStore) = {
            #if DEBUG
            // Live QA on a local stack: `-debug.aiBaseURL http://localhost:8788` gives the extension layers 3–4
            // (AppConfig has no AI URL in Debug). `SessionStore.isAllowed` still rejects anything but HTTPS or localhost.
            let store = SessionStore(
                aiBaseURL: Self.value(after: "-debug.aiBaseURL", in: arguments).flatMap(URL.init(string:)) ?? AppConfig.aiBaseURL,
                onlineCheckAllowed: settings.dataConsent == .granted
            )
            #else
            let store = SessionStore(onlineCheckAllowed: settings.dataConsent == .granted)
            #endif
            let client = APIClient(
                baseURL: AppConfig.apiBaseURL,
                token: { try store.readToken() },
                onUnauthorized: { expiry.report(usedToken: $0) }
            )
            return (ApiRepository(client: client, session: store), store)
        }
        if usesMock {
            let scenario = Self.value(after: "-mock.scenario", in: arguments)
                .flatMap(MockRepository.Scenario.init(rawValue:)) ?? .standard
            repository = MockRepository(
                mode: settings.mode ?? .guardian, scenario: scenario,
                pageCopies: Self.value(after: "-debug.replicaFixture", in: arguments) == "YES"
            )
            session = nil
            // Fixtures only, nothing leaves the phone: UI tests don't answer the question unless they test it.
            if Self.value(after: "-debug.askDataConsent", in: arguments) != "YES" {
                settings.dataConsent = settings.dataConsent ?? .granted
            }
        } else {
            (repository, session) = makeLiveBackend()
        }
        var notifications: any NotificationPermission = SystemNotificationPermission()
        var extensionStatus: () async -> ExtensionStatus = { await ExtensionStatus.load() }
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
        // ON-04 messages (#135): `-UITestExtensionStatus switchedOff|someSitesOnly|notSeen|unchecked`.
        switch Self.value(after: "-UITestExtensionStatus", in: arguments) {
        case "switchedOff": extensionStatus = { .off(lastSeen: nil, reason: .switchedOff) }
        case "someSitesOnly": extensionStatus = { .off(lastSeen: Date(), reason: .someSitesOnly) }
        case "notSeen": extensionStatus = { .off(lastSeen: nil, reason: .notSeen) }
        case "unchecked": extensionStatus = { .active(lastSeen: nil) }
        // Activity "Perlindungan mati" (PR-05): switched off, last heartbeat two days ago.
        case "offTwoDays": extensionStatus = { .off(lastSeen: Date().addingTimeInterval(-2 * 86_400), reason: .switchedOff) }
        default: break
        }
        // Activity empty states (PR-05): the extension's counters as in Figma (#183, not written yet).
        if Self.value(after: "-UITestCheckStats", in: arguments) == "YES" {
            let lastChecked = Calendar.current.date(bySettingHour: 10, minute: 42, second: 0, of: Date()) ?? Date()
            AppGroup.defaults.set(1284, forKey: CheckStats.Key.checked)
            AppGroup.defaults.set(lastChecked, forKey: CheckStats.Key.lastCheckedAt)
        }
        #endif
        let environment = AppEnvironment(
            repository: repository, settings: settings, notifications: notifications, session: session,
            extensionStatus: extensionStatus,
            registerForPush: registerForPush
        )
        environment.makeLiveBackend = makeLiveBackend
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
        if Self.value(after: "-debug.profile", in: arguments) == "YES" { environment.router.openProfile() }
        // Figma parity screenshots of a Profile page: `-debug.profilePage editProfile|notifications|…`.
        let pages: [String: ProfilePage] = [
            "mode": .mode, "editProfile": .editProfile, "connection": .connection, "notifications": .notifications,
            "language": .language, "theme": .theme, "accessibility": .accessibility, "about": .about,
        ]
        if let page = Self.value(after: "-debug.profilePage", in: arguments).flatMap({ pages[$0] }) {
            environment.router.openProfile()
            environment.router.show(.profilePage(page))
        }
        // ON-01: UI tests that don't test the launch splash start on their screen (`-UITestSkipSplash YES`);
        // the splash test holds it long enough to see (`-UITestSplashSeconds 5`).
        if Self.value(after: "-UITestSkipSplash", in: arguments) == "YES" { environment.launchSplash = .done }
        environment.launchSplashHold = Self.value(after: "-UITestSplashSeconds", in: arguments).flatMap(Double.init)
        if Self.value(after: "-UITestReduceMotion", in: arguments) == "YES" {
            environment.reducesMotionForUITests = true
            // Push and sheet transitions too (UIKit); SwiftUI's own animations read `shooReduceMotion`.
            UIView.setAnimationsEnabled(false)
        }
        // Detail (fase 03): `-debug.detail <scanId>` opens it on the selected tab.
        if let scanId = Self.value(after: "-debug.detail", in: arguments) {
            environment.router.showDetail(scanId: scanId)
        }
        #endif
        return environment
    }

    /// A device registered before the question existed answers it before anything else (Apple 5.1.2(i)).
    var needsDataConsent: Bool { settings.mode != nil && settings.dataConsent == nil && !sessionExpired }

    /// Onboarding, the same question for an existing device, and the switch in Profile.
    @MainActor
    func setDataConsent(_ consent: DataConsent) {
        settings.dataConsent = consent
        session?.setOnlineCheck(allowed: consent == .granted)
    }

    /// ON-03: registers the device and saves the mode for good. The repository then answers as this
    /// device (the mock adopts the name, avatar and mode; the API knows them from the token).
    @MainActor
    func register(name: String, mode: UserMode, avatarId: String? = nil) async throws -> DeviceRegistration {
        await deletePreviousInstall()
        let registration = try await repository.registerDevice(name: name, mode: mode, avatarId: avatarId, apnsToken: nil)
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
        // A new device on the server: its first token must be sent even if APNs hands out the same one.
        sentPushToken = nil
        pushTokenEpoch += 1
        liveActivityTokens?.deviceChanged()
        if mode == .guardian { router.pendingJoinCode = nil }
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

    /// A Keychain token with no mode saved: Shoo was deleted and installed again. The Keychain item outlives
    /// the app, the settings don't. That old device is still on the server, linked to the family, shown as
    /// "Aktif" and holding one of the 3 places (QA 2026-11-11 #6). It goes first (`DELETE /devices/me` with
    /// its own token, as "Delete my data" would): nothing of the old install stays behind (SECURITY §3).
    /// Best effort: if it fails, the new device registers anyway, as before.
    @MainActor
    private func deletePreviousInstall() async {
        guard settings.mode == nil, let session, session.token != nil else { return }
        Log.app.info("Token from an earlier install found: deleting that device")
        do {
            try await repository.deleteMe()
        } catch {
            // Already gone (`deleteMe` cleared the session) or the server refused: the new token replaces it.
            session.clear()
            guard !error.isCancellation else { return }
            Log.app.error("Deleting the earlier install failed", error)
        }
    }

    /// Every time the app comes to the foreground (contracts/api.md `extensionLastSeenAt`): tells the
    /// server the extension's last heartbeat (GD-03 "Not connected"), then refreshes name + guardian
    /// in the App Group from `GET /devices/me`.
    @MainActor
    func sceneBecameActive(now: Date = Date()) async {
        // One sync at a time: quick background/foreground flips don't stack requests.
        guard settings.mode != nil, !sessionExpired, !isSyncingForeground else { return }
        isSyncingForeground = true
        defer { isSyncingForeground = false }
        let lastSeen = await extensionStatus().lastSeen
        // PF-01: the guardian's member detail shows the model and iOS version; sent once per launch.
        // The time zone goes with it: quiet hours and the weekly summary use the phone's local time.
        let device = sentDeviceInfo ? nil : (model: DeviceInfo.modelName, os: DeviceInfo.osMajorVersion, zone: DeviceInfo.timeZone)
        if lastSeen != nil || device != nil {
            do {
                try await repository.updateMe(DeviceUpdate(
                    // The server refuses times in the future (clock changes).
                    extensionLastSeenAt: lastSeen.map { min($0, now) },
                    deviceModel: device?.model,
                    osVersion: device?.os,
                    timeZone: device?.zone
                ))
                if device != nil { sentDeviceInfo = true }
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
        await registerForPushIfAllowed()
        startLiveActivityTokens()
        await liveActivityTokens?.sync()
    }

    /// EX-03 (#49, QA 2026-11-10 #5): without the start token the backend answered `no_start_token` to every
    /// `POST /live` and the island never started. Both modes: the island shows the viewer's own Safari page.
    @MainActor
    private func startLiveActivityTokens() {
        guard liveActivityTokens == nil else { return }
        let tokens = LiveActivityTokens(
            canSend: { [weak self] in
                // Never from the demo or the UI-test mock: they have no server record to update.
                guard let self, self.settings.mode != nil, !self.sessionExpired else { return false }
                return !(self.repository is MockRepository)
            },
            send: { [weak self] update in try await self?.repository.updateMe(update) }
        )
        liveActivityTokens = tokens
        tokens.start()
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

    /// A 401 for `usedToken`. Ignored when the session has moved on since that request left
    /// (restart, new registration): only the current token can expire.
    @MainActor
    func handleUnauthorized(usedToken: String) {
        guard let current = try? session?.readToken(), current == usedToken else { return }
        markSessionExpired()
    }

    @MainActor
    func markSessionExpired() {
        // A dead token goes in every case; the screen only for a registered device.
        session?.clear()
        guard settings.mode != nil, !sessionExpired else { return }
        Log.app.info("Session expired")
        sessionExpired = true
        DeliveredPushes.clear()
    }

    /// "Try the demo" (App Review, Guideline 2.1): a family of fixtures on this phone. Nothing is registered and
    /// nothing leaves the phone. Offered only before this device has a mode, so no real session is replaced.
    @MainActor
    func startDemo() {
        guard settings.mode == nil else { return }
        repository = MockRepository(mode: .guardian)
        session = nil
        settings.enterDemo()
    }

    /// Back to a fresh install on the real backend.
    @MainActor
    func leaveDemo() {
        guard settings.demoMode else { return }
        router.reset()
        settings.reset()
        // The demo's fixtures have no favicon links today; emptied anyway so nothing from it stays (P13).
        CachedFaviconLoader.shared.clear()
        if let backend = makeLiveBackend?() {
            repository = backend.repository
            session = backend.session
        }
    }

    /// "Start again" on the Session expired screen: a fresh install (onboarding from the start).
    @MainActor
    func restartOnboarding() {
        session?.clear()
        router.reset()
        settings.reset()
        sessionExpired = false
        DeliveredPushes.clear()
    }

    /// Family mode on (Pribadi → Guardian). The first time, Figma "To be guardian" shows first and its
    /// "Mulai" turns it on (`startGuardian`).
    @MainActor
    func requestFamilyMode() {
        guard settings.mode == .guardian, !settings.familyModeOn else { return }
        if settings.guardianIntroSeen {
            settings.familyModeOn = true
        } else {
            router.isGuardianIntroPresented = true
        }
    }

    /// "Mulai" on Figma "To be guardian".
    @MainActor
    func startGuardian() {
        settings.guardianIntroSeen = true
        settings.familyModeOn = true
        router.isGuardianIntroPresented = false
    }

    /// PF-01 "Punya kode undangan?": a guardian without members joins another family. The server
    /// replaces this device with a protected one; its session and the mode take over here at once
    /// (the old token is dead). The caller closes its screens afterwards (`router.reset()`).
    /// Throws the join errors (code, full family) and `has_members`.
    @MainActor
    func becomeProtected(code: String, name: String) async throws -> GuardianInfo {
        let result = try await repository.becomeProtected(code: code)
        do {
            try session?.save(result.registration, name: name, mode: .protected)
        } catch {
            // The old device is already gone on the server: without the new token the app cannot go on.
            Log.app.error("Session save failed", error)
            markSessionExpired()
            throw RepositoryError.network
        }
        session?.setGuardian(result.guardian)
        settings.becameProtected()
        // A new device on the server: send the push token and device info again.
        sentPushToken = nil
        sentDeviceInfo = false
        pushTokenEpoch += 1
        liveActivityTokens?.deviceChanged()
        DeliveredPushes.clear()
        await registerForPushIfAllowed()
        return result.guardian
    }

    /// Deep links (contracts/app-group-keys.md). A join link only fills in the code: Connect still asks
    /// for a tap (T11). `scan` opens Detail, `activity` the Activity tab; a Guardian's join link, or any
    /// unknown link, lands on Shield.
    @MainActor
    func open(_ url: URL) {
        switch DeepLink(url: url) {
        case .join(let code) where settings.mode != .guardian:
            router.pendingJoinCode = code
            // Not registered yet: onboarding reaches Connect with the code. Mid-onboarding Connect picks it up.
            guard settings.mode == .protected, settings.onboardingCompleted else { return }
            // Already open, `ConnectSheet` picks the new code up.
            router.showConnect()
        case .scan(let id) where isInMainScreen:
            router.openDetail(scanId: id)
        case .activity where isInMainScreen:
            router.openActivity()
        case .join, .unknown:
            // A Guardian's join link, or a link we don't know: Shield.
            if isInMainScreen { router.reset() }
        case .scan, .activity:
            // Onboarding or "Session expired" is on screen: nothing to open yet.
            break
        }
    }

    /// The tabs are showing (not onboarding, not "Session expired").
    @MainActor
    private var isInMainScreen: Bool {
        settings.onboardingCompleted && settings.mode != nil && !sessionExpired
    }

    /// GD-06: a tapped push. A push without a usable `scanId` opens Shield. The Protected device only
    /// gets family pushes (reminder, disconnect, PF-01), which never carry a `scanId`.
    @MainActor
    func openPush(scanId: String?) {
        guard isInMainScreen else { return }
        if let scanId, settings.mode == .guardian {
            router.openDetail(scanId: scanId)
        } else {
            router.reset()
        }
    }

    /// A push that arrives while Shoo is open: a banner only where a tap can open it (C15).
    @MainActor
    var showsPushBanner: Bool { isInMainScreen }

    /// Bumped by every push that arrives while the tabs are showing. Guardian Home reloads on it, so the
    /// banner and the page under it tell the same story without a pull-to-refresh (QA 2026-11-11 #4).
    private(set) var pushesWhileOpen = 0

    /// A push arrived while Shoo is open (`willPresent`).
    @MainActor
    func pushArrivedWhileOpen() {
        guard isInMainScreen else { return }
        pushesWhileOpen += 1
    }

    /// ON-05: both modes send their token. The Guardian gets scan pushes; the Protected device gets
    /// family pushes ("Ingatkan", disconnect, PF-01 proposed in backend/API.md).
    @MainActor
    func pushTokenReceived(_ token: Data) async {
        guard settings.mode != nil, !sessionExpired else { return }
        let hex = NotificationRouter.hex(token: token)
        guard hex != sentPushToken else { return }
        // Marked before the request: a second callback with the same token while it is in flight sends nothing.
        sentPushToken = hex
        let epoch = pushTokenEpoch
        do {
            try await repository.updateMe(DeviceUpdate(apnsToken: hex))
        } catch {
            // Sent again on the next activation, unless a new registration has taken over meanwhile.
            if epoch == pushTokenEpoch, sentPushToken == hex { sentPushToken = nil }
            guard !error.isCancellation else { return }
            Log.app.error("APNs token sync failed", error)
        }
    }

    /// Apple asks apps to register at every launch: the token can change (restore, reinstall).
    @MainActor
    func registerForPushIfAllowed() async {
        guard settings.mode != nil, !sessionExpired, await notifications.status() == .authorized else { return }
        Log.app.info("APNs registration requested")
        registerForPush()
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
        settings.dataConsent = .granted
        let environment = AppEnvironment(repository: MockRepository(mode: mode, latency: .zero), settings: settings)
        environment.launchSplash = .done
        return environment
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

/// Hands a 401 from any URLSession thread to the environment on the main actor.
final class SessionExpiry: @unchecked Sendable {
    /// Written once on the main actor in `live()`, before any request can run.
    weak var environment: AppEnvironment?

    func report(usedToken: String) {
        Task { @MainActor [weak self] in self?.environment?.handleUnauthorized(usedToken: usedToken) }
    }
}
