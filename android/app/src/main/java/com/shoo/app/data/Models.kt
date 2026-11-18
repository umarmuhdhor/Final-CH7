package com.shoo.app.data

import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import org.json.JSONArray
import org.json.JSONObject

// Shapes from contracts/ (api.md, scan-result.schema.json). iOS: ShooShared/ScanResult.swift + Data/Models.swift.
// Decoding is strict like Swift's `Codable`: a missing required field or a wrong type throws `DecodingException`;
// lists use `LossyList`, so one bad row is left out instead of failing the whole answer (#493).
// URLs are kept as `String` (iOS `URL`); dates are `Instant`.

// MARK: ScanResult (ShooShared/ScanResult.swift)

/** Mirrors contracts/scan-result.schema.json. Change the contract first, then this file. */
data class ScanResult(
    val id: String,
    val url: String,
    val domain: String,
    val pageTitle: String? = null,
    val faviconUrl: String? = null,
    val score: Int,
    val status: ScanStatus,
    val signals: List<Signal>,
    val screenshotUrl: String? = null,
    val pageReplicaUrl: String? = null,
    val ownerDeviceId: String,
    val ownerName: String,
    val detectedAt: Instant,
    val verdict: Verdict? = null,
) {
    companion object {
        fun fromJson(json: JSONObject): ScanResult = ScanResult(
            id = json.string("id"),
            url = json.string("url"),
            domain = json.string("domain"),
            pageTitle = json.stringOrNull("pageTitle"),
            faviconUrl = json.stringOrNull("faviconUrl"),
            score = json.int("score"),
            status = ScanStatus.from(json.string("status")),
            signals = json.array("signals").let { array ->
                // Not lossy, like Swift `[Signal]`: a broken signal makes the scan undecodable.
                (0 until array.length()).map { Signal.fromJson(array.objectAt(it)) }
            },
            screenshotUrl = json.stringOrNull("screenshotUrl"),
            pageReplicaUrl = json.stringOrNull("pageReplicaUrl"),
            ownerDeviceId = json.string("ownerDeviceId"),
            ownerName = json.string("ownerName"),
            detectedAt = json.instant("detectedAt"),
            verdict = json.objOrNull("verdict")?.let { Verdict.fromJson(it) },
        )
    }
}

/**
 * `UNKNOWN` = a status this build does not know (a newer backend, #493). Decoding never throws on a new
 * string, so one new value can't make a whole list fail; show it as "unknown status", don't drop the row.
 */
enum class ScanStatus(val rawValue: String) {
    WARNING("warning"),
    BLOCKED("blocked"),
    UNKNOWN("unknown");

    companion object {
        fun from(raw: String): ScanStatus = entries.firstOrNull { it.rawValue == raw } ?: UNKNOWN
    }
}

data class Signal(
    val id: String,
    val layer: Int,
    val weight: Int,
    val label: LocalizedText,
    val labelSimple: LocalizedText,
    val evidence: String? = null,
    /** Layer 1–2 address signals only (#497, DT-04 address card). null = mark the whole domain. */
    val host: Host? = null,
) {
    /** contracts/scan-result.schema.json#/$defs/SignalHost, rules in contracts/detector-interface.md "host". */
    data class Host(
        /** Substrings of `ScanResult.domain` to highlight, as written there (lowercase, punycode), max 4, in reading
         * order. null = no precise part. Ignore a mark not found in the domain. */
        val marks: List<String>? = null,
        /** The brand's real domain (e.g. "bca.co.id"), only on `lookalike_domain` and `brand_plus_keyword`. */
        val official: String? = null,
        /** The brand's display name (e.g. "BCA"), sent with `official`. Detail's "Ringkasan" names it (DT-04). */
        val brand: String? = null,
    ) {
        companion object {
            fun fromJson(json: JSONObject): Host = Host(
                marks = json.arrayOrNull("marks")?.let { array -> (0 until array.length()).map { array.stringAt(it) } },
                official = json.stringOrNull("official"),
                brand = json.stringOrNull("brand"),
            )
        }
    }

    companion object {
        fun fromJson(json: JSONObject): Signal = Signal(
            id = json.string("id"),
            layer = json.int("layer"),
            weight = json.int("weight"),
            label = LocalizedText.fromJson(json.obj("label")),
            labelSimple = LocalizedText.fromJson(json.obj("labelSimple")),
            evidence = json.stringOrNull("evidence"),
            host = json.objOrNull("host")?.let { Host.fromJson(it) },
        )
    }
}

