package com.shoo.app.features.shield

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import com.shoo.app.app.LaunchSplashPhase
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.support.Log
import com.shoo.app.support.NotificationAuthorization
import com.shoo.app.support.NotificationReminder
import com.shoo.app.support.t
import kotlinx.coroutines.launch

/**
 * Guardian Shield (GD-01/GD-02): Family mode off → own Home, on → the family's Home (GD-03).
 * The toggle only changes this view; the guardian's Firefox stays protected either way.
 */
@Composable
fun GuardianShieldView(modifier: Modifier = Modifier) {
    val env = LocalAppEnvironment.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sceneActive = rememberShieldSceneActive()
    var notificationStatus by remember { mutableStateOf(NotificationAuthorization.AUTHORIZED) }
    var isReminderPresented by remember { mutableStateOf(false) }

    Box(modifier) {
        GuardianHomeView(
            repository = env.repository,
            settings = env.settings,
            scope = if (env.settings.familyModeOn) GuardianHomeModel.Scope.FAMILY else GuardianHomeModel.Scope.PERSONAL,
            extensionStatus = env.extensionStatus,
            // One `GET /devices/me` per foreground, shared with `sceneBecameActive` (OPT-06).
            profile = { env.foregroundProfile() },
            onVerdictSaved = { env.verdictSaves += 1 },
        )
    }

    // In use, and the launch splash (ON-01) is gone: the popup never covers the brand.
    // PR-03: not over the join sheet an invite link opens after onboarding; the reminder comes once it is closed.
    val canRemind = sceneActive && env.launchSplash == LaunchSplashPhase.DONE &&
        !env.router.isJoinFamilyPresented && !env.router.isConnectPresented
    LaunchedEffect(canRemind) {
        if (!canRemind) return@LaunchedEffect
        notificationStatus = env.notifications.status()
        isReminderPresented = NotificationReminder.isShown(notificationStatus, env.settings.mode) &&
            !env.router.notificationReminderShown
    }
    ShieldOnChange(isReminderPresented) { _, isPresented ->
        if (isPresented) env.router.notificationReminderShown = true
    }

    // Push alerts are how the guardian hears about the family: remind while they are off (D-alief-A08).
    // A popup once per launch, so it never takes room on Home (QA-A P2-7).
    if (isReminderPresented) {
        AlertDialog(
            onDismissRequest = { isReminderPresented = false },
            title = { Text(t("Notifications are off")) },
            text = {
                // Pribadi (Family mode off) protects nobody: its pushes are about its own blocked sites.
                Text(
                    t(
                        if (env.settings.familyModeOn) {
                            "You won't hear when your family is at risk."
                        } else {
                            "You won't hear when Shoo blocks a dangerous site."
                        },
                    ),
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        isReminderPresented = false
                        // Never asked yet: the system prompt. Denied: only Settings can change it.
                        if (notificationStatus == NotificationAuthorization.NOT_DETERMINED) {
                            scope.launch {
                                notificationStatus = env.notifications.request()
                                env.registerForPushIfAllowed()
                            }
                        } else {
                            openNotificationSettings(context)
                        }
                    },
                    modifier = Modifier.testTag("reminder.turnOn"),
                ) { Text(t("Turn on")) }
            },
            dismissButton = {
                TextButton(
                    onClick = { isReminderPresented = false },
                    modifier = Modifier.testTag("reminder.notNow"),
                ) { Text(t("Not now")) }
            },
        )
    }
}

/** iOS `UIApplication.openNotificationSettingsURLString`: this app's notification settings. */
private fun openNotificationSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
        context.startActivity(intent)
    } catch (error: Exception) {
        Log.ui.error("Opening notification settings failed", error)
    }
}
