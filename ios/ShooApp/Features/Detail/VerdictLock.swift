import Foundation

/// GD-07: an "Aman" can't be changed until Shoo's next weekly AI review has read it. "Bahaya" stays changeable:
/// blocking more is the safe side, and a mis-tapped Bahaya must be undoable (QA 2026-11-11 #5).
///
/// The review is the daily `shoo-admin` cron at 18:00 UTC, which only acts when it is Monday in WITA
/// (shoo-dashboard `src/worker/cron/review.ts`), i.e. every Sunday 18:00 UTC.
/// App-side only for now: the server still accepts a change (contract issue for a server lock).
enum VerdictLock {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// The first weekly review after the decision.
    static func unlocksAt(decidedAt: Date) -> Date {
        utc.nextDate(
            after: decidedAt,
            matching: DateComponents(hour: 18, minute: 0, second: 0, weekday: 1),
            matchingPolicy: .nextTime
        ) ?? decidedAt
    }

    /// When a locked verdict opens again; `nil` when it can be changed now.
    static func lockedUntil(_ verdict: Verdict, now: Date) -> Date? {
        guard verdict.value == .safe else { return nil }
        let until = unlocksAt(decidedAt: verdict.decidedAt)
        return now < until ? until : nil
    }
}