/** Text in both app languages (contracts/scan-result.schema.json#/$defs/LocalizedText). */
data class LocalizedText(val en: String, val id: String) {
    /** Picks the text for a language code ("id" → Bahasa Indonesia, anything else → English). */
    fun text(languageCode: String?): String = if (languageCode == "id") id else en

    companion object {
        fun fromJson(json: JSONObject): LocalizedText = LocalizedText(en = json.string("en"), id = json.string("id"))
    }
}

data class Verdict(
    val value: Value,
    val byDeviceId: String,
    val byName: String,
    val decidedAt: Instant,
) {
    /**
     * `UNKNOWN` = a verdict this build does not know (#493), decoded instead of throwing. Read-only:
     * never send it back (`POST /verdicts` takes `safe` / `not_safe` only).
     */
    enum class Value(val rawValue: String) {
        SAFE("safe"),
        NOT_SAFE("not_safe"),
        UNKNOWN("unknown");

        companion object {
            fun from(raw: String): Value = entries.firstOrNull { it.rawValue == raw } ?: UNKNOWN
        }
    }

    /**
     * null when this build does not know the value (`UNKNOWN`, a newer server, #493): screens then treat the scan as
     * not decided and show its detection status, so an unreadable verdict never looks safe.
     */
    val known: Verdict? get() = if (value == Value.UNKNOWN) null else this

    companion object {
        fun fromJson(json: JSONObject): Verdict = Verdict(
            value = Value.from(json.string("value")),
            byDeviceId = json.string("byDeviceId"),
            byName = json.string("byName"),
            decidedAt = json.instant("decidedAt"),
        )
    }
}

/** Built-in score thresholds (PRD §5 defaults). The live values come from `GET /config/public`; see #383. Owner: lead. */
object ScoreThreshold {
    const val firstWarning = 30
    const val secondWarning = 50
    const val blocked = 80
}

// MARK: App-only types (Data/Models.swift)

/** `POST /devices` response. */
data class DeviceRegistration(val deviceId: String, val token: String, val avatarId: String) {
    companion object {
        fun fromJson(json: JSONObject) = DeviceRegistration(
            deviceId = json.string("deviceId"), token = json.string("token"), avatarId = json.string("avatarId"),
        )
    }
}

/**
 * `POST /devices/me/protected` (PF-01 proposed, "Punya kode undangan?"): the new protected device
 * that replaced this guardian device, and the guardian it joined.
 */
data class ProtectedSwitch(
    val deviceId: String,
    val token: String,
    val avatarId: String,
    val guardian: GuardianInfo,
) {
    val registration: DeviceRegistration get() = DeviceRegistration(deviceId = deviceId, token = token, avatarId = avatarId)

    companion object {
        fun fromJson(json: JSONObject) = ProtectedSwitch(
            deviceId = json.string("deviceId"), token = json.string("token"), avatarId = json.string("avatarId"),
            guardian = GuardianInfo.fromJson(json.obj("guardian")),
        )
    }
}

/** `guardian` object in `GET /devices/me` and `POST /family/join`. */
data class GuardianInfo(val deviceId: String, val name: String, val avatarId: String) {
    companion object {
        fun fromJson(json: JSONObject) = GuardianInfo(
            deviceId = json.string("deviceId"), name = json.string("name"), avatarId = json.string("avatarId"),
        )
    }
}

/** `POST /family/join` response. */
data class JoinResponse(val guardian: GuardianInfo) {
    companion object {
        fun fromJson(json: JSONObject) = JoinResponse(GuardianInfo.fromJson(json.obj("guardian")))
    }
}

/**
 * `stats` in `GET /devices/me` (PF-01, proposed in backend/API.md): lifetime counters, kept past the
 * 14-day retention, and when the device registered.
 */
data class ProfileStats(val blocked: Int, val warnings: Int, val since: Instant) {
    companion object {
        fun fromJson(json: JSONObject) = ProfileStats(
            blocked = json.int("blocked"), warnings = json.int("warnings"), since = json.instant("since"),
        )
    }
}

