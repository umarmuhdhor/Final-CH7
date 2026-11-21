package com.shoo.app.data

import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * PF-01 Protected "Akun Tertaut" switches, "Link terblokir" and the "Situs diperiksa" counter.
 *
 * Kept with the App Group keys so `getSession` hands the switches to the add-on (contracts/app-group-keys.md
 * `link.autoSend`, `history.shareWarnings`). Android: the add-on only reads them when it is linked again.
 */
class LinkedAccountSettings(private val defaults: SharedPreferences) {
    object Key {
        /** Int, written by the extension: pages checked on this phone. Missing = not counted yet. */
        const val statsChecked = AppGroup.Key.statsChecked
        /** Bool, default `true`: "Kirim link secara otomatis", links checked here go to the guardian. */
        const val autoSendLinks = AppGroup.Key.autoSendLinks
        /** Bool, default `true`: "Bagikan riwayat waspada", the guardian also sees warnings (blocked always). */
        const val shareWarnings = AppGroup.Key.shareWarnings
        /** Bool, default `true`: "Link terblokir", a push when the guardian verifies a link. */
        const val notifyLinkVerified = AppGroup.Key.notifyLinkVerified

        val all = listOf(statsChecked, autoSendLinks, shareWarnings, notifyLinkVerified)
    }

    private var _autoSendLinks by mutableStateOf(defaults.optBoolean(Key.autoSendLinks) ?: true)
    private var _shareWarnings by mutableStateOf(defaults.optBoolean(Key.shareWarnings) ?: true)
    private var _notifyLinkVerified by mutableStateOf(defaults.optBoolean(Key.notifyLinkVerified) ?: true)

    var autoSendLinks: Boolean
        get() = _autoSendLinks
        set(value) {
            _autoSendLinks = value
            defaults.edit().putBoolean(Key.autoSendLinks, value).apply()
        }

    var shareWarnings: Boolean
        get() = _shareWarnings
        set(value) {
            _shareWarnings = value
            defaults.edit().putBoolean(Key.shareWarnings, value).apply()
        }

    var notifyLinkVerified: Boolean
        get() = _notifyLinkVerified
        set(value) {
            _notifyLinkVerified = value
            defaults.edit().putBoolean(Key.notifyLinkVerified, value).apply()
        }

    /** null until the extension writes the counter. */
    var checkedCount by mutableStateOf(defaults.optInt(Key.statsChecked))
        private set

    /** The extension may have counted more pages since the screen opened. */
    fun refresh() {
        checkedCount = defaults.optInt(Key.statsChecked)
    }

    /** Delete account: nothing of this device stays behind (SECURITY §3 P3). */
    fun clear() {
        autoSendLinks = true
        shareWarnings = true
        notifyLinkVerified = true
        checkedCount = null
        // After the resets above, which write the defaults back.
        val editor = defaults.edit()
        for (key in Key.all) editor.remove(key)
        editor.apply()
    }

    companion object {
        /**
         * `false` until the extension and server honor the switches (#183). Until then the UI shows the
         * "Akun Tertaut" switches locked at what really happens (everything shared) and hides
         * "Link terblokir", so no switch looks live while doing nothing (lead review on #184).
         */
        const val switchesAreLive = false
    }
}
