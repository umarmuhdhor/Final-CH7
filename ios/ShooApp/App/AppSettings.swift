import Foundation
import Observation

/// App-only preferences (not shared with the extension). Persisted in standard `UserDefaults`;
/// the App Group holds only the contract keys (SECURITY §3 P4).
///
/// Launch arguments override the stored values once at start, which UI tests and screenshots use:
/// `-settings.language id`, `-settings.mode guardian`, `-settings.onboardingCompleted YES`.
@Observable
final class AppSettings {
    enum Keys {
        static let language = "settings.language"
        static let mode = "settings.mode"
        static let onboardingCompleted = "settings.onboardingCompleted"
        static let familyModeOn = "settings.familyModeOn"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    /// Chosen once in ON-03, never changes. Fase 13 also writes it to the App Group (`device.mode`).
    var mode: UserMode? {
        didSet { defaults.set(mode?.rawValue, forKey: Keys.mode) }
    }

    var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted) }
    }

    /// GD-02: the guardian's last Family mode toggle.
    var familyModeOn: Bool {
        didSet { defaults.set(familyModeOn, forKey: Keys.familyModeOn) }
    }

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:))
            ?? AppLanguage.fromSystem(preferredLanguages: preferredLanguages)
        mode = defaults.string(forKey: Keys.mode).flatMap(UserMode.init(rawValue:))
        onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        familyModeOn = defaults.bool(forKey: Keys.familyModeOn)
    }

    /// Back to a fresh install (used by "Delete my data" later and by tests).
    func reset() {
        for key in [Keys.language, Keys.mode, Keys.onboardingCompleted, Keys.familyModeOn] {
            defaults.removeObject(forKey: key)
        }
        language = AppLanguage.fromSystem()
        mode = nil
        onboardingCompleted = false
        familyModeOn = false
    }
}
