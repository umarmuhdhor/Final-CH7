import Foundation
import Testing
@testable import Shoo

/// Home "Scam terbaru" card: "Hari ini" / "Kemarin" / "N hari lalu" by calendar day on the phone.
struct ScamCaseAgeTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    @Test func calendarDaysNotHours() {
        let now = date("2026-11-17T01:00:00Z") // 08:00 WIB
        #expect(ScamCaseAge.days(from: date("2026-11-17T00:00:00Z"), to: now, calendar: calendar) == 0)
        // 23:00 WIB the night before: only 9 hours ago, but yesterday.
        #expect(ScamCaseAge.days(from: date("2026-11-16T16:00:00Z"), to: now, calendar: calendar) == 1)
        #expect(ScamCaseAge.days(from: date("2026-11-14T02:00:00Z"), to: now, calendar: calendar) == 3)
    }

    @Test func aTimeAheadOfThePhoneClockIsToday() {
        let now = date("2026-11-17T01:00:00Z")
        #expect(ScamCaseAge.days(from: date("2026-11-18T03:00:00Z"), to: now, calendar: calendar) == 0)
    }
}