/** `GET /devices/me` response. */
data class DeviceProfile(
    val deviceId: String,
    val name: String,
    val avatarId: String,
    val mode: UserMode,
    val language: String? = null,
    val guardian: GuardianInfo? = null,
    /** PF-01 proposed; null from a server without it (the stats row is hidden). */
    val stats: ProfileStats? = null,
    /** PF-01 proposed (Pengaturan/Notifikasi): the phone's IANA zone the server uses for quiet hours. */
    val timeZone: String? = null,
    /** PF-01 proposed; null from a server without it (the page shows the defaults). */
    val notifications: NotificationSettings? = null,
) {
    companion object {
        fun fromJson(json: JSONObject) = DeviceProfile(
            deviceId = json.string("deviceId"),
            name = json.string("name"),
            avatarId = json.string("avatarId"),
            mode = json.string("mode").let { UserMode.from(it) ?: throw DecodingException("mode: unknown value") },
            language = json.stringOrNull("language"),
            guardian = json.objOrNull("guardian")?.let { GuardianInfo.fromJson(it) },
            stats = json.objOrNull("stats")?.let { ProfileStats.fromJson(it) },
            timeZone = json.stringOrNull("timeZone"),
            notifications = json.objOrNull("notifications")?.let { NotificationSettings.fromJson(it) },
        )
    }
}

/** PF-01 "Pengaturan/Notifikasi" (proposed). Kept on the server, which decides which pushes go out. */
data class NotificationSettings(
    /** "Situs berbahaya": your own warning scans. */
    val warning: Boolean,
    /** "Situs diblokir": your own blocked scans. */
    val blocked: Boolean,
    /** Guardian: "Aktivitas orang dilindungi". */
    val family: Boolean,
    /** Guardian: "Perlindungan mati". */
    val protectionOff: Boolean,
    /** "Ringkasan mingguan", Monday 08:00. */
    val weeklySummary: Boolean,
    /** "Jam tenang": warnings wait; blocked sites still push. */
    val quietHours: Boolean,
    /** Local 24-hour "HH:MM". */
    val quietStart: String,
    val quietEnd: String,
) {
    /** These settings with the keys `update` sets. */
    fun applying(update: NotificationSettingsUpdate): NotificationSettings = copy(
        warning = update.warning ?: warning,
        blocked = update.blocked ?: blocked,
        family = update.family ?: family,
        protectionOff = update.protectionOff ?: protectionOff,
        weeklySummary = update.weeklySummary ?: weeklySummary,
        quietHours = update.quietHours ?: quietHours,
        quietStart = update.quietStart ?: quietStart,
        quietEnd = update.quietEnd ?: quietEnd,
    )

    /**
     * A failed update undone: the `keys` it still owns go back to `before`; every other key keeps what is on
     * screen now (fase 27i, K11).
     */
    fun reverting(keys: Set<NotificationSettingsUpdate.Key>, before: NotificationSettings): NotificationSettings {
        var s = this
        for (key in keys) {
            s = when (key) {
                NotificationSettingsUpdate.Key.WARNING -> s.copy(warning = before.warning)
                NotificationSettingsUpdate.Key.BLOCKED -> s.copy(blocked = before.blocked)
                NotificationSettingsUpdate.Key.FAMILY -> s.copy(family = before.family)
                NotificationSettingsUpdate.Key.PROTECTION_OFF -> s.copy(protectionOff = before.protectionOff)
                NotificationSettingsUpdate.Key.WEEKLY_SUMMARY -> s.copy(weeklySummary = before.weeklySummary)
                NotificationSettingsUpdate.Key.QUIET_HOURS -> s.copy(quietHours = before.quietHours)
                NotificationSettingsUpdate.Key.QUIET_START -> s.copy(quietStart = before.quietStart)
                NotificationSettingsUpdate.Key.QUIET_END -> s.copy(quietEnd = before.quietEnd)
            }
        }
        return s
    }

    companion object {
        /** The server's defaults (migration 20261028130000). */
        val defaults = NotificationSettings(
            warning = true, blocked = true, family = true, protectionOff = true, weeklySummary = false,
            quietHours = true, quietStart = "22:00", quietEnd = "06:00",
        )

        fun fromJson(json: JSONObject) = NotificationSettings(
            warning = json.bool("warning"),
            blocked = json.bool("blocked"),
            family = json.bool("family"),
            protectionOff = json.bool("protectionOff"),
            weeklySummary = json.bool("weeklySummary"),
            quietHours = json.bool("quietHours"),
            quietStart = json.string("quietStart"),
            quietEnd = json.string("quietEnd"),
        )
    }
}

