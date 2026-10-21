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
    /// Safari extension Active/Off right now (heartbeat in the App Group).
    @ObservationIgnored let extensionStatus: () -> ExtensionStatus

    init(
        repository: any ShooRepository,
        settings: AppSettings,
        router: Router = Router(),
        notifications: any NotificationPermission = SystemNotificationPermission(),
        extensionStatus: @escaping () -> ExtensionStatus = { ExtensionStatus.current() }
    ) {
        self.repository = repository
        self.settings = settings
        self.router = router
        self.notifications = notifications
        self.extensionStatus = extensionStatus
    }

    /// The app at launch. Fase A always uses fixtures; fase 13 switches to `ApiRepository`.
    @MainActor
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        #if DEBUG
        if Self.value(after: "-UITestReset", in: arguments) == "YES" {
            AppSettings.clear(defaults: .standard)
        }
        #endif
        let settings = AppSettings()
        let scenario = Self.value(after: "-mock.scenario", in: arguments)
            .flatMap(MockRepository.Scenario.init(rawValue:)) ?? .standard
        // TODO(sync:alief): ApiRepository — replace after fase 13
        let repository = MockRepository(mode: settings.mode ?? .guardian, scenario: scenario)
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
            repository: repository, settings: settings, notifications: notifications, extensionStatus: extensionStatus
        )
        #if DEBUG
        // Screenshots for the UI gate: `-debug.tab activity`, `-debug.profile YES`.
        if let tab = Self.value(after: "-debug.tab", in: arguments).flatMap(AppTab.init(rawValue:)) {
            environment.router.selectedTab = tab
        }
        environment.router.isProfilePresented = Self.value(after: "-debug.profile", in: arguments) == "YES"
        #endif
        return environment
    }

    /// ON-03: registers the device and saves the mode for good. The repository then answers as this
    /// device (the mock adopts the name, avatar and mode; the API knows them from the token).
    @MainActor
    func register(name: String, mode: UserMode) async throws -> DeviceRegistration {
        let registration = try await repository.registerDevice(name: name, mode: mode, apnsToken: nil)
        // TODO(sync:alief): save registration.token in the Keychain (AfterFirstUnlockThisDeviceOnly, P4) and the
        // App Group session keys before chooseMode — replace after fase 13
        settings.chooseMode(mode)
        return registration
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
