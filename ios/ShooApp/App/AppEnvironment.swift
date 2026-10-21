import Foundation
import Observation

/// Dependencies every screen reads from the SwiftUI environment:
/// `@Environment(AppEnvironment.self) private var env`.
@Observable
final class AppEnvironment {
    private(set) var repository: any ShooRepository
    let settings: AppSettings
    let router: Router

    init(repository: any ShooRepository, settings: AppSettings, router: Router = Router()) {
        self.repository = repository
        self.settings = settings
        self.router = router
    }

    /// The app at launch. Fase A always uses fixtures; fase 13 switches to `ApiRepository`.
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        let settings = AppSettings()
        let scenario = Self.value(after: "-mock.scenario", in: arguments)
            .flatMap(MockRepository.Scenario.init(rawValue:)) ?? .standard
        // TODO(sync:alief): ApiRepository — replace after fase 13
        let repository = MockRepository(mode: settings.mode ?? .guardian, scenario: scenario)
        return AppEnvironment(repository: repository, settings: settings)
    }

    /// Ends onboarding with the mode picked in ON-03 (permanent).
    func completeOnboarding(mode: UserMode) {
        settings.mode = mode
        settings.onboardingCompleted = true
        // Fixtures answer as the chosen identity; the real API knows the mode from the token.
        if let mock = repository as? MockRepository {
            repository = mock.switching(to: mode)
        }
    }

    /// For SwiftUI previews: fixtures, no latency, onboarding done.
    static func preview(mode: UserMode = .guardian, language: AppLanguage = .english) -> AppEnvironment {
        let defaults = UserDefaults(suiteName: "preview.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.mode = mode
        settings.language = language
        settings.onboardingCompleted = true
        return AppEnvironment(repository: MockRepository(mode: mode, latency: .zero), settings: settings)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
