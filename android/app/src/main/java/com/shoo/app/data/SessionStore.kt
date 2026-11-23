package com.shoo.app.data

import android.content.Context
import android.content.SharedPreferences
import com.shoo.app.BuildConfig
import com.shoo.app.app.AppConfig
import java.net.URI
import java.util.concurrent.CopyOnWriteArrayList
import org.json.JSONObject

/**
 * The device session after `POST /devices` (fase 13, D-alief-10).
 *
 * - The token lives in the Android Keystore-encrypted [KeychainItem] (SECURITY §3 P4); the app reads it only
 *   from there.
 * - The contract keys (contracts/app-group-keys.md) are kept in the "App Group" prefs (`AppGroup.defaults`), always
 *   through `AppGroup.Key`. Nothing else goes there. Android: the token is never copied there in plain text; the
 *   add-on gets it from [addonSession] when it is linked.
 * - The guardian's avatar is kept in memory only; `GET /devices/me` brings it back (D-alief-C02).
 * - This device's own avatar id (`avatar_01…12`, a catalog id, not personal data) is kept in the app's own prefs,
 *   not the App Group, so Home's profile circle shows it at launch before `GET /devices/me` answers (PF-01).
 *   Cleared with the session.
 */
class SessionStore(
    val defaults: SharedPreferences,
    /** The app's own prefs, for what the extension never reads. */
    val localDefaults: SharedPreferences,
    val keychain: KeychainItem,
    val apiBaseURL: String = AppConfig.apiBaseURL,
    val aiBaseURL: String? = AppConfig.aiBaseURL,
    onlineCheckAllowed: Boolean = false,
    /** Empties in-memory copies of server data (the favicon cache, fase 22c) when what they show is no longer this
     * phone's to see (P13). */
    private val forgetCachedDataHandler: () -> Unit = { InMemoryCaches.clear() },
) {
    private val lock = Any()
    private var _guardian: GuardianInfo? = null
    private var _onlineCheckAllowed = onlineCheckAllowed

    /** Bearer token for the API. null before onboarding, after delete, or when the Keystore key is gone.
     * Throws when the Keystore can't be opened right now. */
    fun readToken(): String? = keychain.read()

    /** `readToken()` with an unreadable store read as "no token" (tests, simple checks). */
    val token: String?
        get() = try {
            readToken()
        } catch (_: Exception) {
            null
        }

    val deviceId: String? get() = defaults.getString(AppGroup.Key.deviceId, null)

    /** This device's avatar from the last registration, `GET /devices/me` or avatar change. null without a session. */
    val avatarId: String?
        get() = synchronized(lock) { if (hasSessionLocked) localDefaults.getString(avatarIdKey, null) else null }

    /** Protected: the guardian from the last join or `GET /devices/me`. */
    val guardian: GuardianInfo? get() = synchronized(lock) { _guardian }

    /** A guardian looks after this phone: in memory, or its name kept from an earlier launch (before
     * `GET /devices/me` answers). Cleared by `setGuardian(null)`, `save` and `clear`. */
    val hasGuardian: Boolean
        get() = synchronized(lock) {
            _guardian != null || (hasSessionLocked && defaults.getString(AppGroup.Key.guardianName, null) != null)
        }

    /** After `POST /devices`: Keychain first, so a failed write leaves no half session behind. One lock around every
     * write, so a `clear()` from a 401 can't interleave with it. */
    fun save(registration: DeviceRegistration, name: String, mode: UserMode) {
        synchronized(lock) {
            keychain.write(registration.token)
            defaults.edit()
                .putString(AppGroup.Key.deviceId, registration.deviceId)
                .putString(AppGroup.Key.deviceMode, mode.rawValue)
                .putString(AppGroup.Key.deviceName, name)
                .remove(AppGroup.Key.guardianName)
                .remove(AppGroup.Key.deviceToken)
                // Android: the add-on holds a copy of the old token (it can't read this storage live), so a new
                // device must be linked again.
                .remove(AppGroup.Key.firefoxLinkedAt)
                .apply()
            localDefaults.edit().putString(avatarIdKey, registration.avatarId).apply()
            _guardian = null
            writeBaseURLsLocked()
        }
        // A new device (registration, guardian → protected) sees other scans.
        forgetCachedData()
    }

    /** Also at every launch, so a new build's URLs reach the extension. */
    fun writeBaseURLs() {
        synchronized(lock) { writeBaseURLsLocked() }
    }

    /** The person's answer (`DataConsent`). The extension calls `/analyze` only with `aiBaseURL`, so without the key
     * no page leaves the phone for a check. */
    fun setOnlineCheck(allowed: Boolean) {
        synchronized(lock) {
            _onlineCheckAllowed = allowed
            if (hasSessionLocked) writeBaseURLsLocked()
        }
    }

    /** After `PATCH /devices/me { name }` or a `GET /devices/me` with another name. A no-op once the session is
     * gone: a late answer never brings data back after delete (P13). */
    fun updateName(name: String) {
        synchronized(lock) { updateNameLocked(name) }
    }

    /** After `PATCH /devices/me { avatarId }`. A no-op once the session is gone (P13). */
    fun updateAvatar(avatarId: String) {
        synchronized(lock) { updateAvatarLocked(avatarId) }
    }

    /** null = no guardian (left, removed by the guardian, or never joined): EX-06 stops naming them. */
    fun setGuardian(guardian: GuardianInfo?) {
        val lostGuardian = synchronized(lock) { setGuardianLocked(guardian) }
        // Left the family, or the guardian removed this phone. Not on a guardian's every `GET /devices/me`.
        if (lostGuardian) forgetCachedData()
    }

    /**
     * `GET /devices/me`: name, avatar and guardian, only while `ifToken` is still the session's token. One lock
     * around the check and the writes, so a switch to a new device ("Punya kode undangan?") can't land between them
     * and get the old device's profile (fase 27h, F-A12). `false` = not written.
     */
    fun applyProfile(name: String, avatarId: String? = null, guardian: GuardianInfo?, ifToken: String): Boolean {
        var lostGuardian = false
        val applied = synchronized(lock) {
            val current = try {
                keychain.read()
            } catch (_: Exception) {
                null
            }
            if (current != ifToken) {
                false
            } else {
                updateNameLocked(name)
                if (avatarId != null) updateAvatarLocked(avatarId)
                lostGuardian = setGuardianLocked(guardian)
                true
            }
        }
        if (lostGuardian) forgetCachedData()
        return applied
    }

    private fun updateNameLocked(name: String) {
        if (!hasSessionLocked) return
        defaults.edit().putString(AppGroup.Key.deviceName, name).apply()
    }

    private fun updateAvatarLocked(avatarId: String) {
        if (!hasSessionLocked) return
        localDefaults.edit().putString(avatarIdKey, avatarId).apply()
    }

    /** `true` when a guardian this phone had is now gone. */
    private fun setGuardianLocked(guardian: GuardianInfo?): Boolean {
        if (guardian != null && !hasSessionLocked) return false
        val hadGuardian = _guardian != null || defaults.getString(AppGroup.Key.guardianName, null) != null
        _guardian = guardian
        if (guardian != null) {
            defaults.edit().putString(AppGroup.Key.guardianName, guardian.name).apply()
        } else {
            defaults.edit().remove(AppGroup.Key.guardianName).apply()
        }
        return hadGuardian && guardian == null
    }

    /** Delete my data, session expired: the extension loses its session at once (P3, P13). */
    fun clear() {
        synchronized(lock) {
            keychain.delete()
            val editor = defaults.edit()
            for (key in appKeys) editor.remove(key)
            editor.apply()
            localDefaults.edit().remove(avatarIdKey).apply()
            _guardian = null
        }
        forgetCachedData()
    }

    /** Also from `ApiRepository.removeMember`. Outside `lock`: the cache has its own. */
    fun forgetCachedData() = forgetCachedDataHandler()

    /**
     * Android only: the `getSession` reply (contracts/app-group-keys.md) that `AddonBridge` hands to the Firefox
     * add-on, without its `ok`. iOS: `SafariWebExtensionHandler.sessionReply()`. null = not onboarded.
     */
    fun addonSession(): JSONObject? {
        val deviceId = defaults.getString(AppGroup.Key.deviceId, null) ?: return null
        val token = token ?: return null
        val mode = defaults.getString(AppGroup.Key.deviceMode, null) ?: return null
        return JSONObject()
            .put("deviceId", deviceId)
            .put("token", token)
            .put("mode", mode)
            .put("name", defaults.getString(AppGroup.Key.deviceName, null) ?: "")
            .put("guardianName", defaults.getString(AppGroup.Key.guardianName, null) ?: JSONObject.NULL)
            .put("apiBaseURL", defaults.getString(AppGroup.Key.apiBaseURL, null) ?: JSONObject.NULL)
            .put("aiBaseURL", defaults.getString(AppGroup.Key.aiBaseURL, null) ?: JSONObject.NULL)
            .put("autoSend", defaults.optBoolean(AppGroup.Key.autoSendLinks) ?: true)
            .put("shareWarnings", defaults.optBoolean(AppGroup.Key.shareWarnings) ?: true)
    }

    private val hasSessionLocked: Boolean get() = defaults.getString(AppGroup.Key.deviceId, null) != null

    private fun writeBaseURLsLocked() {
        val editor = defaults.edit()
        // Release builds only ever hand the extension HTTPS endpoints (P5); plain HTTP is `wrangler dev`.
        if (isAllowed(apiBaseURL)) {
            editor.putString(AppGroup.Key.apiBaseURL, apiBaseURL)
        } else {
            editor.remove(AppGroup.Key.apiBaseURL)
        }
        val ai = aiBaseURL
        if (_onlineCheckAllowed && ai != null && isAllowed(ai)) {
            editor.putString(AppGroup.Key.aiBaseURL, ai)
        } else {
            editor.remove(AppGroup.Key.aiBaseURL)
        }
        editor.apply()
    }

    companion object {
        /** App-only key (never in the App Group: the extension has no use for it). */
        const val avatarIdKey = "session.avatarId"

        /**
         * The keys this app writes. `extension.lastSeenAt` belongs to the extension and is left alone. The Protected
         * "Akun Tertaut" switches go too: the extension reads them, so an old account's `false` would stop the next
         * account's scans (fase 27h, F-A13). Android: the add-on link goes too (it holds the old token).
         */
        val appKeys = listOf(
            AppGroup.Key.deviceId, AppGroup.Key.deviceToken, AppGroup.Key.deviceMode, AppGroup.Key.deviceName,
            AppGroup.Key.guardianName, AppGroup.Key.apiBaseURL, AppGroup.Key.aiBaseURL,
            AppGroup.Key.statsChecked, AppGroup.Key.statsLastCheckedAt,
            LinkedAccountSettings.Key.autoSendLinks, LinkedAccountSettings.Key.shareWarnings,
            LinkedAccountSettings.Key.notifyLinkVerified, AppGroup.Key.firefoxLinkedAt,
        )

        const val LOCAL_PREFS = "shoo.local"
        const val KEYCHAIN_PREFS = "shoo.keychain"

        /** The real store: App Group prefs, the app's prefs, and the Keystore-encrypted token. */
        fun create(
            context: Context,
            apiBaseURL: String = AppConfig.apiBaseURL,
            aiBaseURL: String? = AppConfig.aiBaseURL,
            onlineCheckAllowed: Boolean = false,
        ): SessionStore = SessionStore(
            defaults = AppGroup.defaults(context),
            localDefaults = context.getSharedPreferences(LOCAL_PREFS, Context.MODE_PRIVATE),
            keychain = KeystoreKeychainItem(context.getSharedPreferences(KEYCHAIN_PREFS, Context.MODE_PRIVATE)),
            apiBaseURL = apiBaseURL,
            aiBaseURL = aiBaseURL,
            onlineCheckAllowed = onlineCheckAllowed,
        )

        fun isAllowed(url: String): Boolean {
            val uri = try {
                URI(url)
            } catch (_: Exception) {
                return false
            }
            if (uri.scheme == "https") return true
            // Debug only: `wrangler dev` on the computer (10.0.2.2 is the computer as the Android emulator sees it).
            return BuildConfig.DEBUG && uri.scheme == "http" && uri.host in setOf("localhost", "127.0.0.1", "10.0.2.2")
        }
    }
}

/**
 * In-memory copies of server data (iOS `CachedFaviconLoader.shared`). A cache registers its `clear` here, and the
 * session empties them when what they show is no longer this phone's to see (P13).
 */
object InMemoryCaches {
    private val clearers = CopyOnWriteArrayList<() -> Unit>()

    fun register(clear: () -> Unit) {
        clearers.add(clear)
    }

    fun clear() {
        for (clear in clearers) clear()
    }
}
