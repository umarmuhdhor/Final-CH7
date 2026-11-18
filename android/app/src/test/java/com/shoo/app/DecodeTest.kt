package com.shoo.app

import com.shoo.app.data.APIErrorBody
import com.shoo.app.data.APIErrorCode
import com.shoo.app.data.DeviceProfile
import com.shoo.app.data.DeviceUpdate
import com.shoo.app.data.FamilyMembersResponse
import com.shoo.app.data.LatestScamsPage
import com.shoo.app.data.LoadFailure
import com.shoo.app.data.NotificationSettingsUpdate
import com.shoo.app.data.RepositoryError
import com.shoo.app.data.ScanPage
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ScanStatus
import com.shoo.app.data.ScoreThreshold
import com.shoo.app.data.ShooJson
import com.shoo.app.data.UserMode
import com.shoo.app.data.Verdict
import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS FixtureTests + UnknownEnumMappingTests (decoding part) + LossyList: every contract fixture decodes. */
class DecodeTest {
    private fun fixture(name: String) = JSONObject(TestFixtures.read(name)!!)

    private val scanFixtures = listOf("blocked-92", "blocked-marked-safe", "blocked-verified-scam", "warning-41", "warning-63")

    @Test fun scanFixturesDecode() {
        for (name in scanFixtures) {
            val scan = ScanResult.fromJson(fixture(name))
            assertTrue(name, scan.score >= ScoreThreshold.firstWarning)
            assertTrue(name, scan.signals.isNotEmpty())
            assertEquals(name, if (scan.score >= ScoreThreshold.blocked) ScanStatus.BLOCKED else ScanStatus.WARNING, scan.status)
        }
    }

    @Test fun signalHostAndLabels() {
        val scan = ScanResult.fromJson(fixture("blocked-92"))
        assertEquals(Instant.parse("2026-10-21T04:05:00Z"), scan.detectedAt)
        val brand = scan.signals.first { it.id == "brand_plus_keyword" }
        assertEquals("bca.co.id", brand.host?.official)
        assertEquals("BCA", brand.host?.brand)
        assertNull(brand.host?.marks)
        assertEquals("Memakai nama BCA, tapi bukan BCA", brand.labelSimple.text("id"))
        assertEquals("pin", scan.signals.first { it.id == "asks_pin" }.evidence)
    }

    @Test fun verdicts() {
        assertEquals(Verdict.Value.SAFE, ScanResult.fromJson(fixture("blocked-marked-safe")).verdict!!.value)
        assertEquals(Verdict.Value.NOT_SAFE, ScanResult.fromJson(fixture("blocked-verified-scam")).verdict!!.value)
    }

    /** contracts/fixtures/activity-family.json is a `$ref` list: inlined in order it is a ScanPage of 5. */
    @Test fun activityFamilyDecodesAsScanPage() {
        val refs = fixture("activity-family").getJSONArray("items")
        val items = JSONArray()
        for (i in 0 until refs.length()) items.put(fixture(refs.getJSONObject(i).getString("\$ref").removeSuffix(".json")))
        val page = ScanPage.fromJson(JSONObject().put("items", items).put("nextCursor", JSONObject.NULL))
        assertEquals(5, page.items.size)
        assertNull(page.nextCursor)
    }

    @Test fun familyMembersDecode() {
        val members = FamilyMembersResponse.fromJson(fixture("family-members")).members
        assertEquals(listOf("dev_mom", "dev_dad"), members.map { it.deviceId })
        assertEquals(92, members[0].lastScan?.score)
        assertNull(members[1].lastScan)
        assertFalse(members[1].extensionActive)
    }

    @Test fun latestScamsDecode() {
        val items = LatestScamsPage.fromJson(fixture("latest-scams")).items
        assertEquals("phishing_bank", items[0].id)
        assertEquals("Bank phishing", items[0].title.text("en"))
        assertEquals("Phishing bank", items[0].title.text("id"))
    }

    @Test fun contractErrorBodyDecodes() {
        val body = APIErrorBody.fromJson(JSONObject("""{ "error": { "code": "code_expired", "message": "Code expired" } }"""))
        assertEquals(APIErrorCode.codeExpired, APIErrorCode(body.error.code))
    }

