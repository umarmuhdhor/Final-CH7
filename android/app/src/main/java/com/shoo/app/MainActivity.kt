package com.shoo.app

import android.Manifest
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import com.shoo.app.app.AppEnvironment
import com.shoo.app.app.RootView
import com.shoo.app.support.NotificationRouter
import com.shoo.app.support.SystemNotificationPermission
import kotlinx.coroutines.launch

/**
 * The one Activity (iOS `WindowGroup { RootView() }`). Links (`shoo://…`, `https://<host>/j/<code>`) arrive as
 * Intents (iOS `.onOpenURL`), notification taps as [NotificationRouter.ACTION_PUSH] (iOS `didReceive`), and
 * `onResume` is iOS `scenePhase == .active`.
 */
class MainActivity : ComponentActivity() {
    private lateinit var env: AppEnvironment

    private val notificationPrompt =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            SystemNotificationPermission.answer(granted)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        env = (application as ShooApp).environment(launchArguments(intent))
        SystemNotificationPermission.attach { notificationPrompt.launch(Manifest.permission.POST_NOTIFICATIONS) }
        // A relaunch after the process died restores the screen from state, not from the Intent again.
        if (savedInstanceState == null) handle(intent)
        setContent { RootView(env) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    override fun onResume() {
        super.onResume()
        // An invite code survives the trip to Settings (ON-04), but not past the life of a code (PR-03).
        env.router.dropExpiredInvite()
        env.scope.launch { env.sceneBecameActive() }
    }

    override fun onDestroy() {
        if (isFinishing) SystemNotificationPermission.detach()
        super.onDestroy()
    }

    private fun handle(intent: Intent?) {
        intent ?: return
        if (intent.action == NotificationRouter.ACTION_PUSH) {
            val scanId = NotificationRouter.scanId(mapOf(NotificationRouter.SCAN_ID to intent.getStringExtra(NotificationRouter.SCAN_ID)))
            env.openPush(scanId)
            return
        }
        intent.data?.let { env.open(it) }
    }

    /** Debug builds: string extras stand in for iOS launch arguments (`--es -mock.scenario figma`). */
    private fun launchArguments(intent: Intent?): Map<String, String> {
        if (!BuildConfig.DEBUG) return emptyMap()
        val extras = intent?.extras ?: return emptyMap()
        return extras.keySet().mapNotNull { key ->
            @Suppress("DEPRECATION")
            val value = extras.get(key)?.toString()
            value?.let { key to it }
        }.toMap()
    }
}
