package com.shoo.app.features.detail

import com.shoo.app.data.Verdict
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.Formatters
import com.shoo.app.support.L10n
import java.time.Duration
import java.time.Instant

/** DT-06: who decided. "by you" when the viewer decided (PRD §5 Validasi). */
object VerdictNote {
    /** One line for TalkBack and the header value: "Verified scam by Adhella". */
    fun text(verdict: Verdict, viewerDeviceId: String?, language: AppLanguage): String {
        val name = verdict.byName
        val byViewer = verdict.byDeviceId == viewerDeviceId
        return when (verdict.value) {
            Verdict.Value.NOT_SAFE ->
                if (byViewer) L10n.string("Verified scam by you", language) else L10n.string("Verified scam by %@", language, name)
            Verdict.Value.SAFE ->
                if (byViewer) L10n.string("Marked safe by you", language) else L10n.string("Marked safe by %@", language, name)
            // #493: a verdict this build can't read says who looked, never that it is safe.
            Verdict.Value.UNKNOWN ->
                if (byViewer) L10n.string("Checked by you", language) else L10n.string("Checked by %@", language, name)
        }
    }

    /** Under the card title (Figma "oleh Adhella · Baru saja"). */
    fun byline(verdict: Verdict, viewerDeviceId: String?, now: Instant = Instant.now(), language: AppLanguage): String {
        val elapsed = Duration.between(verdict.decidedAt, now).seconds
        val `when` = if (elapsed < 60) {
            L10n.string("Just now", language)
        } else {
            Formatters.relative(verdict.decidedAt, language, now)
        }
        return if (verdict.byDeviceId == viewerDeviceId) {
            L10n.string("by you · %@", language, `when`)
        } else {
            L10n.string("by %@ · %@", language, verdict.byName, `when`)
        }
    }

    /** The chip under a safe item's badge (Figma "Anda menandai ini aman"). */
    fun markedSafeChip(verdict: Verdict, viewerDeviceId: String?, language: AppLanguage): String =
        if (verdict.byDeviceId == viewerDeviceId) {
            L10n.string("You marked this safe", language)
        } else {
            L10n.string("Marked safe by %@", language, verdict.byName)
        }
}
