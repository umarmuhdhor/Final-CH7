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
        /// Before the text size slider: "Teks besar" on/off. Read once to pick the slider's start.
        static let largeText = "settings.largeText"
        static let theme = "settings.theme"
        static let textSize = "settings.textSize"
        static let boldText = "settings.boldText"
        static let highContrast = "settings.highContrast"
        static let reduceMotion = "settings.reduceMotion"
        static let reduceGlass = "settings.reduceGlass"
        static let haptics = "settings.haptics"
        static let readAloud = "settings.readAloud"

        static let all = [
            language, mode, onboardingCompleted, familyModeOn, onboardingConnectPassed, largeText,
            theme, textSize, boldText, highContrast, reduceMotion, reduceGlass, haptics, readAloud,
        ]
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

    // PF-01 Tema and Aksesibilitas. Applied to the window scene by `AppearanceOverrides` (RootView).

    var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    var textSize: TextSizeLevel {
        didSet { defaults.set(textSize.rawValue, forKey: Keys.textSize) }
    }

    var boldText: Bool {
        didSet { defaults.set(boldText, forKey: Keys.boldText) }
    }

    var highContrast: Bool {
        didSet { defaults.set(highContrast, forKey: Keys.highContrast) }
    }

    /// "Kurangi gerakan": no animated transitions in Shoo (the iPhone's Reduce Motion also counts).
    var reduceMotion: Bool {
        didSet { defaults.set(reduceMotion, forKey: Keys.reduceMotion) }
    }

    /// "Kurangi efek kaca": solid backgrounds instead of glass.
    var reduceGlass: Bool {
        didSet { defaults.set(reduceGlass, forKey: Keys.reduceGlass) }
    }

    /// "Getar": a warning haptic when a warning reaches you in the app.
    var haptics: Bool {
        didSet { defaults.set(haptics, forKey: Keys.haptics) }
    }

    /// "Bacakan peringatan": VoiceOver reads the score and reasons when a warning opens.
    var readAloud: Bool {
        didSet { defaults.set(readAloud, forKey: Keys.readAloud) }
    }

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:))
            ?? AppLanguage.fromSystem(preferredLanguages: preferredLanguages)
        mode = defaults.string(forKey: Keys.mode).flatMap(UserMode.init(rawValue:))
        onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        familyModeOn = defaults.bool(forKey: Keys.familyModeOn)
        onboardingConnectPassed = defaults.bool(forKey: Keys.onboardingConnectPassed)
        theme = defaults.string(forKey: Keys.theme).flatMap(AppTheme.init(rawValue:)) ?? .system
        if defaults.object(forKey: Keys.textSize) != nil {
            textSize = TextSizeLevel(rawValue: defaults.integer(forKey: Keys.textSize)) ?? .standard
        } else {
            // The old "Teks besar" switch meant at least xLarge.
            textSize = defaults.bool(forKey: Keys.largeText) ? .large : .standard
        }
        boldText = defaults.bool(forKey: Keys.boldText)
        highContrast = defaults.bool(forKey: Keys.highContrast)
        reduceMotion = defaults.bool(forKey: Keys.reduceMotion)
        reduceGlass = defaults.bool(forKey: Keys.reduceGlass)
        haptics = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        readAloud = defaults.bool(forKey: Keys.readAloud)
    }

    /// Saves the ON-03 choice. Returns `false` and changes nothing when a mode is already saved.
    @discardableResult
    func chooseMode(_ mode: UserMode) -> Bool {
        guard self.mode == nil else { return false }
        self.mode = mode
        return true
    }

    /// PF-01 "Punya kode undangan?": this iPhone now protected by another guardian (a new device on
    /// the server; the mode itself never changes on a device). Family mode belongs to guardians.
    func becameProtected() {
        mode = .protected
        familyModeOn = false
        onboardingConnectPassed = true
    }

    /// Removes every stored preference (fresh install), e.g. `-UITestReset YES` before launch.
    static func clear(defaults: UserDefaults) {
        for key in Keys.all {
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
        theme = .system
        textSize = .standard
        boldText = false
        highContrast = false
        reduceMotion = false
        reduceGlass = false
        haptics = true
        readAloud = false
    }
}
