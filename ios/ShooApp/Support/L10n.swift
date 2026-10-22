import SwiftUI

/// Lookup in `Localizable.xcstrings` for a given in-app language.
///
/// SwiftUI `Text("literal")` follows `.environment(\.locale, …)` set in `RootView`.
/// Strings built outside a `Text` (view models, accessibility values, alerts built from `String`)
/// do not, so they go through this helper (D-alief-A02).
enum L10n {
    static func string(_ key: String.LocalizationValue, language: AppLanguage) -> String {
        String(localized: key, bundle: bundle(for: language), locale: language.locale)
    }

    static func bundle(for language: AppLanguage) -> Bundle {
        guard let path = Bundle.main.path(forResource: language.code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
}

extension View {
    /// Navigation title that follows a live in-app language change. `navigationTitle(Text(_:))`
    /// keeps the old language after `\.locale` changes (UI test `testLanguageSwitchesLiveFromProfile`),
    /// a plain `String` title is updated.
    func navigationTitle(localized key: String.LocalizationValue) -> some View {
        modifier(LocalizedNavigationTitle(key: key))
    }
}

private struct LocalizedNavigationTitle: ViewModifier {
    let key: String.LocalizationValue
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content.navigationTitle(L10n.string(key, language: AppLanguage(locale: locale)))
    }
}
