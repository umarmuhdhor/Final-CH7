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

    /// Default: Bahasa Indonesia when the iPhone's first language is Indonesian, else English.
    static func fromSystem(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let first = preferredLanguages.first else { return .english }
        return AppLanguage(locale: Locale(identifier: first))
    }
}
