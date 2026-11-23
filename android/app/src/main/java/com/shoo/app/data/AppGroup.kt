package com.shoo.app.data

import android.content.Context
import android.content.SharedPreferences

/**
 * iOS `ShooShared/AppGroup.swift`: what the app shares with the browser extension (contracts/app-group-keys.md).
 *
 * Android has no App Group: the Firefox add-on can't read the app's storage. It gets these values once, as the
 * `getSession` reply, through `bridge/AddonBridge` when the person links it. The keys stay the contract's, in a
 * private `SharedPreferences` file, so every rule written against them (SessionStore, LinkedAccountSettings,
 * CheckStats, ExtensionStatus) reads the same as on iOS. Dates are stored as epoch milliseconds.
 */
object AppGroup {
    const val id = "group.com.shoo.app"

    fun defaults(context: Context): SharedPreferences = context.getSharedPreferences(id, Context.MODE_PRIVATE)

    object Key {
        const val deviceId = "device.id"
        /** iOS copies the token here for the extension. Android never writes it in plain text (the add-on gets it from
         * the Keystore-backed `SessionStore` at link time); kept so `SessionStore.clear()` removes an old copy. */
        const val deviceToken = "device.token"
        const val deviceMode = "device.mode"
        const val deviceName = "device.name"
        const val guardianName = "guardian.name"
        const val extensionLastSeenAt = "extension.lastSeenAt"
        /** Bool. `false` = browser access narrowed to some sites → treat as Off (EX-01). Missing = unknown, treat as `true`. */
        const val extensionAllSites = "extension.allSites"
        const val apiBaseURL = "api.baseURL"
        const val aiBaseURL = "ai.baseURL"
        /** Int, written by the extension: pages checked on this phone. Missing = not counted yet. */
        const val statsChecked = "stats.checked"
        /** Date, written with `statsChecked`: when the extension last checked a page. */
        const val statsLastCheckedAt = "stats.lastCheckedAt"
        /** Bool, default `true`. `false` = warnings stay on this phone; blocked is always sent (#183). */
        const val autoSendLinks = "link.autoSend"
        /** Bool, default `true`. `false` = warnings stay on this phone; blocked is always sent. */
        const val shareWarnings = "history.shareWarnings"
        /** Bool, default `true`: push when the guardian verifies a link. Server side comes later. */
        const val notifyLinkVerified = "notify.linkVerified"
        /** Android only: when the Shoo add-on in Firefox last received this session (`AddonBridge`). */
        const val firefoxLinkedAt = "firefox.linkedAt"
    }

    /** Heartbeat older than this means the extension is treated as Off (seconds, 24 h). */
    const val extensionActiveWindowSeconds: Long = 60L * 60 * 24
}

/** iOS `UserMode` (ShooShared/AppGroup.swift). */
enum class UserMode(val rawValue: String) {
    GUARDIAN("guardian"),
    PROTECTED("protected");

    companion object {
        fun from(raw: String?): UserMode? = entries.firstOrNull { it.rawValue == raw }
    }
}

// SharedPreferences has no Date and no "object" (any type) read: these keep the Swift `as? Bool` / `as? Int` rules.

internal fun SharedPreferences.optBoolean(key: String): Boolean? = all[key] as? Boolean

internal fun SharedPreferences.optInt(key: String): Int? = when (val value = all[key]) {
    is Int -> value
    is Long -> value.toInt()
    else -> null
}

internal fun SharedPreferences.optInstant(key: String): java.time.Instant? =
    (all[key] as? Long)?.let(java.time.Instant::ofEpochMilli)
