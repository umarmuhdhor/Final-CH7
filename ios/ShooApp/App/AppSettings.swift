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
        static let onboardingConnectPassed = "settings.onboardingConnectPassed"
        static let largeText = "settings.largeText"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    /// Chosen once in ON-03, never changes (`chooseMode`). Fase 13 also writes it to the App Group (`device.mode`).
    private(set) var mode: UserMode? {
        didSet { defaults.set(mode?.rawValue, forKey: Keys.mode) }
    }

    var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted) }
    }

    /// Protected passed the Connect step of onboarding (resume point after a relaunch).
    var onboardingConnectPassed: Bool {
        didSet { defaults.set(onboardingConnectPassed, forKey: Keys.onboardingConnectPassed) }
    }

    /// GD-02: the guardian's last Family mode toggle.
    var familyModeOn: Bool {
        didSet { defaults.set(familyModeOn, forKey: Keys.familyModeOn) }
    }

    /// PF-01 Aksesibilitas "Teks besar": text at least `.xLarge` in the app; a larger system size still wins.
    var largeText: Bool {
        didSet { defaults.set(largeText, forKey: Keys.largeText) }
    }

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:))
            ?? AppLanguage.fromSystem(preferredLanguages: preferredLanguages)
        mode = defaults.string(forKey: Keys.mode).flatMap(UserMode.init(rawValue:))
        onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        familyModeOn = defaults.bool(forKey: Keys.familyModeOn)
        onboardingConnectPassed = defaults.bool(forKey: Keys.onboardingConnectPassed)
        largeText = defaults.bool(forKey: Keys.largeText)
    }

    /// Saves the ON-03 choice. Returns `false` and changes nothing when a mode is already saved.
    @discardableResult
    func chooseMode(_ mode: UserMode) -> Bool {
        guard self.mode == nil else { return false }
        self.mode = mode
        return true
    }

    /// Removes every stored preference (fresh install), e.g. `-UITestReset YES` before launch.
    static func clear(defaults: UserDefaults) {
        for key in [Keys.language, Keys.mode, Keys.onboardingCompleted, Keys.familyModeOn, Keys.onboardingConnectPassed, Keys.largeText] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Back to a fresh install (used by "Delete my data" later and by tests).
    func reset() {
        Self.clear(defaults: defaults)
        language = AppLanguage.fromSystem()
        mode = nil
        onboardingCompleted = false
        familyModeOn = false
        onboardingConnectPassed = false
        largeText = false
    }
}
