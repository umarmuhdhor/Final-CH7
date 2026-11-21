package com.shoo.app.support

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import com.shoo.app.data.UserMode
import kotlinx.coroutines.CompletableDeferred

/** The app's view of the notification permission (ON-05). */
enum class NotificationAuthorization {
    NOT_DETERMINED,
    DENIED,
    AUTHORIZED,
}

/**
 * Asks for notifications just in time (SECURITY §3 P7). An interface so tests and UI tests never see a system
 * prompt.
 */
interface NotificationPermission {
    suspend fun status(): NotificationAuthorization

    /** Shows the system prompt (Android 13+, while Android still offers it) and returns the answer. */
    suspend fun request(): NotificationAuthorization
}

/**
 * The real permission: `POST_NOTIFICATIONS` on Android 13+, the app's notification switch before that.
 * iOS `UNUserNotificationCenter`. Android has no "not asked yet" state of its own, so the first ask is
 * remembered (`notify.asked`): before it the answer is [NotificationAuthorization.NOT_DETERMINED].
 *
 * The prompt needs an Activity: `MainActivity` hands one in with [attach].
 */
class SystemNotificationPermission(context: Context) : NotificationPermission {
    private val context = context.applicationContext
    private val prefs = this.context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    override suspend fun status(): NotificationAuthorization {
        val manager = context.getSystemService(NotificationManager::class.java)
        val enabled = manager?.areNotificationsEnabled() ?: false
        if (Build.VERSION.SDK_INT < 33) {
            return if (enabled) NotificationAuthorization.AUTHORIZED else NotificationAuthorization.DENIED
        }
        val granted = context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        return when {
            granted && enabled -> NotificationAuthorization.AUTHORIZED
            granted -> NotificationAuthorization.DENIED
            prefs.getBoolean(KEY_ASKED, false) -> NotificationAuthorization.DENIED
            else -> NotificationAuthorization.NOT_DETERMINED
        }
    }

    override suspend fun request(): NotificationAuthorization {
        if (Build.VERSION.SDK_INT >= 33 && status() == NotificationAuthorization.NOT_DETERMINED) {
            val ask = requester
            if (ask == null) {
                Log.app.error("Notification permission request failed", "no activity")
            } else {
                prefs.edit().putBoolean(KEY_ASKED, true).apply()
                ask()
            }
        }
        return status()
    }

    companion object {
        private const val PREFS = "shoo.notifications"
        private const val KEY_ASKED = "notify.asked"

        /** Launches the system prompt and waits for the answer. Set by the visible Activity. */
        @Volatile
        private var requester: (suspend () -> Boolean)? = null

        /**
         * `MainActivity.onCreate`: `launch` starts its `ActivityResultLauncher` for `POST_NOTIFICATIONS`; the
         * launcher's callback calls [answer].
         */
        fun attach(launch: () -> Unit) {
            requester = {
                val answer = CompletableDeferred<Boolean>()
                pending?.complete(false)
                pending = answer
                launch()
                answer.await()
            }
        }

        fun detach() {
            requester = null
            pending?.complete(false)
            pending = null
        }

        @Volatile
        private var pending: CompletableDeferred<Boolean>? = null

        fun answer(granted: Boolean) {
            pending?.complete(granted)
            pending = null
        }
    }
}

/** Fixed answer for UI tests and screenshots (`-UITestNotifications granted|denied`, Debug only). */
class FixedNotificationPermission(private val answer: NotificationAuthorization) : NotificationPermission {
    private var asked = false

    override suspend fun status(): NotificationAuthorization = if (asked) answer else NotificationAuthorization.NOT_DETERMINED

    override suspend fun request(): NotificationAuthorization {
        asked = true
        return answer
    }
}

/** The small "Notifications are off" banner on Home (ON-05). */
object NotificationReminder {
    /**
     * Guardian mode gets the pushes (contracts/api.md): the family's sites with Family mode on, its own blocked and
     * dangerous sites in Pribadi. Its alert says which (GuardianShieldView).
     */
    fun isShown(status: NotificationAuthorization, mode: UserMode?): Boolean =
        mode == UserMode.GUARDIAN && status != NotificationAuthorization.AUTHORIZED
}