/** Only the switches that changed; null keys are left out of `PATCH /devices/me`. */
data class NotificationSettingsUpdate(
    val warning: Boolean? = null,
    val blocked: Boolean? = null,
    val family: Boolean? = null,
    val protectionOff: Boolean? = null,
    val weeklySummary: Boolean? = null,
    val quietHours: Boolean? = null,
    val quietStart: String? = null,
    val quietEnd: String? = null,
) {
    enum class Key { WARNING, BLOCKED, FAMILY, PROTECTION_OFF, WEEKLY_SUMMARY, QUIET_HOURS, QUIET_START, QUIET_END }

    /** The keys this update sets. */
    val keys: Set<Key>
        get() = buildSet {
            if (warning != null) add(Key.WARNING)
            if (blocked != null) add(Key.BLOCKED)
            if (family != null) add(Key.FAMILY)
            if (protectionOff != null) add(Key.PROTECTION_OFF)
            if (weeklySummary != null) add(Key.WEEKLY_SUMMARY)
            if (quietHours != null) add(Key.QUIET_HOURS)
            if (quietStart != null) add(Key.QUIET_START)
            if (quietEnd != null) add(Key.QUIET_END)
        }

    fun toJson(): JSONObject = JSONObject().apply {
        warning?.let { put("warning", it) }
        blocked?.let { put("blocked", it) }
        family?.let { put("family", it) }
        protectionOff?.let { put("protectionOff", it) }
        weeklySummary?.let { put("weeklySummary", it) }
        quietHours?.let { put("quietHours", it) }
        quietStart?.let { put("quietStart", it) }
        quietEnd?.let { put("quietEnd", it) }
    }
}

/** `PATCH /devices/me` body. null fields are left out of the request. */
data class DeviceUpdate(
    val name: String? = null,
    val apnsToken: String? = null,
    val language: String? = null,
    val extensionLastSeenAt: Instant? = null,
    /** PF-01 proposed: "Pixel 8" and "15" on the guardian's member detail. */
    val deviceModel: String? = null,
    val osVersion: String? = null,
    /** PF-01 proposed "Ubah foto": one of the onboarding avatars. */
    val avatarId: String? = null,
    /** PF-01 proposed: IANA zone ("Asia/Makassar") for quiet hours and the weekly summary. */
    val timeZone: String? = null,
    val notifications: NotificationSettingsUpdate? = null,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        name?.let { put("name", it) }
        apnsToken?.let { put("apnsToken", it) }
        language?.let { put("language", it) }
        extensionLastSeenAt?.let { put("extensionLastSeenAt", ShooJson.format(it)) }
        deviceModel?.let { put("deviceModel", it) }
        osVersion?.let { put("osVersion", it) }
        avatarId?.let { put("avatarId", it) }
        timeZone?.let { put("timeZone", it) }
        notifications?.let { put("notifications", it.toJson()) }
    }
}

/** `POST /family/code` response. 6 digits, valid 30 min, `inviteUrl` = `https://<api host>/j/<code>`. */
data class FamilyCode(val code: String, val expiresAt: Instant, val inviteUrl: String) {
    companion object {
        fun fromJson(json: JSONObject) = FamilyCode(
            code = json.string("code"), expiresAt = json.instant("expiresAt"), inviteUrl = json.string("inviteUrl"),
        )
    }
}

