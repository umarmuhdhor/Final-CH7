package com.shoo.app.features.detail

import com.shoo.app.data.Verdict
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneOffset
import java.time.temporal.TemporalAdjusters

/**
 * GD-07: an "Aman" can't be changed until Shoo's next weekly AI review has read it. "Bahaya" stays changeable:
 * blocking more is the safe side, and a mis-tapped Bahaya must be undoable (QA 2026-11-11 #5).
 *
 * The review is the daily `shoo-admin` cron at 18:00 UTC, which only acts when it is Monday in WITA
 * (shoo-dashboard `src/worker/cron/review.ts`), i.e. every Sunday 18:00 UTC.
 * App-side only for now: the server still accepts a change (contract issue for a server lock).
 */
object VerdictLock {
    /** The first weekly review after the decision (Sunday 18:00 UTC, strictly later). */
    fun unlocksAt(decidedAt: Instant): Instant {
        var candidate = decidedAt.atZone(ZoneOffset.UTC).toLocalDate().atTime(18, 0).atZone(ZoneOffset.UTC)
            .with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY))
        if (!candidate.toInstant().isAfter(decidedAt)) candidate = candidate.plusWeeks(1)
        return candidate.toInstant()
    }

    /** When a locked verdict opens again; null when it can be changed now. */
    fun lockedUntil(verdict: Verdict, now: Instant): Instant? {
        if (verdict.value != Verdict.Value.SAFE) return null
        val until = unlocksAt(verdict.decidedAt)
        return if (now.isBefore(until)) until else null
    }
}
