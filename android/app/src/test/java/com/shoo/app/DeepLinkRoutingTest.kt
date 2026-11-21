package com.shoo.app

import com.shoo.app.app.AppEnvironment
import com.shoo.app.app.AppSettings
import com.shoo.app.app.AppTab
import com.shoo.app.app.InMemoryPreferences
import com.shoo.app.app.InviteNotice
import com.shoo.app.app.ProfilePage
import com.shoo.app.app.Route
import com.shoo.app.data.MockRepository
import com.shoo.app.data.UserMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS DeepLinkRoutingTests (PairingTests.swift): what a link does in each mode. */
class DeepLinkRoutingTest {
    private fun environment(
        mode: UserMode?,
        onboarded: Boolean,
        scenario: MockRepository.Scenario = MockRepository.Scenario.STANDARD,
    ): AppEnvironment {
        val settings = AppSettings(InMemoryPreferences())
        if (mode != null) settings.chooseMode(mode)
        settings.onboardingCompleted = onboarded
        val repository = MockRepository(
            mode = mode ?: UserMode.PROTECTED, scenario = scenario, latencyMillis = 0, fixtures = TestFixtures.loader,
        )
        return AppEnvironment(
            repository = repository, settings = settings,
            // The invite check runs at once on the test thread (the mock answers without suspending).
            scope = CoroutineScope(Dispatchers.Unconfined),
            fixtures = TestFixtures.loader,
        )
    }

    /** `open` hands the invite to a coroutine (it asks the server first); the tests wait for it. */
    private fun open(link: String, env: AppEnvironment) {
        env.open(link)
        runBlocking { env.inviteTask?.join() }
    }

    @Test fun protectedWithoutAGuardianOpensConnectWithTheCode() {
        val env = environment(UserMode.PROTECTED, onboarded = true, scenario = MockRepository.Scenario.UNPAIRED)
        env.router.selectedTab = AppTab.ACTIVITY
        open("shoo://join?code=482193", env)
        assertTrue(env.router.isConnectPresented)
        assertEquals("482193", env.router.pendingJoinCode)
        assertEquals(AppTab.SHIELD, env.router.selectedTab)
        assertNull(env.router.inviteNotice)
    }

    @Test fun protectedWithAGuardianIsToldAndTheCodeIsDropped() {
        val env = environment(UserMode.PROTECTED, onboarded = true)
        open("shoo://join?code=482193", env)
        assertFalse(env.router.isConnectPresented)
        assertNull(env.router.pendingJoinCode)
        assertEquals(
            InviteNotice.AlreadyProtected(guardian = MockRepository.protectedProfile.guardian?.name ?: ""),
            env.router.inviteNotice,
        )
    }

    /** Delete = gone at once: the deleted account's banner and code don't greet the next one. */
    @Test fun deletingTheAccountDropsItsInviteBanner() {
        val env = environment(UserMode.PROTECTED, onboarded = true)
        open("shoo://join?code=482193", env)
        assertNotNull(env.router.inviteNotice)
        env.router.pendingJoinCode = "482193"
        env.returnToOnboardingAfterDelete()
        assertNull(env.router.inviteNotice)
        assertNull(env.router.pendingJoinCode)
    }

    @Test fun beforeRegistrationTheCodeWaitsForOnboarding() {
        val env = environment(mode = null, onboarded = false)
        open("shoo://join?code=482193", env)
        assertFalse(env.router.isConnectPresented)
        assertFalse(env.router.isJoinFamilyPresented)
        assertNull(env.router.inviteNotice)
        assertEquals("482193", env.router.takePendingJoinCode())
        assertNull(env.router.pendingJoinCode)
    }

    @Test fun personalWithoutMembersGetsTheInviteNotice() {
        val env = environment(UserMode.GUARDIAN, onboarded = true, scenario = MockRepository.Scenario.EMPTY)
        env.router.selectedTab = AppTab.ACTIVITY
        env.router.activityPath = listOf(Route.Profile)
        open("shoo://join?code=482193", env)
        assertEquals(InviteNotice.Invited, env.router.inviteNotice)
        assertEquals("482193", env.router.pendingJoinCode)
        assertFalse("a link never joins or opens the sheet by itself (T11)", env.router.isJoinFamilyPresented)
        assertEquals(AppTab.SHIELD, env.router.selectedTab)
        assertTrue(env.router.activityPath.isEmpty())
    }

    @Test fun guardianWithMembersIsToldAndTheCodeIsDropped() {
        val env = environment(UserMode.GUARDIAN, onboarded = true)
        open("shoo://join?code=482193", env)
        assertEquals(InviteNotice.HasMembers, env.router.inviteNotice)
        assertNull(env.router.pendingJoinCode)
    }

    @Test fun viewingTheInviteOpensTheJoinSheetWithTheCode() {
        val env = environment(UserMode.GUARDIAN, onboarded = true, scenario = MockRepository.Scenario.EMPTY)
        open("shoo://join?code=482193", env)
        env.router.acceptInvite()
        assertNull(env.router.inviteNotice)
        assertTrue(env.router.isJoinFamilyPresented)
        assertEquals("482193", env.router.takePendingJoinCode())
    }