/** One entry of `GET /family/members`. */
data class FamilyMember(
    val deviceId: String,
    val name: String,
    val avatarId: String,
    val extensionActive: Boolean,
    val lastScan: LastScan? = null,
    // PF-01 proposed (backend/API.md): null from a server without them, and the row is hidden.
    /** "Terhubung sejak". */
    val connectedAt: Instant? = null,
    /** Last extension heartbeat ("aktif 2 mnt lalu"). */
    val lastSeenAt: Instant? = null,
    val deviceModel: String? = null,
    val osVersion: String? = null,
    /** "Kabari saya". */
    val notify: Boolean? = null,
    /** Last "Ingatkan" push. */
    val remindedAt: Instant? = null,
    val stats: Stats? = null,
) {
    val id: String get() = deviceId

    data class LastScan(val status: ScanStatus, val score: Int, val url: String, val detectedAt: Instant) {
        companion object {
            fun fromJson(json: JSONObject) = LastScan(
                status = ScanStatus.from(json.string("status")), score = json.int("score"),
                url = json.string("url"), detectedAt = json.instant("detectedAt"),
            )
        }
    }

    /** `stats` of a member (PF-01 proposed). */
    data class Stats(val blocked: Int, val warnings: Int) {
        companion object {
            fun fromJson(json: JSONObject) = Stats(blocked = json.int("blocked"), warnings = json.int("warnings"))
        }
    }

    companion object {
        fun fromJson(json: JSONObject) = FamilyMember(
            deviceId = json.string("deviceId"),
            name = json.string("name"),
            avatarId = json.string("avatarId"),
            extensionActive = json.bool("extensionActive"),
            lastScan = json.objOrNull("lastScan")?.let { LastScan.fromJson(it) },
            connectedAt = json.instantOrNull("connectedAt"),
            lastSeenAt = json.instantOrNull("lastSeenAt"),
            deviceModel = json.stringOrNull("deviceModel"),
            osVersion = json.stringOrNull("osVersion"),
            notify = json.boolOrNull("notify"),
            remindedAt = json.instantOrNull("remindedAt"),
            stats = json.objOrNull("stats")?.let { Stats.fromJson(it) },
        )
    }
}

/** `GET /family/members` response. Row by row (#493): a member the app can't read is left out, the rest still shows. */
data class FamilyMembersResponse(val members: List<FamilyMember>) {
    companion object {
        fun fromJson(json: JSONObject) = FamilyMembersResponse(
            LossyList.decode(json.array("members"), "members", { FamilyMember.fromJson(it) }).elements,
        )
    }
}

/**
 * One card of the Home row "Scam terbaru di pengguna Shoo" (Figma 955:10323): an item of `GET /scams/latest`
 * (contracts/api.md, fixtures/latest-scams.json). The words are the admin's category label; the card adds
 * "Hari ini" / "Kemarin" / "3 hari lalu" from `lastSeenAt`. No channel ("lewat WhatsApp"): Shoo only sees the
 * address, not where the link came from.
 */
data class ScamCase(
    /** The category id (`undian_palsu`); one card per category. */
    val id: String,
    val title: LocalizedText,
    /** The newest counted scan, server time rounded to the hour. */
    val lastSeenAt: Instant,
) {
    companion object {
        fun fromJson(json: JSONObject) = ScamCase(
            id = json.string("category"),
            title = LocalizedText.fromJson(json.obj("title")),
            lastSeenAt = json.instant("lastSeenAt"),
        )
    }
}

/** `GET /scams/latest` response. A broken item is dropped, the rest still show. */
data class LatestScamsPage(val items: List<ScamCase>) {
    companion object {
        fun fromJson(json: JSONObject) = LatestScamsPage(LossyList.decode(json.array("items"), "items", { ScamCase.fromJson(it) }).elements)
    }
}

/**
 * `GET /scans` response. Row by row (#493): a scan the app can't read is left out; the other rows and `nextCursor`
 * stay, so the next page still loads. A page whose rows were all left out is empty, not an error.
 */
data class ScanPage(val items: List<ScanResult>, val nextCursor: String? = null) {
    companion object {
        fun fromJson(json: JSONObject) = ScanPage(
            items = LossyList.decode(json.array("items"), "items", { ScanResult.fromJson(it) }).elements,
            nextCursor = json.stringOrNull("nextCursor"),
        )
    }
}

/** `POST /verdicts` response. */
data class VerdictResponse(val verdict: Verdict) {
    companion object {
        fun fromJson(json: JSONObject) = VerdictResponse(Verdict.fromJson(json.obj("verdict")))
    }
}

/** `{ "ok": true }` answers. */
data class OkResponse(val ok: Boolean) {
    companion object {
        fun fromJson(json: JSONObject) = OkResponse(json.bool("ok"))
    }
}

/** `owner=` filter of `GET /scans`. */
sealed interface ScanOwnerFilter {
    val queryValue: String

