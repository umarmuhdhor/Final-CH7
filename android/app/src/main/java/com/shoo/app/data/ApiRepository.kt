package com.shoo.app.data

import java.time.Duration
import java.time.Instant
import org.json.JSONObject

/**
 * `ShooRepository` against the real backend (contracts/api.md). Keeps `SessionStore` in step with the server, so
 * the add-on gets the same name and guardian as the app (contracts/app-group-keys.md).
 */
class ApiRepository(
    private val client: ApiClient,
    private val session: SessionStore,
    private val now: () -> Instant = Instant::now,
) : ShooRepository {
    /**
     * The last family code, in memory only, for the device that got it. Home, Profile and onboarding each open
     * their own code screen; they share this one instead of each asking the server, which allows 6 asks a minute
     * (contracts/api.md). `fetchedAt` and `endsAt` are on the phone's clock (issue #227): the server's `expiresAt`
     * is only trusted for how long is left, at most 30 min.
     */
    private val lock = Any()
    private var lastCode: CachedCode? = null

    // MARK: Devices

    override suspend fun registerDevice(name: String, mode: UserMode, avatarId: String?, apnsToken: String?): DeviceRegistration {
        val body = JSONObject().put("name", name).put("mode", mode.rawValue)
        avatarId?.let { body.put("avatarId", it) }
        apnsToken?.let { body.put("apnsToken", it) }
        // The caller saves the session (`AppEnvironment.register`): it knows the name and mode chosen.
        return client.send(
            ApiClient.Request(ApiClient.Method.POST, listOf("devices"), body = body, authorized = false),
            { DeviceRegistration.fromJson(it) },
        )
    }

    override suspend fun me(): DeviceProfile {
        val usedToken = session.token
        val profile = client.send(ApiClient.Request(ApiClient.Method.GET, listOf("devices", "me")), { DeviceProfile.fromJson(it) })
        // Written only while the token is still the one this request used: when "Punya kode undangan?" saved a new
        // device meanwhile (fase 27h, F-A12), this is the old device's profile and the App Group keeps the new name
        // and guardian. No token (cleared) = nothing to write for. `guardian: null` = never joined, left, or removed by
        // the guardian (D-alief-21).
        if (usedToken != null) {
            session.applyProfile(
                name = profile.name, avatarId = profile.avatarId,
                guardian = if (profile.mode == UserMode.PROTECTED) profile.guardian else null, ifToken = usedToken,
            )
        }
        return profile
    }

    override suspend fun updateMe(update: DeviceUpdate) {
        client.send(ApiClient.Request(ApiClient.Method.PATCH, listOf("devices", "me"), body = update.toJson()), { OkResponse.fromJson(it) })
        update.name?.let(session::updateName)
        update.avatarId?.let(session::updateAvatar)
    }

    override suspend fun becomeProtected(code: String): ProtectedSwitch {
        // The caller saves the new session (`AppEnvironment.becomeProtected`), then the guardian.
        synchronized(lock) { lastCode = null }
        return client.send(
            ApiClient.Request(ApiClient.Method.POST, listOf("devices", "me", "protected"), body = JSONObject().put("code", code)),
            { ProtectedSwitch.fromJson(it) },
        )
    }

    override suspend fun deleteMe() {
        synchronized(lock) { lastCode = null }
        try {
            client.send(
                ApiClient.Request(ApiClient.Method.DELETE, listOf("devices", "me"), reportsUnauthorized = false),
                { OkResponse.fromJson(it) },
            )
        } catch (error: RepositoryError) {
            // Already gone (an earlier answer got lost): the session goes too, then the caller decides.
            if (error.apiCode == APIErrorCode.notFound || error.apiCode == APIErrorCode.unauthorized) session.clear()
            throw error
        }
        session.clear()
    }

    // MARK: Family

    override suspend fun createFamilyCode(refresh: Boolean): FamilyCode {
        val deviceId = session.deviceId
        // The server would hand back this same code while more than 5 min is left (contracts/api.md).
        if (!refresh && deviceId != null) {
            val cached = synchronized(lock) { lastCode }
            if (cached != null && cached.deviceId == deviceId && cached.isReusable(now())) return cached.code
        }
        // No body for the usual case (allowed by the contract): the server hands out the active code.
        val code = client.send(
            ApiClient.Request(
                ApiClient.Method.POST, listOf("family", "code"),
                body = if (refresh) JSONObject().put("refresh", true) else null,
            ),
            { FamilyCode.fromJson(it) },
        )
        val cached = deviceId?.let { CachedCode(it, code, now()) }
        synchronized(lock) { lastCode = cached }
        return code
    }

    data class CachedCode(val deviceId: String, val code: FamilyCode, val fetchedAt: Instant) {
        /** `fetchedAt` + what the server says is left, clamped to 0…30 min: a phone clock behind the server's never
         * stretches it, one ahead makes it 0 (asks the server again). */
        val endsAt: Instant
            get() {
                val left = Duration.between(fetchedAt, code.expiresAt).toMillis().coerceIn(0, codeLifetimeSeconds * 1000)
                return fetchedAt.plusMillis(left)
            }

        /** More than 5 min left, and the clock was not set back since the code came. */
        fun isReusable(now: Instant): Boolean =
            !now.isBefore(fetchedAt) && Duration.between(now, endsAt).toMillis() > codeReuseSeconds * 1000
    }

    override suspend fun joinFamily(code: String): GuardianInfo {
        val response = client.send(
            ApiClient.Request(ApiClient.Method.POST, listOf("family", "join"), body = JSONObject().put("code", code)),
            { JoinResponse.fromJson(it) },
        )
        session.setGuardian(response.guardian)
        return response.guardian
    }

    override suspend fun familyMembers(): List<FamilyMember> =
        client.send(ApiClient.Request(ApiClient.Method.GET, listOf("family", "members")), { FamilyMembersResponse.fromJson(it) }).members

    override suspend fun removeMember(deviceId: String) {
        // P13: their icons go from memory whatever the answer (a failed call only costs a download).
        try {
            client.send(ApiClient.Request(ApiClient.Method.DELETE, listOf("family", "members", deviceId)), { OkResponse.fromJson(it) })
        } finally {
            session.forgetCachedData()
        }
    }

    override suspend fun setMemberNotify(deviceId: String, notify: Boolean) {
        client.send(
            ApiClient.Request(
                ApiClient.Method.PATCH, listOf("family", "members", deviceId), body = JSONObject().put("notify", notify),
            ),
            { OkResponse.fromJson(it) },
        )
    }

    override suspend fun remindMember(deviceId: String) {
        client.send(ApiClient.Request(ApiClient.Method.POST, listOf("family", "members", deviceId, "remind")), { OkResponse.fromJson(it) })
    }

    override suspend fun leaveGuardian() {
        try {
            client.send(ApiClient.Request(ApiClient.Method.DELETE, listOf("family", "guardian")), { OkResponse.fromJson(it) })
        } catch (error: RepositoryError) {
            // No guardian on the server any more: forget the name here too.
            if (error.apiCode == APIErrorCode.notFound) session.setGuardian(null)
            throw error
        }
        session.setGuardian(null)
    }

    // MARK: Scans

    override suspend fun scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?): ScanPage {
        val query = buildList {
            add("owner" to owner.queryValue)
            status?.let { add("status" to it.rawValue) }
            cursor?.let { add("cursor" to it) }
        }
        return client.send(ApiClient.Request(ApiClient.Method.GET, listOf("scans"), query = query), { ScanPage.fromJson(it) })
    }

    override suspend fun scan(id: String): ScanResult =
        client.send(ApiClient.Request(ApiClient.Method.GET, listOf("scans", id)), { ScanResult.fromJson(it) })

    override suspend fun latestScams(): List<ScamCase> =
        client.send(ApiClient.Request(ApiClient.Method.GET, listOf("scams", "latest")), { LatestScamsPage.fromJson(it) }).items

    override suspend fun setVerdict(scanId: String, value: Verdict.Value): Verdict = setVerdict(scanId, value, null)

    override suspend fun setVerdict(scanId: String, value: Verdict.Value, notes: String?): Verdict {
        // #493: `UNKNOWN` only comes from the server; `POST /verdicts` takes `safe` / `not_safe` only.
        if (value == Verdict.Value.UNKNOWN) {
            throw RepositoryError.Api(APIErrorCode.invalidBody, "A verdict must be safe or not_safe")
        }
        val trimmed = notes?.trim()
        val body = JSONObject().put("scanId", scanId).put("value", value.rawValue)
        // Left out when empty, as older builds send it.
        if (!trimmed.isNullOrEmpty()) body.put("notes", trimmed)
        return client.send(ApiClient.Request(ApiClient.Method.POST, listOf("verdicts"), body = body), { VerdictResponse.fromJson(it) }).verdict
    }

    companion object {
        /** Same as the server's `REUSE_MIN_SECONDS` (checked by backend/api/test/family-code-sync.test.ts). */
        const val codeReuseSeconds: Long = 5 * 60

        /**
         * How long a family code lives (contracts/api.md: 30 min). iOS: `FamilyCodeModel.codeLifetime`; kept here so
         * `data/` and `app/` don't depend on a feature screen. `FamilyCodeModel` should use this value.
         */
        const val codeLifetimeSeconds: Long = 30 * 60
    }
}