    @Test fun deviceProfileDecodesWithNullGuardian() {
        val json = """{ "deviceId": "d1", "name": "Mom", "avatarId": "avatar_03", "mode": "protected", "language": "id", "guardian": null }"""
        val profile = DeviceProfile.fromJson(JSONObject(json))
        assertEquals(UserMode.PROTECTED, profile.mode)
        assertNull(profile.guardian)
        assertNull(profile.stats)
    }

    // #493: a status or verdict this build does not know decodes to UNKNOWN.

    private fun scanJson(status: String, verdict: String? = null): JSONObject {
        val json = JSONObject(
            """{"id":"s493","url":"https://promo-shopee88.xyz/","domain":"promo-shopee88.xyz","score":70,"status":"$status",
             "signals":[],"ownerDeviceId":"dev_mom","ownerName":"Mom","detectedAt":"2026-10-21T04:05:00Z"}""",
        )
        if (verdict != null) {
            json.put(
                "verdict",
                JSONObject().put("value", verdict).put("byDeviceId", "dev_me").put("byName", "Virellia")
                    .put("decidedAt", "2026-10-21T05:00:00.123Z"),
            )
        }
        return json
    }

    @Test fun newWireValuesDecodeToUnknown() {
        val decoded = ScanResult.fromJson(scanJson("reviewing", "maybe"))
        assertEquals(ScanStatus.UNKNOWN, decoded.status)
        assertEquals(Verdict.Value.UNKNOWN, decoded.verdict?.value)
    }

    @Test fun unknownVerdictIsNotAKnownDecision() {
        assertNull(ScanResult.fromJson(scanJson("blocked", "maybe")).verdict?.known)
        val safe = ScanResult.fromJson(scanJson("blocked", "safe")).verdict!!
        assertEquals(safe, safe.known)
    }

    /** Row by row (#493): a broken row is left out, the rest and `nextCursor` stay. */
    @Test fun aBrokenRowIsLeftOut() {
        val broken = scanJson("warning").also { it.remove("ownerName") }
        val wrongType = scanJson("warning").put("score", "high")
        val page = ScanPage.fromJson(
            JSONObject()
                .put("items", JSONArray().put(scanJson("blocked")).put(broken).put(JSONObject.NULL).put(wrongType))
                .put("nextCursor", "20"),
        )
        assertEquals(1, page.items.size)
        assertEquals("20", page.nextCursor)
    }

    @Test fun aListThatIsNotAnArrayStillFails() {
        val failed = runCatching { ScanPage.fromJson(JSONObject().put("items", "nope")) }
        assertTrue(failed.isFailure)
    }

    @Test fun datesWithAndWithoutFractions() {
        assertEquals(Instant.parse("2026-10-21T04:05:00Z"), ShooJson.parseDate("2026-10-21T04:05:00Z"))
        assertEquals(Instant.parse("2026-10-21T04:05:00.123Z"), ShooJson.parseDate("2026-10-21T04:05:00.123Z"))
        assertEquals(Instant.parse("2026-10-21T04:05:00Z"), ShooJson.parseDate("2026-10-21T11:05:00+07:00"))
        assertEquals("2026-10-21T04:05:00Z", ShooJson.format(Instant.parse("2026-10-21T04:05:00.987Z")))
    }

    /** `PATCH /devices/me`: null fields are left out. */
    @Test fun deviceUpdateLeavesOutNulls() {
        val json = DeviceUpdate(language = "id", notifications = NotificationSettingsUpdate(quietHours = false)).toJson()
        assertEquals(setOf("language", "notifications"), json.keys().asSequence().toSet())
        assertEquals(false, json.getJSONObject("notifications").getBoolean("quietHours"))
        assertEquals(1, json.getJSONObject("notifications").length())
    }

    @Test fun loadFailureTellsServerFromConnection() {
        assertEquals(LoadFailure.SERVER, LoadFailure.from(RepositoryError.Decoding))
        assertEquals(LoadFailure.SERVER, LoadFailure.from(RepositoryError.Api(APIErrorCode.internal, "HTTP 502")))
        assertEquals(LoadFailure.CONNECTION, LoadFailure.from(RepositoryError.Network))
        assertEquals(LoadFailure.CONNECTION, LoadFailure.from(IllegalStateException()))
        assertEquals("Something went wrong. Try again.", LoadFailure.SERVER.message("Check your connection"))
    }
}
