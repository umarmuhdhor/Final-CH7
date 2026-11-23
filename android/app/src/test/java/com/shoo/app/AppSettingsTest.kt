package com.shoo.app

import com.shoo.app.app.AppSettings
import com.shoo.app.app.DataConsent
import com.shoo.app.app.InMemoryPreferences
import com.shoo.app.components.AppTheme
import com.shoo.app.components.TextSizeLevel
import com.shoo.app.data.ExtensionStatus
import com.shoo.app.data.UserMode
import com.shoo.app.support.AppLanguage
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS AppSettingsTests + ExtensionStatusTests (the pure rule). */
class AppSettingsTest {
    @Test fun freshInstallDefaults() {
        val settings = AppSettings(InMemoryPreferences())
        assertEquals(AppLanguage.INDONESIAN, settings.language)
        assertNull(settings.mode)
        assertNull(settings.dataConsent)
        assertEquals(AppTheme.SYSTEM, settings.theme)
        assertEquals(TextSizeLevel.STANDARD, settings.textSize)
        assertTrue(settings.haptics)
        assertFalse(settings.onboardingCompleted)
    }

    @Test fun valuesSurviveARelaunch() {
        val prefs = InMemoryPreferences()
        val settings = AppSettings(prefs)
        settings.language = AppLanguage.ENGLISH
        settings.chooseMode(UserMode.PROTECTED)
        settings.dataConsent = DataConsent.DECLINED
        settings.theme = AppTheme.DARK
        settings.textSize = TextSizeLevel.LARGEST
        settings.haptics = false
        settings.dismissHomeScan("scan-1")
        val again = AppSettings(prefs)
        assertEquals(AppLanguage.ENGLISH, again.language)
        assertEquals(UserMode.PROTECTED, again.mode)
        assertEquals(DataConsent.DECLINED, again.dataConsent)
        assertEquals(AppTheme.DARK, again.theme)
        assertEquals(TextSizeLevel.LARGEST, again.textSize)
        assertFalse(again.haptics)
        assertEquals(listOf("scan-1"), again.dismissedHomeScanIds)
    }

    @Test fun theModeIsChosenOnce() {
        val settings = AppSettings(InMemoryPreferences())
        assertTrue(settings.chooseMode(UserMode.GUARDIAN))
        assertFalse(settings.chooseMode(UserMode.PROTECTED))
        assertEquals(UserMode.GUARDIAN, settings.mode)
        settings.becameProtected()
        assertEquals(UserMode.PROTECTED, settings.mode)
        assertTrue(settings.onboardingConnectPassed)
    }

    @Test fun theOldLargeTextSwitchStartsTheSlider() {
        val prefs = InMemoryPreferences()
        prefs.edit().putBoolean(AppSettings.Keys.largeText, true).apply()
        assertEquals(TextSizeLevel.LARGE, AppSettings(prefs).textSize)
    }

    @Test fun dismissedCardsKeepTheNewest50() {
        val settings = AppSettings(InMemoryPreferences())
        repeat(60) { settings.dismissHomeScan("scan-$it") }
        settings.dismissHomeScan("scan-59")
        assertEquals(50, settings.dismissedHomeScanIds.size)
        assertEquals("scan-10", settings.dismissedHomeScanIds.first())
        assertEquals("scan-59", settings.dismissedHomeScanIds.last())
    }

    @Test fun resetIsAFreshInstall() {
        val settings = AppSettings(InMemoryPreferences())
        settings.enterDemo()
        assertTrue(settings.demoMode)
        settings.reset()
        assertNull(settings.mode)
        assertFalse(settings.demoMode)
        assertFalse(settings.onboardingCompleted)
        assertEquals(AppLanguage.INDONESIAN, settings.language)
    }

    @Test fun extensionStatusRule() {
        val now = Instant.parse("2026-10-21T04:05:00Z")
        assertEquals(
            ExtensionStatus.Off(null, ExtensionStatus.OffReason.NOT_SEEN),
            ExtensionStatus.evaluate(lastSeen = null, now = now),
        )
        assertTrue(ExtensionStatus.evaluate(lastSeen = now.minusSeconds(3600), now = now).isActive)
        assertFalse(ExtensionStatus.evaluate(lastSeen = now.minusSeconds(25 * 3600), now = now).isActive)
        assertEquals(
            ExtensionStatus.OffReason.SOME_SITES_ONLY,
            (ExtensionStatus.evaluate(lastSeen = now, allSites = false, now = now) as ExtensionStatus.Off).reason,
        )
        assertEquals(
            ExtensionStatus.OffReason.SWITCHED_OFF,
            (ExtensionStatus.evaluate(lastSeen = now, enabled = false, now = now) as ExtensionStatus.Off).reason,
        )
        assertEquals(ExtensionStatus.NextStep.OPEN_A_WEBSITE, ExtensionStatus.evaluate(null, enabled = true, now = now).nextStep)
        assertNull(ExtensionStatus.evaluate(now, enabled = true, now = now).nextStep)
        // A heartbeat from the future (clock change) still counts as recent.
        assertTrue(ExtensionStatus.evaluate(lastSeen = now.plusSeconds(3600), now = now).isActive)
    }
}
