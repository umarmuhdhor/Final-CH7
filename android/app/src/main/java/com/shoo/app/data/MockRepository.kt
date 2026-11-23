package com.shoo.app.data

import android.content.res.AssetManager
import com.shoo.app.app.AppConfig
import com.shoo.app.app.DeepLink
import com.shoo.app.support.Log
import java.net.URI
import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlin.random.Random
import kotlinx.coroutines.delay
import org.json.JSONArray
import org.json.JSONObject

/**
 * `ShooRepository` backed by contracts/fixtures (copied into the APK's `assets/fixtures` at build time). Used for
 * previews, tests, the demo and Debug builds.
 *
 * Magic join codes trigger the contract errors so screens can show them:
 * `000000` code_invalid · `999999` code_expired · `888888` family_full · `777777` too_many_attempts ·
 * `555555` rate_limited · `666666` already_connected.
 *
 * iOS: an `actor`. Here every read and write of the state happens under one lock, never across a suspension.
 */
class MockRepository(
    mode: UserMode = UserMode.GUARDIAN,
    val scenario: Scenario = Scenario.STANDARD,
    /** Milliseconds each call waits (iOS `latency`, 300 ms). */
    val latencyMillis: Long = 300,
    val pageSize: Int = Companion.pageSize,
    /** Reads a fixture by name without `.json` (`activity-family`); null when missing. See [assetFixtures]. */
    private val fixtures: (String) -> String?,
    /** `-debug.replicaFixture YES`: Detail of a scan with a screenshot gets a page copy link. The contract fixtures
     * have `pageReplicaUrl: null`, so previews and the UI gate need this to show a copy. */
    val pageCopies: Boolean = false,
    /** See `failIfAsked`. */
    val failures: Map<String, RepositoryError> = emptyMap(),
    private val now: () -> Instant = Instant::now,
) : ShooRepository {
    enum class Scenario(val rawValue: String) {
        /** Fixture data as in contracts/fixtures. */
        STANDARD("standard"),
        /** No scans, no members — for empty states. */
        EMPTY("empty"),
        /** Like `EMPTY`, and a Protected phone has no guardian yet: joining a family works (Figma "Berhasil Terhubung"). */
        UNPAIRED("unpaired"),
        /** Fixture data with only the first member (UI gate GD-03: 1 person). */
        ONE_MEMBER("oneMember"),
        /** Fixture data plus a third, connected member without risky sites (UI gate GD-03: 3 people). */
        THREE_MEMBERS("threeMembers"),
        // Figma parity QA (`MockScenarios`): the content the Figma frames show, and variants of it.
        FIGMA("figma"),
        MIXED_VERDICTS("mixedVerdicts"),
        HEAVY("heavy"),
        EDGE("edge"),
        ALL_SAFE("allSafe"),
        ALL_BLOCKED("allBlocked"),
        /** Imelda's eval corpus with the detector's real results (`corpus-scans.json`). */
        CORPUS("corpus"),
        /** DT-04 (#497): one scan whose address reasons carry `host.marks`, `official` and `brand`. */
        ADDRESS_MARKS("addressMarks"),
        // Home parity QA (`MockScenarios.home`): one state per Figma HOME frame (Pribadi, protected/Home).
        HOME_PRIBADI("homePribadi"),
        HOME_PRIBADI_ALONE("homePribadiAlone"),
        PROTECTED_QUIET("protectedQuiet"),
        PROTECTED_BLOCKED("protectedBlocked"),
        PROTECTED_BLOCKED_SCAM("protectedBlockedScam"),
        PROTECTED_BLOCKED_SAFE("protectedBlockedSafe"),
        PROTECTED_WARNING("protectedWarning"),
        PROTECTED_WARNING_SCAM("protectedWarningScam"),
        PROTECTED_WARNING_SAFE("protectedWarningSafe"),
        PROTECTED_ALONE("protectedAlone");

        /** Draws the Figma "Scam Terbaru" cards on Home. */
        val hasScamCases: Boolean
            get() = when (this) {
                STANDARD, EMPTY, UNPAIRED, ONE_MEMBER, THREE_MEMBERS, MIXED_VERDICTS, HEAVY, EDGE, ALL_SAFE,
                ALL_BLOCKED, CORPUS, ADDRESS_MARKS -> false
                FIGMA, HOME_PRIBADI, HOME_PRIBADI_ALONE, PROTECTED_QUIET, PROTECTED_BLOCKED, PROTECTED_BLOCKED_SCAM,
                PROTECTED_BLOCKED_SAFE, PROTECTED_WARNING, PROTECTED_WARNING_SCAM, PROTECTED_WARNING_SAFE, PROTECTED_ALONE -> true
            }

        companion object {
            fun from(raw: String?): Scenario? = entries.firstOrNull { it.rawValue == raw }
        }
    }

    private val lock = Any()
    private var profile: DeviceProfile
    private var allScans: MutableList<ScanResult>
    private var members: MutableList<FamilyMember>
    /** The guardian's active code, handed out again while more than 5 min is left. */
    private var familyCode: FamilyCode? = null
    private val callCounts = mutableMapOf<String, Int>()

    /** The `notes` of the last `setVerdict` (tests and the debug flow; the server never returns them). */
    var lastVerdictNotes: String? = null
        private set

    init {
        val dataset = MockScenarios.dataset(scenario, now(), fixtures)
        profile = if (dataset != null) {
            if (mode == UserMode.GUARDIAN) dataset.guardian else dataset.protected
        } else {
            if (mode == UserMode.GUARDIAN) guardianProfile else protectedProfile
        }
        when (scenario) {
            Scenario.STANDARD, Scenario.ONE_MEMBER, Scenario.THREE_MEMBERS -> {
                allScans = (load("activity-family", { ScanPage.fromJson(it) })?.items ?: emptyList()).toMutableList()
                val fixture = load("family-members", { FamilyMembersResponse.fromJson(it) })?.members ?: emptyList()
                members = when (scenario) {
                    Scenario.ONE_MEMBER -> fixture.take(1).map { withDetails(it) }
                    Scenario.THREE_MEMBERS -> (fixture + extraMember).map { withDetails(it) }
                    else -> fixture.map { withDetails(it) }
                }.toMutableList()
            }
            Scenario.EMPTY, Scenario.UNPAIRED -> {
                allScans = mutableListOf()
                members = mutableListOf()
            }
            else -> {
                allScans = (dataset?.scans ?: emptyList()).toMutableList()
                members = (dataset?.members ?: emptyList()).toMutableList()
            }
        }
        if (scenario == Scenario.UNPAIRED) profile = profile.copy(guardian = null)
    }

    // MARK: Devices

    override suspend fun registerDevice(name: String, mode: UserMode, avatarId: String?, apnsToken: String?): DeviceRegistration {
        pause()
        return synchronized(lock) {
            failIfAsked("registerDevice")
            val trimmed = name.trim()
            if (trimmed.length !in 1..20) throw RepositoryError.Api(APIErrorCode.invalidBody, "name must be 1–20 characters")
            // Same rule as the server (contracts/api.md, #120): a known id is kept, anything else is random.
            val avatar = avatarId?.takeIf { it in avatarIds } ?: "avatar_%02d".format(Random.nextInt(1, 13))
            profile = DeviceProfile(
                deviceId = if (mode == UserMode.GUARDIAN) guardianProfile.deviceId else protectedProfile.deviceId,
                name = trimmed, avatarId = avatar, mode = mode, language = profile.language,
                guardian = if (mode == UserMode.GUARDIAN) null else profile.guardian,
            )
            DeviceRegistration(deviceId = profile.deviceId, token = "mock-${UUID.randomUUID()}", avatarId = avatar)
        }
    }

    override suspend fun latestScams(): List<ScamCase> =
        if (scenario.hasScamCases) MockScenarios.scamCases(now()) else emptyList()

    override suspend fun me(): DeviceProfile {
        pause()
        return synchronized(lock) {
            failIfAsked("me")
            profile
        }
    }

    override suspend fun updateMe(update: DeviceUpdate) {
        pause()
        synchronized(lock) {
            failIfAsked("updateMe")
            // Validate everything first: a rejected update changes nothing.
            val trimmed = update.name?.trim()
            if (trimmed != null && trimmed.length !in 1..20) {
                throw RepositoryError.Api(APIErrorCode.invalidBody, "name must be 1–20 characters")
            }
            if (update.language != null && update.language !in listOf("en", "id")) {
                throw RepositoryError.Api(APIErrorCode.invalidBody, "language must be en or id")
            }
            if (update.avatarId != null && update.avatarId !in avatarIds) {
                throw RepositoryError.Api(APIErrorCode.invalidBody, "avatarId must be avatar_01…avatar_12")
            }
            var p = profile
            if (trimmed != null) p = p.copy(name = trimmed)
            update.language?.let { p = p.copy(language = it) }
            update.avatarId?.let { p = p.copy(avatarId = it) }
            update.timeZone?.let { p = p.copy(timeZone = it) }
            update.notifications?.let { p = p.copy(notifications = (p.notifications ?: NotificationSettings.defaults).applying(it)) }
            profile = p
        }
    }

    // MARK: Family

    override suspend fun createFamilyCode(refresh: Boolean): FamilyCode {
        pause()
        return synchronized(lock) {
            failIfAsked("createFamilyCode")
            require(UserMode.GUARDIAN)
            // Same code while more than 5 min is left, like the server (contracts/api.md).
            val current = familyCode
            if (!refresh && current != null &&
                Duration.between(now(), current.expiresAt).toMillis() > ApiRepository.codeReuseSeconds * 1000
            ) {
                return@synchronized current
            }
            val code = "%06d".format(Random.nextInt(100_000, 600_000))
            val fresh = FamilyCode(
                code = code,
                expiresAt = now().plusSeconds(ApiRepository.codeLifetimeSeconds),
                inviteUrl = "${AppConfig.publicBaseURL}/j/$code",
            )
            familyCode = fresh
            fresh
        }
    }

    override suspend fun joinFamily(code: String): GuardianInfo {
        pause()
        return synchronized(lock) {
            failIfAsked("joinFamily")
            require(UserMode.PROTECTED)
            when (code) {
                "000000" -> throw RepositoryError.Api(APIErrorCode.codeInvalid, "No family uses this code")
                "999999" -> throw RepositoryError.Api(APIErrorCode.codeExpired, "Code expired")
                "888888" -> throw RepositoryError.Api(APIErrorCode.familyFull, "Guardian already has 3 members")
                // The backend sends `Retry-After` with both 429s (contracts/api.md): the Connect countdown.
                "777777" -> throw RepositoryError.Throttled(APIErrorCode.tooManyAttempts, "Too many attempts", 299.0)
                // Really from `POST /devices` in onboarding; here so "Coba lagi dalam 59 menit" can be staged.
                "555555" -> throw RepositoryError.Throttled(APIErrorCode.rateLimited, "Too many requests", 3599.0)
                "666666" -> throw RepositoryError.Api(APIErrorCode.alreadyConnected, "Already connected")
            }
            if (!DeepLink.isCode(code)) throw RepositoryError.Api(APIErrorCode.codeInvalid, "Code must be 6 digits")
            if (profile.guardian != null) throw RepositoryError.Api(APIErrorCode.alreadyConnected, "Already connected")
            val guardian = fixtureGuardian
            profile = profile.copy(guardian = guardian)
            guardian
        }
    }

    override suspend fun becomeProtected(code: String): ProtectedSwitch {
        pause()
        return synchronized(lock) {
            failIfAsked("becomeProtected")
            require(UserMode.GUARDIAN)
            if (members.isNotEmpty()) throw RepositoryError.Api(APIErrorCode.hasMembers, "Disconnect the people you protect first")
            when (code) {
                "000000" -> throw RepositoryError.Api(APIErrorCode.codeInvalid, "No family uses this code")
                "999999" -> throw RepositoryError.Api(APIErrorCode.codeExpired, "Code expired")
                "888888" -> throw RepositoryError.Api(APIErrorCode.familyFull, "Guardian already has 3 members")
            }
            if (!DeepLink.isCode(code)) throw RepositoryError.Api(APIErrorCode.codeInvalid, "Code must be 6 digits")
            profile = profile.copy(deviceId = protectedProfile.deviceId, mode = UserMode.PROTECTED, guardian = otherGuardian)
            ProtectedSwitch(
                deviceId = profile.deviceId, token = "mock-${UUID.randomUUID()}", avatarId = profile.avatarId,
                guardian = otherGuardian,
            )
        }
    }

    override suspend fun familyMembers(): List<FamilyMember> {
        pause()
        return synchronized(lock) {
            failIfAsked("familyMembers")
            require(UserMode.GUARDIAN)
            members.toList()
        }
    }

    override suspend fun removeMember(deviceId: String) {
        pause()
        synchronized(lock) {
            failIfAsked("removeMember")
            require(UserMode.GUARDIAN)
            if (members.none { it.deviceId == deviceId }) throw RepositoryError.Api(APIErrorCode.notFound, "Not your member")
            members.removeAll { it.deviceId == deviceId }
        }
    }

    override suspend fun deleteMe() {
        pause()
        synchronized(lock) {
            failIfAsked("deleteMe")
            val me = profile.deviceId
            allScans.removeAll { it.ownerDeviceId == me }
            members.clear()
            profile = profile.copy(guardian = null)
        }
    }

    override suspend fun setMemberNotify(deviceId: String, notify: Boolean) {
        pause()
        synchronized(lock) {
            failIfAsked("setMemberNotify")
            require(UserMode.GUARDIAN)
            val index = members.indexOfFirst { it.deviceId == deviceId }
            if (index < 0) throw RepositoryError.Api(APIErrorCode.notFound, "Not your member")
            members[index] = members[index].copy(notify = notify)
        }
    }

    override suspend fun remindMember(deviceId: String) {
        pause()
        synchronized(lock) {
            failIfAsked("remindMember")
            require(UserMode.GUARDIAN)
            val index = members.indexOfFirst { it.deviceId == deviceId }
            if (index < 0) throw RepositoryError.Api(APIErrorCode.notFound, "Not your member")
            val last = members[index].remindedAt
            if (last != null && Duration.between(last, now()).seconds < 6 * 3600) {
                throw RepositoryError.Api(APIErrorCode.remindTooSoon, "Already reminded recently")
            }
            members[index] = members[index].copy(remindedAt = now())
        }
    }

    override suspend fun leaveGuardian() {
        pause()
        synchronized(lock) {
            failIfAsked("leaveGuardian")
            require(UserMode.PROTECTED)
            if (profile.guardian == null) throw RepositoryError.Api(APIErrorCode.notFound, "No guardian")
            profile = profile.copy(guardian = null)
        }
    }

    // MARK: Scans

    override suspend fun scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?): ScanPage {
        pause()
        return synchronized(lock) {
            failIfAsked("scans")
            val owners = visibleOwners(owner)
            val matching = allScans
                .filter { it.ownerDeviceId in owners && (status == null || it.status == status) }
                // Tie-break on id so the index cursor never skips or repeats an item.
                .sortedWith(compareByDescending<ScanResult> { it.detectedAt }.thenByDescending { it.id })
            val start = cursor?.toIntOrNull() ?: 0
            if (start < 0 || start > matching.size) throw RepositoryError.Api(APIErrorCode.invalidBody, "Bad cursor")
            val end = minOf(start + pageSize, matching.size)
            // Lists never carry a screenshot URL (contracts/api.md).
            val items = matching.subList(start, end).map { it.copy(screenshotUrl = null) }
            ScanPage(items = items, nextCursor = if (end < matching.size) end.toString() else null)
        }
    }

    /** Adds a scan as if a device had just sent it (tests: rows the scenarios don't have). */
    fun insertScan(scan: ScanResult) {
        synchronized(lock) { allScans.add(scan) }
    }

    override suspend fun scan(id: String): ScanResult {
        pause()
        return synchronized(lock) {
            failIfAsked("scan")
            val scan = allScans.firstOrNull { it.id == id }
            val filter = if (profile.mode == UserMode.GUARDIAN) ScanOwnerFilter.Family else ScanOwnerFilter.Me
            if (scan == null || scan.ownerDeviceId !in visibleOwners(filter)) {
                throw RepositoryError.Api(APIErrorCode.notFound, "Scan not found")
            }
            if (!pageCopies || scan.screenshotUrl == null) scan else scan.copy(pageReplicaUrl = fixtureReplicaURL(scan.id))
        }
    }

    override suspend fun setVerdict(scanId: String, value: Verdict.Value, notes: String?): Verdict {
        val verdict = setVerdict(scanId, value)
        synchronized(lock) { lastVerdictNotes = notes }
        return verdict
    }

    override suspend fun setVerdict(scanId: String, value: Verdict.Value): Verdict {
        synchronized(lock) { lastVerdictNotes = null }
        pause()
        return synchronized(lock) {
            failIfAsked("setVerdict")
            if (profile.mode != UserMode.GUARDIAN) {
                throw RepositoryError.Api(APIErrorCode.verdictNotAllowed, "Only the guardian decides")
            }
            val scan = allScans.firstOrNull { it.id == scanId }
            if (scan == null || scan.ownerDeviceId !in visibleOwners(ScanOwnerFilter.Family)) {
                throw RepositoryError.Api(APIErrorCode.notFound, "Scan not found")
            }
            // GD-07: warning and blocked alike (Figma 416:9469, backend #191); a new verdict replaces the old.
            val verdict = Verdict(value = value, byDeviceId = profile.deviceId, byName = profile.name, decidedAt = now())
            // A verdict applies to the scan's link for that owner (contracts/api.md "Verdicts (per link)", #241).
            val link = link(scan.url)
            for (index in allScans.indices) {
                if (link(allScans[index].url) == link && allScans[index].ownerDeviceId == scan.ownerDeviceId) {
                    allScans[index] = allScans[index].copy(verdict = verdict)
                }
            }
            // `setVerdict.lost`: saved, but the answer never arrives (a timeout). A-02 stages the 409 after it with
            // `-mock.fail setVerdict.lost,setVerdict~1=verdict_locked`.
            failIfAsked("setVerdict.lost")
            verdict
        }
    }

    // MARK: Helpers

    private fun visibleOwners(filter: ScanOwnerFilter): Set<String> {
        val me = profile.deviceId
        // Only current members: a removed member's scans are gone from the guardian's view.
        val family = setOf(me) + members.map { it.deviceId }
        return when (filter) {
            ScanOwnerFilter.Me -> setOf(me)
            ScanOwnerFilter.Family -> {
                if (profile.mode != UserMode.GUARDIAN) throw RepositoryError.Api(APIErrorCode.forbidden, "Guardian only")
                family
            }
            is ScanOwnerFilter.Device -> {
                if (profile.mode != UserMode.GUARDIAN || filter.id !in family) {
                    throw RepositoryError.Api(APIErrorCode.notFound, "Unknown device")
                }
                setOf(filter.id)
            }
        }
    }

    private fun require(mode: UserMode) {
        if (profile.mode != mode) throw RepositoryError.Api(APIErrorCode.forbidden, "Wrong mode")
    }

    /**
     * Debug: `-mock.fail me,scans,setVerdict=verdict_not_allowed` makes those calls fail (no value = no connection;
     * `name=code` = that contract error), to stage the error states. `name~N` lets the first N calls through
     * (`scans~1`: Activity loads, then its refresh fails). `setVerdict.lost` fails after the verdict was saved, like
     * an answer lost to a timeout.
     */
    private fun failIfAsked(name: String) {
        val call = (callCounts[name] ?: 0) + 1
        callCounts[name] = call
        failures[name]?.let { throw it }
        for ((key, failure) in failures) {
            if (!key.startsWith("$name~")) continue
            val skip = key.substring(name.length + 1).toIntOrNull()
            if (skip != null && call > skip) throw failure
        }
    }

    private suspend fun pause() {
        if (latencyMillis > 0) delay(latencyMillis)
    }

    private fun <T> load(name: String, decode: (JSONObject) -> T): T? {
        val text = fixtures(name)
        if (text == null) {
            Log.data.error("Missing fixture", name)
            return null
        }
        return try {
            decode(inlineRefs(parseObject(text)))
        } catch (_: Exception) {
            Log.data.error("Bad fixture", name)
            null
        }
    }

    /** contracts/fixtures/activity-family.json lists `{ "$ref": "blocked-92.json" }`: each one is that file's content
     * (iOS keeps an inlined copy of the file instead). */
    private fun inlineRefs(json: JSONObject): JSONObject {
        val items = json.optJSONArray("items") ?: return json
        val inlined = JSONArray()
        for (index in 0 until items.length()) {
            val item = items.opt(index)
            val ref = (item as? JSONObject)?.optString("\$ref")?.takeIf { it.isNotEmpty() }
            val text = ref?.let { fixtures(it.removeSuffix(".json")) }
            inlined.put(if (text != null) parseObject(text) else item)
        }
        return JSONObject(json.toString()).put("items", inlined)
    }

    companion object {
        const val pageSize = 20

        /** The ids `AvatarCatalog` knows (`avatar_01…12`, contracts/api.md #120). */
        val avatarIds: List<String> = (1..12).map { "avatar_%02d".format(it) }

        /** Not in contracts/fixtures: only the 3-member UI gate uses it. */
        val extraMember = FamilyMember(
            deviceId = "dev_grandma", name = "Grandma", avatarId = "avatar_05", extensionActive = true, lastScan = null,
        )

        /** Fixture identities. `dev_me` is the guardian in contracts/fixtures (verdicts "by Adhella"). */
        val guardianProfile = DeviceProfile(
            deviceId = "dev_me", name = "Adhella", avatarId = "avatar_01", mode = UserMode.GUARDIAN, language = "en",
            guardian = null, stats = ProfileStats(blocked = 3, warnings = 5, since = Instant.ofEpochSecond(1_789_351_800)),
            timeZone = "Asia/Jakarta", notifications = NotificationSettings.defaults,
        )
        val fixtureGuardian = GuardianInfo(deviceId = "dev_me", name = "Adhella", avatarId = "avatar_01")
        val protectedProfile = DeviceProfile(
            deviceId = "dev_mom", name = "Mom", avatarId = "avatar_03", mode = UserMode.PROTECTED, language = "en",
            guardian = fixtureGuardian,
            stats = ProfileStats(blocked = 3, warnings = 1, since = Instant.ofEpochSecond(1_789_351_800)),
            timeZone = "Asia/Jakarta", notifications = NotificationSettings.defaults,
        )

        /** Another family's guardian, for "Punya kode undangan?". */
        val otherGuardian = GuardianInfo(deviceId = "dev_budi", name = "Budi", avatarId = "avatar_04")

        /** PF-01 member detail fields (proposed, not in contracts/fixtures): added to the fixture members by id. */
        fun withDetails(member: FamilyMember): FamilyMember {
            val base = member.copy(connectedAt = Instant.ofEpochSecond(1_789_351_800), notify = true) // 14 Sep 2026
            return when (base.deviceId) {
                "dev_mom" -> base.copy(
                    lastSeenAt = Instant.ofEpochSecond(1_793_073_480), deviceModel = "iPhone 15", osVersion = "26",
                    stats = FamilyMember.Stats(blocked = 3, warnings = 5),
                )
                "dev_dad" -> base.copy(
                    lastSeenAt = Instant.ofEpochSecond(1_792_900_000), deviceModel = "iPad", osVersion = "26",
                    stats = FamilyMember.Stats(blocked = 1, warnings = 0),
                )
                else -> base.copy(stats = FamilyMember.Stats(blocked = 0, warnings = 0))
            }
        }

        /** Link the Detail screen gets for a fixture page copy; `example.invalid` never resolves. */
        fun fixtureReplicaURL(scanId: String): String = "https://example.invalid/replicas/$scanId"

        /** The backend's link (`verdict_link`, #241) kept simple: origin + path, without query or fragment. */
        fun link(url: String): String {
            val uri = try {
                URI(url)
            } catch (_: Exception) {
                return url
            }
            val scheme = uri.scheme?.lowercase() ?: "https"
            val host = uri.host?.lowercase() ?: ""
            val port = if (uri.port >= 0) ":${uri.port}" else ""
            val path = uri.path.takeUnless { it.isNullOrEmpty() } ?: "/"
            return "$scheme://$host$port$path"
        }

        /** Parses `-mock.fail`. Every entry is `name` or `name=api_error_code`. */
        fun failures(argument: String?): Map<String, RepositoryError> {
            if (argument == null) return emptyMap()
            val result = mutableMapOf<String, RepositoryError>()
            for (entry in argument.split(",")) {
                val parts = entry.split("=", limit = 2)
                val name = parts.first()
                if (name.isEmpty()) continue
                result[name] = if (parts.size > 1) RepositoryError.Api(APIErrorCode(parts[1]), parts[1]) else RepositoryError.Network
            }
            return result
        }

        /** Fixtures from the APK: `assets/fixtures/<name>.json` (contracts/fixtures, copied by the build). */
        fun assetFixtures(assets: AssetManager): (String) -> String? = { name ->
            try {
                assets.open("fixtures/$name.json").bufferedReader().use { it.readText() }
            } catch (_: Exception) {
                null
            }
        }
    }
}
