package com.shoo.app

import com.shoo.app.app.DeepLink
import com.shoo.app.data.APIErrorCode
import com.shoo.app.data.ApiRepository
import com.shoo.app.data.MockRepository
import com.shoo.app.data.RepositoryError
import com.shoo.app.data.ScanOwnerFilter
import com.shoo.app.data.ScanStatus
import com.shoo.app.data.UserMode
import com.shoo.app.data.Verdict
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS MockRepositoryTests: the fixture backend answers like the contract. */
class MockRepositoryTest {
    private fun guardian(pageSize: Int = MockRepository.pageSize) =
        MockRepository(mode = UserMode.GUARDIAN, latencyMillis = 0, pageSize = pageSize, fixtures = TestFixtures.loader)

    private fun protected() = MockRepository(mode = UserMode.PROTECTED, latencyMillis = 0, fixtures = TestFixtures.loader)

    private fun apiCode(block: suspend () -> Unit): APIErrorCode? = runBlocking {
        try {
            block()
            null
        } catch (error: RepositoryError) {
            error.apiCode
        }
    }

    @Test fun familyListsEveryFixtureNewestFirstWithoutScreenshots() = runBlocking {
        val page = guardian().scans(ScanOwnerFilter.Family, null, null)
        assertEquals(5, page.items.size)
        assertEquals(page.items.map { it.detectedAt }.sortedDescending(), page.items.map { it.detectedAt })
        assertTrue(page.items.all { it.screenshotUrl == null })
        assertNull(page.nextCursor)
    }

    @Test fun ownerMeIsOnlyMyScans() = runBlocking {
        val page = guardian().scans(ScanOwnerFilter.Me, null, null)
        assertEquals(listOf("dev_me"), page.items.map { it.ownerDeviceId })
    }

    @Test fun ownerDeviceAndStatusFilter() = runBlocking {
        val page = guardian().scans(ScanOwnerFilter.Device("dev_mom"), ScanStatus.BLOCKED, null)
        assertTrue(page.items.isNotEmpty())
        assertTrue(page.items.all { it.ownerDeviceId == "dev_mom" && it.status == ScanStatus.BLOCKED })
    }

    @Test fun cursorPagesThroughEverything() = runBlocking {
        val repo = guardian(pageSize = 2)
        var cursor: String? = null
        val ids = mutableListOf<String>()
        do {
            val page = repo.scans(ScanOwnerFilter.Family, null, cursor)
            assertTrue(page.items.size <= 2)
            ids += page.items.map { it.id }
            cursor = page.nextCursor
        } while (cursor != null)
        assertEquals(5, ids.size)
        assertEquals(5, ids.toSet().size)
    }

    @Test fun protectedCannotListFamily() {
        assertEquals(APIErrorCode.forbidden, apiCode { protected().scans(ScanOwnerFilter.Family, null, null) })
    }

    @Test fun protectedSeesOnlyOwnScans() = runBlocking {
        val page = protected().scans(ScanOwnerFilter.Me, null, null)
        assertTrue(page.items.isNotEmpty())
        assertTrue(page.items.all { it.ownerDeviceId == "dev_mom" })
    }

    @Test fun scanDetailKeepsScreenshotUrl() = runBlocking {
        assertNotNull(guardian().scan("6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03").screenshotUrl)
    }

    @Test fun protectedCannotOpenSomeoneElsesScan() {
        // blocked-verified-scam belongs to dev_dad.
        assertEquals(APIErrorCode.notFound, apiCode { protected().scan("6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e04") })
    }

    @Test fun unknownScanIsNotFound() {
        assertEquals(APIErrorCode.notFound, apiCode { guardian().scan("nope") })
        assertEquals(APIErrorCode.notFound, apiCode { guardian().setVerdict("nope", Verdict.Value.SAFE) })
    }

    @Test fun badCursorIsInvalidBody() {
        assertEquals(APIErrorCode.invalidBody, apiCode { guardian().scans(ScanOwnerFilter.Family, null, "99") })
    }

    @Test fun removedMemberScansAreNoLongerVisible() = runBlocking {
        val repo = guardian()
        repo.removeMember("dev_dad")
        val page = repo.scans(ScanOwnerFilter.Family, null, null)
        assertFalse(page.items.any { it.ownerDeviceId == "dev_dad" })
        assertEquals(APIErrorCode.notFound, apiCode { repo.scans(ScanOwnerFilter.Device("dev_dad"), null, null) })
    }

    @Test fun verdictAppliesToBlockedScanAndIsStored() = runBlocking {
        val repo = guardian()
        val verdict = repo.setVerdict("6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03", Verdict.Value.SAFE)
        assertEquals(Verdict.Value.SAFE, verdict.value)
        assertEquals("dev_me", verdict.byDeviceId)
        assertEquals(verdict, repo.scan("6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03").verdict)
    }

    @Test fun verdictNotesAreKeptOnlyForTheLastCall() = runBlocking {
        val repo = guardian()
        repo.setVerdict("6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03", Verdict.Value.NOT_SAFE, "Asks for my PIN")
        assertEquals("Asks for my PIN", repo.lastVerdictNotes)
        repo.setVerdict("6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03", Verdict.Value.SAFE)
        assertNull(repo.lastVerdictNotes)
    }

    @Test fun protectedCannotSetVerdict() {
        assertEquals(
            APIErrorCode.verdictNotAllowed,
            apiCode { protected().setVerdict("6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03", Verdict.Value.SAFE) },
        )
    }

