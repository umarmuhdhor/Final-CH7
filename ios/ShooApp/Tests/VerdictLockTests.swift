import Foundation
import Testing
@testable import Shoo

/// GD-07: "Aman" locks until the next weekly review (Sunday 18:00 UTC = Monday 02:00 WITA).
struct VerdictLockTests {
    private static func date(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }
    private static func verdict(_ value: Verdict.Value, at iso: String) -> Verdict {
        Verdict(value: value, byDeviceId: "dev_me", byName: "Adhella", decidedAt: date(iso))
    }

    @Test func unlocksAtTheNextSundayRun() {
        // Thursday 12 Nov 2026 → Sunday 15 Nov 18:00 UTC.
        #expect(VerdictLock.unlocksAt(decidedAt: Self.date("2026-11-12T12:00:00Z")) == Self.date("2026-11-15T18:00:00Z"))
        // Right after a run → the one a week later.
        #expect(VerdictLock.unlocksAt(decidedAt: Self.date("2026-11-15T18:00:00Z")) == Self.date("2026-11-22T18:00:00Z"))
        // Sunday before the run → the same evening.
        #expect(VerdictLock.unlocksAt(decidedAt: Self.date("2026-11-15T17:59:00Z")) == Self.date("2026-11-15T18:00:00Z"))
    }

    @Test func safeIsLockedUntilTheRun() {
        let safe = Self.verdict(.safe, at: "2026-11-12T12:00:00Z")
        #expect(VerdictLock.lockedUntil(safe, now: Self.date("2026-11-14T00:00:00Z")) == Self.date("2026-11-15T18:00:00Z"))
        #expect(VerdictLock.lockedUntil(safe, now: Self.date("2026-11-15T18:00:00Z")) == nil)
    }

    @Test func dangerIsNeverLocked() {
        let danger = Self.verdict(.notSafe, at: "2026-11-12T12:00:00Z")
        #expect(VerdictLock.lockedUntil(danger, now: Self.date("2026-11-12T12:01:00Z")) == nil)
    }
}
