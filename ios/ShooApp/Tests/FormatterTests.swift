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
}
