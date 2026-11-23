package com.shoo.app

import com.shoo.app.app.AppTab
import com.shoo.app.app.InviteNotice
import com.shoo.app.app.ProfilePage
import com.shoo.app.app.Route
import com.shoo.app.app.Router
import com.shoo.app.data.ApiRepository
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS PendingInviteTests + the Router rules the routing tests lean on. */
class RouterTest {
    private class Clock {
        var now: Instant = Instant.ofEpochSecond(1_000_000)
    }

    private val lifetime = ApiRepository.codeLifetimeSeconds

    @Test fun theCodeSurvivesUntilItWouldHaveExpired() {
        val clock = Clock()
        val router = Router { clock.now }
        router.pendingJoinCode = "482193"
        clock.now = clock.now.plusSeconds(lifetime - 1)
        router.dropExpiredInvite()
        assertEquals("482193", router.takePendingJoinCode())
    }

    @Test fun anExpiredCodeIsGone() {
        val clock = Clock()
        val router = Router { clock.now }
        router.pendingJoinCode = "482193"
        router.inviteNotice = InviteNotice.Invited
        clock.now = clock.now.plusSeconds(lifetime + 1)
        router.dropExpiredInvite()
        assertNull(router.pendingJoinCode)
        assertNull(router.inviteNotice)
    }

    @Test fun takingAnExpiredCodeGivesNothing() {
        val clock = Clock()
        val router = Router { clock.now }
        router.pendingJoinCode = "482193"
        clock.now = clock.now.plusSeconds(lifetime + 1)
        assertNull(router.takePendingJoinCode())
    }

    @Test fun aNewCodeRestartsTheClock() {
        val clock = Clock()
        val router = Router { clock.now }
        router.pendingJoinCode = "482193"
        clock.now = clock.now.plusSeconds(lifetime - 10)
        router.pendingJoinCode = "123456"
        clock.now = clock.now.plusSeconds(20)
        assertEquals("123456", router.takePendingJoinCode())
    }

    @Test fun openProfileFromTheMembersNotice() {
        val router = Router()
        router.inviteNotice = InviteNotice.HasMembers
        router.openProfileFromInviteNotice()
        assertNull(router.inviteNotice)
        assertEquals(listOf<Route>(Route.Profile), router.shieldPath)
    }

    @Test fun openDetailReplacesTheActivityStackAndClosesSheets() {
        val router = Router()
        router.shieldPath = listOf(Route.Profile)
        router.isTurnOnPresented = true
        router.isGuardianIntroPresented = true
        val before = router.screenSheetsClosed
        router.openDetail("scan-1")
        assertEquals(AppTab.ACTIVITY, router.selectedTab)
        assertTrue(router.shieldPath.isEmpty())
        assertEquals(listOf<Route>(Route.Detail("scan-1")), router.activityPath)
        assertFalse(router.isTurnOnPresented)
        assertFalse(router.isGuardianIntroPresented)
        assertEquals(before + 1, router.screenSheetsClosed)
    }

    @Test fun profileIsPushedOnceOnTheTabOnScreen() {
        val router = Router()
        router.selectedTab = AppTab.ACTIVITY
        router.openProfile()
        router.openProfile()
        router.show(Route.ProfilePage(ProfilePage.THEME))
        assertEquals(listOf(Route.Profile, Route.ProfilePage(ProfilePage.THEME)), router.activityPath)
        router.pop()
        assertEquals(listOf<Route>(Route.Profile), router.activityPath)
        assertTrue(router.shieldPath.isEmpty())
    }

    /** One sheet at a time: Connect waits for the "Turn on" sheet to go. */
    @Test fun connectWaitsForTheOpenSheet() {
        val router = Router()
        router.isTurnOnPresented = true
        router.showConnect()
        assertFalse(router.isTurnOnPresented)
        assertFalse(router.isConnectPresented)
        assertTrue(router.wantsConnect)
        router.sheetDismissed()
        assertTrue(router.isConnectPresented)
        assertFalse(router.wantsConnect)
    }

    @Test fun resetGoesBackToShield() {
        val router = Router()
        router.selectedTab = AppTab.ACTIVITY
        router.activityPath = listOf(Route.Member("dev_dad"))
        router.isJoinFamilyPresented = true
        router.reset()
        assertEquals(AppTab.SHIELD, router.selectedTab)
        assertTrue(router.activityPath.isEmpty())
        assertFalse(router.isJoinFamilyPresented)
    }
}