    data object Me : ScanOwnerFilter {
        override val queryValue: String get() = "me"
    }

    /** The guardian's own scans plus their protected members' (contracts/api.md). */
    data object Family : ScanOwnerFilter {
        override val queryValue: String get() = "family"
    }

    data class Device(val id: String) : ScanOwnerFilter {
        override val queryValue: String get() = id
    }
}

/** Error codes from contracts/api.md. Open set: unknown server codes still decode. */
@JvmInline
value class APIErrorCode(val rawValue: String) {
    override fun toString(): String = rawValue

    companion object {
        // Common
        val invalidBody = APIErrorCode("invalid_body")
        val badJSON = APIErrorCode("bad_json")
        val tooLarge = APIErrorCode("too_large")
        val rateLimited = APIErrorCode("rate_limited")
        val internal = APIErrorCode("internal")
        // Backend-specific (plan/alief/ref/R3 §1)
        val unauthorized = APIErrorCode("unauthorized")
        val forbidden = APIErrorCode("forbidden")
        val notFound = APIErrorCode("not_found")
        val codeUnavailable = APIErrorCode("code_unavailable")
        // Join (PR-01, PR-03)
        val codeInvalid = APIErrorCode("code_invalid")
        val codeExpired = APIErrorCode("code_expired")
        val familyFull = APIErrorCode("family_full")
        val tooManyAttempts = APIErrorCode("too_many_attempts")
        val alreadyConnected = APIErrorCode("already_connected")
        // Verdicts (GD-07)
        val verdictNotAllowed = APIErrorCode("verdict_not_allowed")
        /** 409: the link has a `safe` verdict that stays until the weekly AI review (#476). */
        val verdictLocked = APIErrorCode("verdict_locked")
        // Member reminder (PF-01 proposed)
        val pushUnavailable = APIErrorCode("push_unavailable")
        val remindTooSoon = APIErrorCode("remind_too_soon")
        // Guardian → Protected (PF-01 proposed)
        val hasMembers = APIErrorCode("has_members")
    }
}

/** `{ "error": { "code", "message" } }` body (contracts/api.md). */
data class APIErrorBody(val error: Detail) {
    data class Detail(val code: String, val message: String)

    companion object {
        fun fromJson(json: JSONObject): APIErrorBody {
            val detail = json.obj("error")
            return APIErrorBody(Detail(code = detail.string("code"), message = detail.string("message")))
        }
    }
}

/** Everything a `ShooRepository` call can throw. */
sealed class RepositoryError : Exception() {
    /** The backend answered with a contract error code. */
    data class Api(val code: APIErrorCode, override val message: String) : RepositoryError()

    /** No connection, timeout, TLS failure. */
    data object Network : RepositoryError() {
        override val message: String get() = "network"
    }

    /** The response did not match the contract. */
    data object Decoding : RepositoryError() {
        override val message: String get() = "decoding"
    }

    /** A 429 (`rate_limited`, `too_many_attempts`) that said how long to wait (`Retry-After` seconds, contracts/api.md). */
    data class Throttled(val code: APIErrorCode, override val message: String, override val retryAfter: Double) : RepositoryError()

    open val apiCode: APIErrorCode?
        get() = when (this) {
            is Api -> code
            is Throttled -> code
            Network, Decoding -> null
        }

    /** Seconds the server asked to wait before the next try, when it said. */
    open val retryAfter: Double? get() = null
}

/**
 * Why a screen could not load, for the sentence under "Couldn't load" (A-03, fase 28m). Only a request that
 * never reached the server asks the person to check their connection: a server error (5xx) or an answer the
 * app can't read is not theirs to fix.
 */
enum class LoadFailure {
    /** No connection, timeout, TLS failure; also every error this type does not name. */
    CONNECTION,
    /** A 5xx (`internal`, or a status without a contract body) or a response that broke the contract. */
    SERVER;

    /** The screen's own "check your connection" catalog key, or the general one. Look the key up with `t()`. */
    fun message(connection: String): String = when (this) {
        CONNECTION -> connection
        SERVER -> "Something went wrong. Try again."
    }

    companion object {
        fun from(error: Throwable): LoadFailure = when {
            error is RepositoryError.Decoding -> SERVER
            error is RepositoryError.Api && error.code == APIErrorCode.internal -> SERVER
            else -> CONNECTION
        }
    }
}