    @Test fun notNowDropsTheCode() {
        val env = environment(UserMode.GUARDIAN, onboarded = true, scenario = MockRepository.Scenario.EMPTY)
        open("shoo://join?code=482193", env)
        env.router.dismissInviteNotice()
        assertNull(env.router.inviteNotice)
        assertNull(env.router.pendingJoinCode)
        assertFalse(env.router.isJoinFamilyPresented)
    }

    /** Profile is a pushed screen (PF-01): the link pops it and Connect opens at once. */
    @Test fun linkWhileProfileIsOpenClosesItAndShowsConnect() {
        val env = environment(UserMode.PROTECTED, onboarded = true, scenario = MockRepository.Scenario.UNPAIRED)
        env.router.selectedTab = AppTab.ACTIVITY
        env.router.activityPath = listOf(Route.Profile, Route.ProfilePage(ProfilePage.CONNECTION))
        open("shoo://join?code=482193", env)
        assertTrue(env.router.activityPath.isEmpty())
        assertEquals(AppTab.SHIELD, env.router.selectedTab)
        assertTrue(env.router.isConnectPresented)
        assertEquals("482193", env.router.pendingJoinCode)
    }

    @Test fun secondLinkWhileConnectIsOpenOnlyRefillsTheCode() {
        val env = environment(UserMode.PROTECTED, onboarded = true, scenario = MockRepository.Scenario.UNPAIRED)
        open("shoo://join?code=482193", env)
        env.router.takePendingJoinCode()
        open("shoo://join?code=123456", env)
        assertTrue(env.router.isConnectPresented)
        assertEquals("123456", env.router.pendingJoinCode)
    }

    @Test fun secondLinkWhileTheJoinSheetIsOpenOnlyRefillsTheCode() {
        val env = environment(UserMode.GUARDIAN, onboarded = true, scenario = MockRepository.Scenario.EMPTY)
        env.router.isJoinFamilyPresented = true
        open("shoo://join?code=123456", env)
        assertNull(env.router.inviteNotice)
        assertEquals("123456", env.router.pendingJoinCode)
    }

    /** Everyone registers as Pribadi now (PR-03): the code must survive it for the join sheet. */
    @Test fun personalRegistrationKeepsAWaitingCode() {
        val env = environment(mode = null, onboarded = false)
        open("shoo://join?code=482193", env)
        runBlocking { env.register(name = "Rina", mode = UserMode.GUARDIAN) }
        assertEquals("482193", env.router.pendingJoinCode)
        assertEquals(UserMode.GUARDIAN, env.settings.mode)
    }

    /** BH-28: a scan link closes the "Become supervised" sheet and the Guardian intro cover too. */
    @Test fun scanLinkClosesEverySheetAndCover() {
        val env = environment(UserMode.GUARDIAN, onboarded = true)
        env.router.isJoinFamilyPresented = true
        env.router.isGuardianIntroPresented = true
        env.router.isTurnOnPresented = true
        env.open("shoo://scan/6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03")
        assertFalse(env.router.isJoinFamilyPresented)
        assertFalse(env.router.isGuardianIntroPresented)
        assertFalse(env.router.isTurnOnPresented)
        assertEquals(listOf<Route>(Route.Detail("6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03")), env.router.activityPath)
        env.router.isJoinFamilyPresented = true
        env.open("shoo://activity")
        assertFalse(env.router.isJoinFamilyPresented)
    }

    @Test fun scanLinkTellsScreensToCloseTheirOwnSheets() {
        val env = environment(UserMode.GUARDIAN, onboarded = true)
        val before = env.router.screenSheetsClosed
        env.open("shoo://scan/6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03")
        assertEquals(before + 1, env.router.screenSheetsClosed)
        env.open("shoo://activity")
        assertEquals(before + 2, env.router.screenSheetsClosed)
    }

    @Test fun brokenLinkLandsOnShield() {
        val env = environment(UserMode.PROTECTED, onboarded = true)
        env.router.selectedTab = AppTab.ACTIVITY
        env.open("shoo://join?code=12")
        assertFalse(env.router.isConnectPresented)
        assertEquals(AppTab.SHIELD, env.router.selectedTab)
    }

    @Test fun aTappedNotificationOpensDetailOrShield() {
        val env = environment(UserMode.GUARDIAN, onboarded = true)
        env.openPush("scan-1")
        assertEquals(listOf<Route>(Route.Detail("scan-1")), env.router.activityPath)
        env.openPush(null)
        assertEquals(AppTab.SHIELD, env.router.selectedTab)
        assertTrue(env.router.activityPath.isEmpty())
    }

    @Test fun familyModeAsksTheIntroFirstTime() {
        val env = environment(UserMode.GUARDIAN, onboarded = true)
        env.requestFamilyMode()
        assertTrue(env.router.isGuardianIntroPresented)
        assertFalse(env.settings.familyModeOn)
        env.startGuardian()
        assertTrue(env.settings.familyModeOn)
        assertFalse(env.router.isGuardianIntroPresented)
    }
}
