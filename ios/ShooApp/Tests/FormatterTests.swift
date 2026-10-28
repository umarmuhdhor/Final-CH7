import Foundation
import Testing
@testable import Shoo

struct FormatterTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    @Test func relativeTimeInBothLanguages() {
        let date = now.addingTimeInterval(-120)
        #expect(Formatters.relative(date, now: now, language: .english) == "2 minutes ago")
        #expect(Formatters.relative(date, now: now, language: .indonesian) == "2 menit yang lalu")
    }

    @Test(arguments: [(92, "92%"), (41, "41%"), (100, "100%")])
    func percent(score: Int, expected: String) {
        #expect(Formatters.percent(score, language: .english) == expected)
        #expect(Formatters.percent(score, language: .indonesian) == expected)
    }

    @Test func dateTimeUsesLanguageMonthNames() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-21T04:05:00Z"))
        let english = Formatters.dateTime(date, language: .english, timeZone: utc)
        let indonesian = Formatters.dateTime(date, language: .indonesian, timeZone: utc)
        #expect(english.contains("Oct"))
        #expect(indonesian.contains("Okt"))
        #expect(english.contains("2026") && indonesian.contains("2026"))
    }

    @Test func activityTimeHasTheTimeZoneAbbreviation() throws {
        let jakarta = try #require(TimeZone(identifier: "Asia/Jakarta"))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-25T03:42:00Z"))
        #expect(Formatters.time(date, language: .indonesian, timeZone: jakarta) == "10.42 WIB")
        #expect(Formatters.time(date, language: .english, timeZone: jakarta).hasPrefix("10:42\u{202F}AM")
            || Formatters.time(date, language: .english, timeZone: jakarta).hasPrefix("10:42 AM"))
    }

    @Test func activityDayAddsTheYearOnlyForPastYears() throws {
        let jakarta = try #require(TimeZone(identifier: "Asia/Jakarta"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-28T03:00:00Z"))
        let thisYear = try #require(ISO8601DateFormatter().date(from: "2026-10-25T03:42:00Z"))
        let lastYear = try #require(ISO8601DateFormatter().date(from: "2025-09-08T03:42:00Z"))
        #expect(Formatters.day(thisYear, now: now, language: .indonesian, timeZone: jakarta) == "25 Oktober")
        #expect(Formatters.day(thisYear, now: now, language: .english, timeZone: jakarta) == "October 25")
        #expect(Formatters.day(lastYear, now: now, language: .indonesian, timeZone: jakarta) == "8 September 2025")
        #expect(Formatters.day(lastYear, now: now, language: .english, timeZone: jakarta) == "September 8, 2025")
    }
}
