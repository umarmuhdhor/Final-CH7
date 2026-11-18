import Foundation

/// In-app language (PF-01). Changes the app only; the extension follows the iPhone language
/// (contracts/app-group-keys.md "Language").
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case indonesian = "id"

    var id: String { rawValue }
    /// Language code for `LocalizedText.text(for:)` and `PATCH /devices/me {language}`.
    var code: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    /// Shown in its own language so people can always find theirs.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .indonesian: "Bahasa Indonesia"
        }
    }

    /// The app language a SwiftUI `\.locale` stands for (set from `AppSettings.language` in `RootView`).
    init(locale: Locale) {
        self = locale.language.languageCode?.identifier == "id" ? .indonesian : .english
    }

    /// Fresh install: Bahasa Indonesia, whatever the iPhone language is. Profile changes it (`settings.language`).
    static let defaultLanguage: AppLanguage = .indonesian
}
