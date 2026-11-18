package com.shoo.app.notify

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import com.shoo.app.MainActivity
import com.shoo.app.R
import com.shoo.app.ShooApp
import com.shoo.app.app.AppConfig
import com.shoo.app.app.AppSettings
import com.shoo.app.data.ApiClient
import com.shoo.app.data.ApiRepository
import com.shoo.app.data.ScanOwnerFilter
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ScanStatus
import com.shoo.app.data.SessionStore
import com.shoo.app.data.UserMode
import com.shoo.app.support.Log
import com.shoo.app.support.NotificationRouter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Guardian notifications on Android (PORTING.md: APNs push → polling + local notifications, until FCM exists).
 * The backend pushes through APNs only, so the app asks `GET /scans?owner=family` about every 15 minutes
 * (JobScheduler's floor) and posts a local notification for each new warned or blocked page of a family member.
 * Tapping it opens Detail (`AppEnvironment.openPush`, GD-06), like a tapped push on iOS.
 *
 * Scheduled by `AppEnvironment.registerForPushIfAllowed` (iOS: `registerForRemoteNotifications`): a Guardian with
 * notifications allowed. It reads the session itself, so it also runs when the app is not open.
 */
class GuardianCheckJob : JobService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onStartJob(params: JobParameters): Boolean {
        scope.launch {
            try {
                check(applicationContext)
            } catch (error: Exception) {
                Log.app.error("Guardian check failed", error)
            }
            jobFinished(params, false)
        }
        return true
    }

    override fun onStopJob(params: JobParameters) = true

    companion object {
        private const val JOB_ID = 4201
        private const val CHANNEL = "family"
        private const val PREFS = "shoo.notify"
        /** Epoch ms of the newest family scan already notified. */
        private const val LAST_NOTIFIED_AT = "notify.lastScanAt"

        fun createChannel(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, context.getString(R.string.notify_channel), NotificationManager.IMPORTANCE_HIGH),
            )
        }

        /** A Guardian with a real session: schedule; anyone else (demo, Debug fixtures, Protected): cancel. Safe to call often. */
        fun sync(context: Context) {
            val app = context.applicationContext
            val scheduler = app.getSystemService(JobScheduler::class.java) ?: return
            val settings = AppSettings(app)
            val wanted = settings.mode == UserMode.GUARDIAN && !settings.demoMode && SessionStore.create(app).deviceId != null
            if (!wanted) return scheduler.cancel(JOB_ID)
            if (scheduler.getPendingJob(JOB_ID) != null) return
            scheduler.schedule(
                JobInfo.Builder(JOB_ID, ComponentName(app, GuardianCheckJob::class.java))
                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                    .setPeriodic(15 * 60 * 1000L)
                    .setPersisted(false)
                    .build(),
            )
        }

        suspend fun check(context: Context) {
            val app = context.applicationContext
            val settings = AppSettings(app)
            // The family's sites go to the Guardian with Family mode on (contracts/api.md "Push payloads").
            if (settings.mode != UserMode.GUARDIAN || settings.demoMode || !settings.familyModeOn) return
            val session = SessionStore.create(app)
            val deviceId = session.deviceId ?: return
            if (session.token == null) return
            // A 401 here only stops this check; the app shows "Session expired" when it next opens.
            val repository = ApiRepository(ApiClient(AppConfig.apiBaseURL, token = { session.readToken() }), session)
            val items = repository.scans(ScanOwnerFilter.Family, status = null, cursor = null).items
                .filter { it.ownerDeviceId != deviceId }
            val newest = items.maxOfOrNull { it.detectedAt } ?: return
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val since = prefs.getLong(LAST_NOTIFIED_AT, -1L)
            prefs.edit().putLong(LAST_NOTIFIED_AT, newest.toEpochMilli()).apply()
            if (since < 0) return // first run: remember where we are, don't flood with history
            val localized = localizedContext(app, settings)
            items.filter { it.detectedAt.toEpochMilli() > since }.take(3).forEach { scan -> notify(app, localized, scan) }
            // The page under the notification reloads too, when Shoo is open (QA 2026-11-11 #4).
            (app as? ShooApp)?.environmentOrNull?.let { env -> env.scope.launch { env.pushArrivedWhileOpen() } }
        }

        /** The app language (PF-01), not the phone's: res/values is Bahasa Indonesia, res/values-en English. */
        private fun localizedContext(context: Context, settings: AppSettings): Context {
            val configuration = Configuration(context.resources.configuration)
            configuration.setLocale(settings.language.locale)
            return context.createConfigurationContext(configuration)
        }

        private fun notify(context: Context, localized: Context, scan: ScanResult) {
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) return
            val id = scan.id.hashCode()
            // An unknown status (#493) reads no safer than a warning.
            val title = localized.getString(
                if (scan.status == ScanStatus.BLOCKED) R.string.notify_blocked_title else R.string.notify_warning_title,
                scan.ownerName,
            )
            val open = PendingIntent.getActivity(
                context, id,
                Intent(context, MainActivity::class.java)
                    .setAction(NotificationRouter.ACTION_PUSH)
                    .putExtra(NotificationRouter.SCAN_ID, scan.id)
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val notification = Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_shield)
                .setContentTitle(title)
                .setContentText("${scan.domain} · ${scan.score}%")
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
            context.getSystemService(NotificationManager::class.java)?.notify(id, notification)
        }
    }
}
