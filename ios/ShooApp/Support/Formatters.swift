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

    /// "10.42 WIB" / "10:42 AM GMT+7": the hour in the language's style plus the time-zone
    /// abbreviation (Activity rows, PR-05/GD-05).
    static func time(_ date: Date, language: AppLanguage, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("jmz")
        return formatter.string(from: date)
    }

    /// Activity day header: "25 Oktober" / "October 25", with the year when it isn't this year's.
    /// "Today" is the caller's (its wording differs per screen).
    static func day(_ date: Date, now: Date = Date(), language: AppLanguage, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var style = Date.FormatStyle(locale: language.locale, calendar: calendar, timeZone: timeZone).day().month(.wide)
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            style = style.year()
        }
        return date.formatted(style)
    }

    /// "Today · 10.42 WIB" / "Hari ini · 10.42 WIB" (Guardian Home recent rows).
    static func dayAndTime(_ date: Date, now: Date = Date(), language: AppLanguage, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let day: String
        if calendar.isDate(date, inSameDayAs: now) || calendar.isDate(date, inSameDayAs: yesterday) {
            // "today" / "hari ini", "yesterday" / "kemarin", capitalised as the first word.
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = language.locale
            formatter.dateTimeStyle = .named
            formatter.calendar = calendar
            let offset = calendar.isDate(date, inSameDayAs: now) ? 0 : -1
            let word = formatter.localizedString(from: DateComponents(day: offset))
            day = word.prefix(1).uppercased(with: language.locale) + word.dropFirst()
        } else {
            var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: language.locale)
            style.timeZone = timeZone
            day = date.formatted(style)
        }
        var time = Date.FormatStyle(date: .omitted, time: .shortened, locale: language.locale)
        time.timeZone = timeZone
        let zone = timeZone.localizedName(for: .shortStandard, locale: language.locale) ?? ""
        return [day, [date.formatted(time), zone].filter { !$0.isEmpty }.joined(separator: " ")].joined(separator: " · ")
    }
}