// MARK: JSON (iOS `JSONDecoder.shoo` / `JSONEncoder.shoo`)

/** A response or fixture that does not match the contract. Message: contract field names only, never a value (P6). */
class DecodingException(message: String) : Exception(message)

object ShooJson {
    /**
     * ISO 8601 UTC dates, with or without fractional seconds (the backend sends `2026-10-21T04:05:00.123Z`;
     * blocklist cursors carry microseconds). An offset other than `Z` is accepted too, like Swift's
     * `.withInternetDateTime`.
     */
    fun parseDate(text: String): Instant = try {
        Instant.parse(text)
    } catch (_: Exception) {
        try {
            OffsetDateTime.parse(text, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant()
        } catch (_: Exception) {
            throw DecodingException("Expected an ISO 8601 date")
        }
    }

    /** Swift `.iso8601` encoding: whole seconds, `Z`. */
    fun format(instant: Instant): String = DateTimeFormatter.ISO_INSTANT.format(instant.truncatedTo(ChronoUnit.SECONDS))
}

// Strict readers: like Swift `Codable`, `null` or a missing key is only accepted for optional fields, and a value of
// another JSON type throws (org.json alone would turn a number into a string, or `null` into "null").

private fun JSONObject.raw(key: String): Any? = opt(key).takeUnless { it == null || it == JSONObject.NULL }

internal fun JSONObject.string(key: String): String =
    stringOrNull(key) ?: throw DecodingException("$key: missing")

internal fun JSONObject.stringOrNull(key: String): String? = when (val value = raw(key)) {
    null -> null
    is String -> value
    else -> throw DecodingException("$key: not a string")
}

internal fun JSONObject.int(key: String): Int = intOrNull(key) ?: throw DecodingException("$key: missing")

internal fun JSONObject.intOrNull(key: String): Int? = when (val value = raw(key)) {
    null -> null
    is Int -> value
    is Long -> if (value in Int.MIN_VALUE..Int.MAX_VALUE) value.toInt() else throw DecodingException("$key: out of range")
    is Number -> value.toDouble().let { if (it % 1.0 == 0.0 && it in -2.147483648E9..2.147483647E9) it.toInt() else throw DecodingException("$key: not an integer") }
    else -> throw DecodingException("$key: not a number")
}

internal fun JSONObject.bool(key: String): Boolean = boolOrNull(key) ?: throw DecodingException("$key: missing")

internal fun JSONObject.boolOrNull(key: String): Boolean? = when (val value = raw(key)) {
    null -> null
    is Boolean -> value
    else -> throw DecodingException("$key: not a boolean")
}

internal fun JSONObject.instant(key: String): Instant = instantOrNull(key) ?: throw DecodingException("$key: missing")

internal fun JSONObject.instantOrNull(key: String): Instant? = stringOrNull(key)?.let {
    try {
        ShooJson.parseDate(it)
    } catch (_: DecodingException) {
        throw DecodingException("$key: not an ISO 8601 date")
    }
}

internal fun JSONObject.obj(key: String): JSONObject = objOrNull(key) ?: throw DecodingException("$key: missing")

internal fun JSONObject.objOrNull(key: String): JSONObject? = when (val value = raw(key)) {
    null -> null
    is JSONObject -> value
    else -> throw DecodingException("$key: not an object")
}

internal fun JSONObject.array(key: String): JSONArray = arrayOrNull(key) ?: throw DecodingException("$key: missing")

internal fun JSONObject.arrayOrNull(key: String): JSONArray? = when (val value = raw(key)) {
    null -> null
    is JSONArray -> value
    else -> throw DecodingException("$key: not an array")
}

internal fun JSONArray.objectAt(index: Int): JSONObject =
    opt(index) as? JSONObject ?: throw DecodingException("[$index]: not an object")

internal fun JSONArray.stringAt(index: Int): String =
    opt(index) as? String ?: throw DecodingException("[$index]: not a string")

/** Parses a response body; anything that is not a JSON object breaks the contract. */
internal fun parseObject(text: String): JSONObject = try {
    JSONObject(text)
} catch (_: Exception) {
    throw DecodingException("not a JSON object")
}