    @Test fun magicCodesGiveTheirErrors() {
        val cases = mapOf(
            "000000" to APIErrorCode.codeInvalid,
            "999999" to APIErrorCode.codeExpired,
            "888888" to APIErrorCode.familyFull,
            "777777" to APIErrorCode.tooManyAttempts,
            "555555" to APIErrorCode.rateLimited,
            "666666" to APIErrorCode.alreadyConnected,
        )
        for ((code, expected) in cases) {
            val repo = MockRepository(
                mode = UserMode.PROTECTED, scenario = MockRepository.Scenario.UNPAIRED, latencyMillis = 0,
                fixtures = TestFixtures.loader,
            )
            assertEquals(code, expected, apiCode { repo.joinFamily(code) })
        }
        val throttled = runCatching {
            runBlocking {
                MockRepository(UserMode.PROTECTED, MockRepository.Scenario.UNPAIRED, 0, fixtures = TestFixtures.loader).joinFamily("777777")
            }
        }.exceptionOrNull() as RepositoryError
        assertEquals(299.0, throttled.retryAfter!!, 0.0)
    }

    @Test fun joinWhileConnectedIsAlreadyConnected() {
        assertEquals(APIErrorCode.alreadyConnected, apiCode { protected().joinFamily("482193") })
    }

    @Test fun leaveWithoutGuardianIsNotFound() = runBlocking {
        val repo = protected()
        repo.leaveGuardian()
        assertEquals(APIErrorCode.notFound, apiCode { repo.leaveGuardian() })
    }

    @Test fun wrongModeIsForbidden() {
        assertEquals(APIErrorCode.forbidden, apiCode { guardian().joinFamily("482193") })
        assertEquals(APIErrorCode.forbidden, apiCode { protected().removeMember("dev_dad") })
    }

    @Test fun joinWithValidCodeReturnsGuardian() = runBlocking {
        val repo = protected()
        repo.leaveGuardian()
        assertNull(repo.me().guardian)
        val guardian = repo.joinFamily("482193")
        assertEquals("Adhella", guardian.name)
        assertEquals(guardian, repo.me().guardian)
    }

    @Test fun familyCodeIsSixDigitsValidFor30Minutes() = runBlocking {
        val now = Instant.ofEpochSecond(1_000_000)
        val repo = MockRepository(mode = UserMode.GUARDIAN, latencyMillis = 0, fixtures = TestFixtures.loader, now = { now })
        val code = repo.createFamilyCode(refresh = false)
        assertTrue(DeepLink.isCode(code.code))
        assertEquals(now.plusSeconds(30 * 60), code.expiresAt)
        assertEquals("https://join.shoo.ai.id/j/${code.code}", code.inviteUrl)
    }

    @Test fun familyCodeIsReusedUntilRefreshed() = runBlocking {
        var now = Instant.ofEpochSecond(1_000_000)
        val repo = MockRepository(mode = UserMode.GUARDIAN, latencyMillis = 0, fixtures = TestFixtures.loader, now = { now })
        val first = repo.createFamilyCode(refresh = false)
        now = now.plusSeconds(24 * 60)
        assertEquals(first, repo.createFamilyCode(refresh = false))
        now = now.plusSeconds(60)
        assertNotEquals(first.expiresAt, repo.createFamilyCode(refresh = false).expiresAt)
        val refreshed = repo.createFamilyCode(refresh = true)
        assertTrue(refreshed.expiresAt.isAfter(first.expiresAt))
        assertEquals(ApiRepository.codeLifetimeSeconds, java.time.Duration.between(now, refreshed.expiresAt).seconds)
    }

    @Test fun protectedCannotCreateFamilyCode() {
        assertEquals(APIErrorCode.forbidden, apiCode { protected().createFamilyCode(refresh = false) })
    }

    @Test fun membersAndRemove() = runBlocking {
        val repo = guardian()
        assertEquals(2, repo.familyMembers().size)
        repo.removeMember("dev_dad")
        assertEquals(listOf("dev_mom"), repo.familyMembers().map { it.deviceId })
        assertEquals(APIErrorCode.notFound, apiCode { repo.removeMember("dev_dad") })
    }

    @Test fun failuresParseAndApply() = runBlocking {
        val failures = MockRepository.failures("me,setVerdict=verdict_not_allowed,scans~1")
        assertEquals(RepositoryError.Network, failures["me"])
        assertEquals(APIErrorCode.verdictNotAllowed, failures["setVerdict"]?.apiCode)
        val repo = MockRepository(UserMode.GUARDIAN, latencyMillis = 0, fixtures = TestFixtures.loader, failures = failures)
        assertEquals(5, repo.scans(ScanOwnerFilter.Family, null, null).items.size)
        val second = runCatching { repo.scans(ScanOwnerFilter.Family, null, null) }.exceptionOrNull()
        assertEquals(RepositoryError.Network, second)
    }

    @Test fun figmaScenarioHasThreeMembersAndScamCards() = runBlocking {
        val repo = MockRepository(
            UserMode.GUARDIAN, MockRepository.Scenario.FIGMA, latencyMillis = 0, fixtures = TestFixtures.loader,
        )
        assertEquals(listOf("dev_syahnaz", "dev_bayu", "dev_renatta"), repo.familyMembers().map { it.deviceId })
        assertEquals(3, repo.latestScams().size)
        assertEquals("Adhella", repo.me().name)
    }

    @Test fun linkIsOriginAndPath() {
        assertEquals("https://bca-verifikasi.site/login", MockRepository.link("https://BCA-verifikasi.site/login?ref=wa#x"))
        assertEquals("https://example.com/", MockRepository.link("https://example.com"))
    }
}
