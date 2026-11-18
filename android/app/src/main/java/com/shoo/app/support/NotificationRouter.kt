package com.shoo.app.support

import android.app.NotificationManager
import android.content.Context
import com.shoo.app.data.ApiClient

/**
 * GD-06: what a notification opens, and a push token as the backend stores it. Pure, so tests cover every payload.
 * Links (`shoo://scan/{id}`, `shoo://activity`, `shoo://join`) are parsed by `DeepLink`.
 *
 * Android: no APNs. `GuardianCheckJob` posts local notifications whose tap intent carries [ACTION_PUSH] and the
 * `scanId` extra, the same payload key as the contract push (`{ "aps": …, "scanId": "…" }`).
 */
object NotificationRouter {
    /** Intent action of a tapped Shoo notification (`MainActivity` → `AppEnvironment.openPush`). */
    const val ACTION_PUSH = "com.shoo.app.action.PUSH"
    const val SCAN_ID = "scanId"

    /** `scanId` of a push, only when it is a plain id (T15): it ends up in a URL path (`GET /scans/{id}`). */
    fun scanId(userInfo: Map<String, Any?>): String? {
        val id = userInfo[SCAN_ID] as? String ?: return null
        return if (ApiClient.isPlainSegment(id)) id else null
    }

    /** A device token as lowercase hex (iOS: for `PATCH /devices/me { apnsToken }`; unused until FCM exists). */
    fun hex(token: ByteArray): String = token.joinToString("") { "%02x".format(it.toInt() and 0xFF) }
}

/**
 * P13: notifications already in the shade carry a family member's name and site. They go when the data they point
 * at goes (delete, remove, disconnect, session end, D-alief-C18).
 */
object DeliveredPushes {
    fun clear(context: Context) {
        try {
            context.getSystemService(NotificationManager::class.java)?.cancelAll()
        } catch (_: RuntimeException) {
        }
    }
}
