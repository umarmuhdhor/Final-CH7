package com.shoo.app

import com.shoo.app.support.AppLanguage
import com.shoo.app.support.L10n
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test

/** support/L10n.kt against the real String Catalogs (the same files the build copies into the APK). */
class L10nTest {
    companion object {
        private val ios = File("../../ios/ShooApp/Resources/Localizable.xcstrings")
        private val android = File("src/main/l10n/android.xcstrings")

        @JvmStatic
        @BeforeClass
        fun loadCatalogs() {
            L10n.load(listOf(ios.readText(), android.readText()))
        }
    }

    @Test fun catalogsParse() {
        assertTrue(L10n.parse(ios.readText()).size > 500)
        // Android-only copy starts empty but must stay a valid catalog.
        L10n.parse(android.readText())
    }

    @Test fun indonesianValue() {
        assertEquals("Aktivitas Terakhir", L10n.string("Recent activity", AppLanguage.INDONESIAN))
    }

    @Test fun missingEnglishReadsAsTheKey() {
        assertEquals("Recent activity", L10n.string("Recent activity", AppLanguage.ENGLISH))
        assertEquals("Not in any catalog", L10n.string("Not in any catalog", AppLanguage.INDONESIAN))
    }

    @Test fun keyIsFormattedWhenMissing() {
        assertEquals("3 days ago", L10n.string("%lld days ago", AppLanguage.ENGLISH, 3))
        assertEquals("3 hari lalu", L10n.string("%lld days ago", AppLanguage.INDONESIAN, 3))
        assertEquals("Budi opened", L10n.string("%@ opened", AppLanguage.ENGLISH, "Budi"))
    }

    @Test fun pluralsPickByFirstInteger() {
        assertEquals("Try again in 1 hour", L10n.string("Try again in %lld hours", AppLanguage.ENGLISH, 1))
        assertEquals("Try again in 2 hours", L10n.string("Try again in %lld hours", AppLanguage.ENGLISH, 2L))
        assertEquals("Try again in 0 hours", L10n.string("Try again in %lld hours", AppLanguage.ENGLISH, 0))
        // Indonesian has no "one" form.
        assertEquals("Coba lagi dalam 1 jam", L10n.string("Try again in %lld hours", AppLanguage.INDONESIAN, 1))
    }

    @Test fun positionalArguments() {
        assertEquals("Budi, 2 dari 3", L10n.string("%@, %lld of %lld", AppLanguage.INDONESIAN, "Budi", 2, 3))
        assertEquals("Budi, 2 of 3", L10n.string("%@, %lld of %lld", AppLanguage.ENGLISH, "Budi", 2, 3))
    }

    @Test fun formatConversion() {
        assertEquals("%s", L10n.convertFormat("%@"))
        assertEquals("%d %d %d %d", L10n.convertFormat("%lld %ld %d %u"))
        assertEquals("%1\$s and %2\$d", L10n.convertFormat("%1\$@ and %2\$lld"))
        assertEquals("100%% of %s", L10n.convertFormat("100%% of %@"))
        assertEquals("%.1f", L10n.convertFormat("%.1f"))
        assertEquals("92% safe", L10n.format("%lld%% safe", arrayOf(92)))
    }

    @Test fun noArgumentsKeepsTheTextAsItStands() {
        assertEquals("100% sure", L10n.format("100% sure", emptyArray()))
    }

    @Test fun badFormatFallsBackToTheTemplate() {
        assertEquals("%lld and %lld", L10n.format("%lld and %lld", arrayOf(1)))
    }
}
