package com.shoo.app.data

import android.content.SharedPreferences
import java.time.Instant

/**
 * What the extension has checked on this phone (Activity empty states, PR-05): how many pages and when the last
 * one was. Numbers and a time only, never addresses.
 *
 * Android: the Firefox add-on counts in its own storage (`native-bridge.js` answers `pageChecked`) and can't write
 * the app's, so both stay null and Activity falls back to "extension on", like iOS before the extension wrote them.
 */
data class CheckStats(
    /** null until the extension writes the counter. */
    val checked: Int? = null,
    val lastCheckedAt: Instant? = null,
) {
    object Key {
        /** Int, written by the extension: pages checked on this phone, all verdicts. */
        const val checked = AppGroup.Key.statsChecked
        /** Date, written by the extension: when it last checked a page. */
        const val lastCheckedAt = AppGroup.Key.statsLastCheckedAt
    }

    companion object {
        fun current(defaults: SharedPreferences): CheckStats =
            CheckStats(checked = defaults.optInt(Key.checked), lastCheckedAt = defaults.optInstant(Key.lastCheckedAt))

        /** Delete my data: nothing of this device stays behind (SECURITY §3 P3). */
        fun clear(defaults: SharedPreferences) {
            defaults.edit().remove(Key.checked).remove(Key.lastCheckedAt).apply()
        }
    }
}
