import Foundation

/// Text formatting shared by every screen. All functions take the language explicitly, because
/// the in-app language (PF-01) may differ from the iPhone's.
enum Formatters {
    /// "2 minutes ago" / "2 menit yang lalu" (Activity, Detail DT-03).
    static func relative(_ date: Date, now: Date = Date(), language: AppLanguage) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = language.locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// "92%" — scores are whole numbers 0–100.
    static func percent(_ score: Int, language: AppLanguage) -> String {
        (Double(score) / 100).formatted(.percent.precision(.fractionLength(0)).locale(language.locale))
    }

    /// "21 Oct 2026, 12:05" / "21 Okt 2026, 12.05" (Detail DT-03).
    static func dateTime(_ date: Date, language: AppLanguage, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: language.locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}
