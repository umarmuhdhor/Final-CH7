package com.shoo.app.app

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import com.shoo.app.BuildConfig
import com.shoo.app.data.ApiClient
import com.shoo.app.data.ApiRepository
import com.shoo.app.data.APIErrorCode
import com.shoo.app.data.AppGroup
import com.shoo.app.data.CheckStats
import com.shoo.app.data.DeviceProfile
import com.shoo.app.data.DeviceRegistration
import com.shoo.app.data.DeviceUpdate
import com.shoo.app.data.ExtensionStatus
import com.shoo.app.data.GuardianInfo
import com.shoo.app.data.InMemoryCaches
import com.shoo.app.data.LinkedAccountSettings
import com.shoo.app.data.MockRepository
import com.shoo.app.data.ProtectedSwitch
import com.shoo.app.data.RepositoryError
import com.shoo.app.data.SessionStore
import com.shoo.app.data.ShooRepository
import com.shoo.app.data.UserMode
import com.shoo.app.notify.GuardianCheckJob
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.DeliveredPushes
import com.shoo.app.support.DeviceInfo
import com.shoo.app.support.FixedNotificationPermission
import com.shoo.app.support.Log
import com.shoo.app.support.NotificationAuthorization
import com.shoo.app.support.NotificationPermission
import com.shoo.app.support.NotificationRouter
import com.shoo.app.support.SystemNotificationPermission
import com.shoo.app.support.isCancellation
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject

/** Every screen reads the environment from here: `val env = LocalAppEnvironment.current`. Provided by `RootView`. */
val LocalAppEnvironment = staticCompositionLocalOf<AppEnvironment> { error("no env") }

/** ON-01: the brand splash over the first screen (`LaunchSplash`, features/onboarding). */
enum class LaunchSplashPhase {
    SHOWING,
    /** Fading out over the screen that is already there. */
    LEAVING,
    DONE,
}

/**
 * Dependencies every screen reads (iOS `@Environment(AppEnvironment.self)`). Compose state where SwiftUI observes,
 * plain fields where Swift has `@ObservationIgnored`. Its methods run on the main thread, like Swift's `@MainActor`;
 * `scope` (main dispatcher) runs the work they start on their own.
 */
class AppEnvironment(
    repository: ShooRepository,
    val settings: AppSettings,
    val router: Router = Router(),
    val notifications: NotificationPermission = FixedNotificationPermission(NotificationAuthorization.DENIED),
    session: SessionStore? = null,
    /** The App Group prefs (`AppGroup.defaults`): `LinkedAccountSettings(env.appGroupDefaults)`,
     * `CheckStats.current(env.appGroupDefaults)`. In memory in previews and tests. */
    val appGroupDefaults: SharedPreferences = InMemoryPreferences(),
    /** Shoo's add-on Active/Off right now (Firefox installed + linked, see `ExtensionStatus`). */
    val extensionStatus: suspend () -> ExtensionStatus = { ExtensionStatus.current(appGroupDefaults) },
    /** iOS: asks for the APNs token. Android: (re)schedules `GuardianCheckJob`, the polling stand-in for pushes. */
    private val registerForPush: () -> Unit = {},
    /** Runs the work the environment starts itself (invite check, shared profile call). Main thread in the app. */
    val scope: CoroutineScope = MainScope(),
    /** iOS `DeliveredPushes.clear()`: notifications in the shade go with the data they point at. */
    private val clearDeliveredPushes: () -> Unit = {},
    /** Fixture reader for the demo's `MockRepository` (`MockRepository.assetFixtures`). */
    private val fixtures: (String) -> String? = { null },
) {
    var repository: ShooRepository by mutableStateOf(repository)
        private set

    /** Keystore token + App Group keys. null with `MockRepository` (previews, UI tests, demo): fixtures never touch
     * the real App Group. */
    var session: SessionStore? = session
        private set

    /** The server no longer knows our token (401), or the Keystore has none. `RootView` then shows "Session expired"
     * (fase 13 step 4). */
    var sessionExpired by mutableStateOf(false)
        private set

    /** Verdicts the server confirmed in this launch, from Detail and Home (fase 27 K8). Activity reloads when it shows
     * again and this changed since its last load: its rows are a separate list. */
    var verdictSaves by mutableIntStateOf(0)

    /** Members the guardian disconnected in this launch (Member detail). Family Activity reloads when it shows again and
     * this changed: its rows and person picker must not keep a removed member's sites and name. */
    var familyChanges by mutableIntStateOf(0)

    private var isSyncingForeground = false

    /** PR-03: the server check behind the latest invite link (`routeInvite`). A newer link cancels it. */
    var inviteTask: Job? = null
        private set

    /** PR-03: onboarding ended with an invite code waiting. The tabs open its sheet once they are on screen
     * (`presentInviteAfterOnboarding`): a sheet asked for before then is lost in the cross-fade. */
    var opensInviteAfterOnboarding = false
        private set

    /** The token the server has (or is getting) from this launch: the same one is not sent twice. */
    private var sentPushToken: String? = null

    /** PF-01: model and OS version go to the server once per launch. */
    private var sentDeviceInfo = false

    /** Bumped by `register`: a token send that started for the old device can't mark the new one as sent. */
    private var pushTokenEpoch = 0

    /** While `becomeProtected` runs, the server may already have swapped the device: a 401 for the old token is the old
     * session's, not this one's (fase 27h, F-A3). A count, so overlapping calls each hold it. */
    private var switchingSessions = 0

    /** OPT-06: the last `GET /devices/me` asked by the foreground sync or by Home, for the other side to share. */
    private var profileCall: ProfileCall? = null

    /** UI tests (`-UITestReduceMotion YES`, Debug only): no endless shield animation keeping the app busy. */
    var reducesMotionForUITests = false
        private set

    /** Builds the real backend when the demo ends. null in previews and tests that don't leave a demo. */
    internal var makeLiveBackend: (() -> Pair<ShooRepository, SessionStore>)? = null

    /** ON-01: the brand splash over the first screen (`LaunchSplash`). It lives as long as the process, so a cold launch
     * shows it and a return from the background does not. */
    var launchSplash by mutableStateOf(LaunchSplashPhase.SHOWING)

    /** UI tests: how long the splash stays before it fades (`-UITestSplashSeconds`, Debug only). */
    var launchSplashHold: Double? = null
        private set

    /** Bumped by every notification that arrives while the tabs are showing. Guardian Home reloads on it, so the banner
     * and the page under it tell the same story without a pull-to-refresh (QA 2026-11-11 #4). */
    var pushesWhileOpen by mutableIntStateOf(0)
        private set

    /** A device registered before the question existed answers it before anything else (Apple 5.1.2(i)). Only once
     * onboarding is done: during onboarding the invite path asks before Connect and ON-04 has its checkbox, so this
     * screen must not replace the flow halfway (fase 27d, F-A1). */
    val needsDataConsent: Boolean
        get() = settings.mode != null && settings.onboardingCompleted && settings.dataConsent == null && !sessionExpired

    /** The local part of "this device is deleted on the server" (P13), shared by "Delete my data" and cancelling a
     * failed invite join: the Protected switches and the checked-pages counter. The session is already empty
     * (`ApiRepository.deleteMe`); the caller resets the settings its own way. */
    fun forgetDeletedDevice(linked: LinkedAccountSettings) {
        linked.clear()
        CheckStats.clear(appGroupDefaults)
    }

    /** Onboarding, the same question for an existing device, and the switch in Profile. */
    fun setDataConsent(consent: DataConsent) {
        settings.dataConsent = consent
        session?.setOnlineCheck(allowed = consent == DataConsent.GRANTED)
    }

    /** ON-03: registers the device and saves the mode for good. The repository then answers as this device (the mock
     * adopts the name, avatar and mode; the API knows them from the token). */
    suspend fun register(name: String, mode: UserMode, avatarId: String? = null): DeviceRegistration {
        deletePreviousInstall()
        val registration = repository.registerDevice(name = name, mode = mode, avatarId = avatarId, apnsToken = null)
        // Keystore + App Group before the mode is saved: a relaunch never finds a mode without a session.
        try {
            session?.save(registration, name = name, mode = mode)
        } catch (error: Exception) {
            // Keystore refused: no half session. The unused device on the server holds only a name and expires with
            // the inactive-device cleanup (handoff fase 13).
            session?.clear()
            Log.app.error("Session save failed", error)
            throw RepositoryError.Network
        }
        settings.chooseMode(mode)
        // A new device on the server: its first token must be sent, and its model, OS version and time zone too
        // (a second registration in one launch, fase 27h F-A8).
        sentPushToken = null
        sentDeviceInfo = false
        pushTokenEpoch += 1
        // `POST /devices` has no language; the server defaults to English (pushes are localized, D-alief-05).
        if (settings.language != AppLanguage.ENGLISH) {
            try {
                repository.updateMe(DeviceUpdate(language = settings.language.code))
            } catch (error: Exception) {
                // Profile sends it again when `me().language` differs (D-alief-A19).
                Log.app.error("Language sync after registration failed", error)
            }
        }
        return registration
    }

    /**
     * A token with no mode saved: Shoo was installed again over data the reinstall kept. That old device is still on
     * the server, linked to the family, shown as "Aktif" and holding one of the 3 places (QA 2026-11-11 #6). It goes
     * first (`DELETE /devices/me` with its own token, as "Delete my data" would). Best effort: if it fails, the new
     * device registers anyway. Android: `allowBackup="false"` and the Keystore key go with an uninstall, so this
     * mostly finds nothing.
     */
    private suspend fun deletePreviousInstall() {
        val session = session ?: return
        if (settings.mode != null || session.token == null) return
        Log.app.info("Token from an earlier install found: deleting that device")
        try {
            repository.deleteMe()
        } catch (error: Exception) {
            // Already gone (`deleteMe` cleared the session) or the server refused: the new token replaces it.
            session.clear()
            if (error.isCancellation) return
            Log.app.error("Deleting the earlier install failed", error)
        }
    }

    /**
     * Every time the app comes to the foreground (contracts/api.md `extensionLastSeenAt`): tells the server the
     * extension's last sign of life (GD-03 "Not connected"; none while this app shows Off because the browser's access
     * is narrowed or Shoo is switched off), then refreshes name + guardian in the App Group from `GET /devices/me`.
     */
    suspend fun sceneBecameActive(now: Instant = Instant.now()) {
        // One sync at a time: quick background/foreground flips don't stack requests.
        if (settings.mode == null || sessionExpired || isSyncingForeground) return
        isSyncingForeground = true
        try {
            val status = extensionStatus()
            // X-01: Shoo may read only some sites, or it is switched off, so this app shows Off. The Guardian must not
            // see better than that: the server would call the member "connected".
            val lastSeen: Instant? = when {
                status is ExtensionStatus.Off && (
                    status.reason == ExtensionStatus.OffReason.SOME_SITES_ONLY ||
                        status.reason == ExtensionStatus.OffReason.SWITCHED_OFF
                    ) -> null
                else -> status.lastSeen
            }
            // PF-01: the guardian's member detail shows the model and OS version; sent once per launch. The time zone
            // goes with it: quiet hours and the weekly summary use the phone's local time.
            val device = if (sentDeviceInfo) null else Triple(DeviceInfo.modelName, DeviceInfo.osMajorVersion, DeviceInfo.timeZone)
            if (lastSeen != null || device != null) {
                try {
                    repository.updateMe(
                        DeviceUpdate(
                            // The server refuses times in the future (clock changes).
                            extensionLastSeenAt = lastSeen?.let { if (it.isAfter(now)) now else it },
                            deviceModel = device?.first,
                            osVersion = device?.second,
                            timeZone = device?.third,
                        ),
                    )
                    if (device != null) sentDeviceInfo = true
                } catch (error: Exception) {
                    if (error.isCancellation) return
                    Log.app.error("Extension heartbeat sync failed", error)
                }
            }
            try {
                sharedProfile(forSync = true)
            } catch (error: Exception) {
                if (error.isCancellation) return
                Log.app.error("Profile refresh failed", error)
            }
            registerForPushIfAllowed()
        } finally {
            isSyncingForeground = false
        }
    }

    /** `GET /devices/me` for Home (OPT-06, fase 28i K11). Coming to the foreground, `sceneBecameActive` and Home both
     * need it, for the same answer: Home takes the sync's call (still running, or answered moments ago) and the sync
     * takes Home's. One request per foreground instead of two. */
    suspend fun foregroundProfile(): DeviceProfile = sharedProfile(forSync = false)

    /** The other side's call is taken once, if it started under the same token and repository less than
     * `profileShareWindowSeconds` ago. A second ask from the same side (pull to refresh, the next foreground) asks anew. */
    private suspend fun sharedProfile(forSync: Boolean, now: Instant = Instant.now()): DeviceProfile {
        val token = session?.token
        val source = repository
        val shared = profileCall
        val task: Deferred<DeviceProfile>
        val age = shared?.let { Duration.between(it.startedAt, now).toMillis() }
        if (shared != null && !shared.taken && shared.forSync != forSync && shared.token == token &&
            shared.source === source && age != null && age >= 0 && age < profileShareWindowSeconds * 1000
        ) {
            shared.taken = true
            task = shared.task
        } else {
            task = scope.async { source.me() }
            profileCall = ProfileCall(task = task, token = token, source = source, startedAt = now, forSync = forSync)
        }
        val profile = try {
            task.await()
        } catch (error: CancellationException) {
            // This asker stopped; the shared call goes on for the other side unless it was cancelled itself.
            if (task.isCancelled && profileCall?.task === task) profileCall = null
            throw error
        } catch (error: Exception) {
            // A failed call is never handed on: the next ask tries anew.
            if (profileCall?.task === task) profileCall = null
            throw error
        }
        // The shared call is not cancelled with one asker; this asker still stops like a cancelled request.
        currentCoroutineContext().ensureActive()
        return profile
    }

    /** A registered device whose token is gone (the Keystore key no longer opens it) can't call the API. The App Group
     * copy is not trusted then (P4). */
    fun checkStoredSession() {
        val session = session ?: return
        val token = try {
            session.readToken()
        } catch (_: Exception) {
            // Keystore not readable right now: decide on the next launch.
            return
        }
        if (token == null) {
            // Never leave a session the app can't use in the App Group, registered or not.
            session.clear()
            if (settings.mode != null) markSessionExpired()
            return
        }
        if (settings.mode != null) session.writeBaseURLs()
    }

    /** A 401 for `usedToken`. Ignored when the session has moved on since that request left (restart, new
     * registration): only the current token can expire. Also ignored while `becomeProtected` runs. */
    fun handleUnauthorized(usedToken: String) {
        if (switchingSessions != 0) return
        val current = try {
            session?.readToken()
        } catch (_: Exception) {
            null
        }
        if (current == null || current != usedToken) return
        markSessionExpired()
    }

    fun markSessionExpired() {
        // A dead token goes in every case; the screen only for a registered device.
        session?.clear()
        if (settings.mode == null || sessionExpired) return
        Log.app.info("Session expired")
        sessionExpired = true
        clearDeliveredPushes()
    }

    /** "Try the demo" (App Review, Guideline 2.1): a family of fixtures on this phone. Nothing is registered and
     * nothing leaves the phone. Offered only before this device has a mode, so no real session is replaced. */
    fun startDemo() {
        if (settings.mode != null) return
        repository = MockRepository(mode = UserMode.GUARDIAN, fixtures = fixtures)
        session = null
        settings.enterDemo()
    }

    /** Back to a fresh install on the real backend. */
    fun leaveDemo() {
        if (!settings.demoMode) return
        router.reset()
        settings.reset()
        // The demo's fixtures have no favicon links today; emptied anyway so nothing from it stays (P13).
        InMemoryCaches.clear()
        makeLiveBackend?.invoke()?.let { (liveRepository, liveSession) ->
            repository = liveRepository
            session = liveSession
        }
    }

    /** "Start again" on the Session expired screen: a fresh install (onboarding from the start). */
    fun restartOnboarding() {
        session?.clear()
        router.reset()
        // The old account's banner goes; a code from a link that came while "Session expired" showed still waits.
        router.inviteNotice = null
        settings.reset()
        sessionExpired = false
        clearDeliveredPushes()
    }

    /** "Delete my data" is done (the device is gone on the server): back to onboarding. Profile calls it right before
     * `settings.reset()`. */
    fun returnToOnboardingAfterDelete() {
        leaveDemo()
        router.reset()
        router.forgetInvite()
        // A 401 for another request with the same token can land before the delete answers (fase 27h, F-N7): the
        // device is gone on purpose, so onboarding shows, not "Session expired".
        sessionExpired = false
        clearDeliveredPushes()
    }

    /** Family mode on (Pribadi → Guardian). The first time, Figma "To be guardian" shows first and its "Mulai" turns it
     * on (`startGuardian`). */
    fun requestFamilyMode() {
        if (settings.mode != UserMode.GUARDIAN || settings.familyModeOn) return
        if (settings.guardianIntroSeen) {
            settings.familyModeOn = true
        } else {
            router.isGuardianIntroPresented = true
        }
    }

    /** "Mulai" on Figma "To be guardian". */
    fun startGuardian() {
        settings.guardianIntroSeen = true
        settings.familyModeOn = true
        router.isGuardianIntroPresented = false
    }

    /**
     * PF-01 "Punya kode undangan?": a guardian without members joins another family. The server replaces this device
     * with a protected one; its session and the mode take over here at once (the old token is dead). The caller closes
     * its screens afterwards (`router.reset()`). Throws the join errors (code, full family) and `has_members`.
     */
    suspend fun becomeProtected(code: String, name: String): GuardianInfo {
        switchingSessions += 1
        try {
            val result: ProtectedSwitch = try {
                repository.becomeProtected(code)
            } catch (error: RepositoryError) {
                // This request's own 401: the token was already dead before the switch, and nothing replaces it.
                if (error.apiCode == APIErrorCode.unauthorized) markSessionExpired()
                throw error
            }
            try {
                session?.save(result.registration, name = name, mode = UserMode.PROTECTED)
            } catch (error: Exception) {
                // The old device is already gone on the server: without the new token the app cannot go on.
                Log.app.error("Session save failed", error)
                markSessionExpired()
                throw RepositoryError.Network
            }
            session?.setGuardian(result.guardian)
            settings.becameProtected()
            // A new device on the server: send the push token and device info again.
            sentPushToken = null
            sentDeviceInfo = false
            pushTokenEpoch += 1
            clearDeliveredPushes()
            registerForPushIfAllowed()
            return result.guardian
        } finally {
            switchingSessions -= 1
        }
    }

    /**
     * Deep links (contracts/app-group-keys.md). A join link only fills in the code: joining still asks for a tap (T11).
     * Every mode gets its invite (PR-03, BH-10): `routeInvite` decides between the join sheet, Connect and a Home card.
     * `scan` opens Detail, `activity` the Activity tab; an unknown link lands on Shield. iOS `RootView.onOpenURL`.
     */
    fun open(url: String) {
        when (val link = DeepLink.from(url)) {
            is DeepLink.Join -> {
                router.pendingJoinCode = link.code
                // Not registered or still onboarding: the join sheet opens with the code once onboarding is done
                // (`finishOnboarding`). "Session expired": the code just waits.
                if (!isInMainScreen) return
                inviteTask?.cancel()
                inviteTask = scope.launch { routeInvite() }
            }
            is DeepLink.Scan -> if (isInMainScreen) router.openDetail(link.id)
            DeepLink.Activity -> if (isInMainScreen) router.openActivity()
            // A link we don't know: Shield. Onboarding or "Session expired" on screen: nothing to open yet.
            DeepLink.Unknown -> if (isInMainScreen) router.reset()
        }
    }

    /** `MainActivity`: the link an Intent carries (`intent.data`). */
    fun open(uri: android.net.Uri) = open(uri.toString())

    /**
     * PR-03, an invite link while the tabs show (Figma "Flow · Protected buka link undangan"). An open join sheet just
     * gets the new code. Otherwise the server decides what Home says: a guardian still protecting someone can't join
     * (`has_members`), a protected phone with a guardian can't either, and anyone else gets the invite banner (Pribadi)
     * or Connect (Protected without a guardian). Offline: the banner or Connect, and the join itself says why it can't.
     */
    suspend fun routeInvite() {
        if (router.isConnectPresented || router.isJoinFamilyPresented) return
        router.inviteNotice = null
        when (settings.mode) {
            UserMode.GUARDIAN -> {
                val members = try {
                    repository.familyMembers()
                } catch (_: Exception) {
                    null
                }
                if (!currentCoroutineContext().isActive || router.pendingJoinCode == null) return
                showHomeForInvite()
                if (!members.isNullOrEmpty()) {
                    router.dismissInviteNotice()
                    router.inviteNotice = InviteNotice.HasMembers
                } else {
                    router.inviteNotice = InviteNotice.Invited
                }
            }
            UserMode.PROTECTED -> {
                val guardian = try {
                    repository.me().guardian
                } catch (_: Exception) {
                    null
                }
                if (!currentCoroutineContext().isActive || router.pendingJoinCode == null) return
                if (guardian != null) {
                    showHomeForInvite()
                    router.dismissInviteNotice()
                    router.inviteNotice = InviteNotice.AlreadyProtected(guardian = guardian.name)
                } else {
                    // Already open, `ConnectSheet` picks the new code up.
                    router.showConnect()
                }
            }
            null -> Unit
        }
    }

    /** The banner shows over Home: no pushed screen, no Turn on sheet. */
    private fun showHomeForInvite() {
        router.isTurnOnPresented = false
        router.popToRoot()
        router.selectedTab = AppTab.SHIELD
    }

    /** The tabs are showing (not onboarding, not "Session expired"). */
    private val isInMainScreen: Boolean
        get() = settings.onboardingCompleted && settings.mode != null && !sessionExpired

    /** GD-06: a tapped notification. One with a usable `scanId` opens Detail in either mode. Family notifications
     * (reminder, disconnect, PF-01) carry none and open Shield. */
    fun openPush(scanId: String?) {
        if (!isInMainScreen) return
        if (scanId != null) router.openDetail(scanId) else router.reset()
    }

    /** A notification that arrives while Shoo is open: shown only where a tap can open it (C15). */
    val showsPushBanner: Boolean get() = isInMainScreen

    /** A notification arrived while Shoo is open. */
    fun pushArrivedWhileOpen() {
        if (!isInMainScreen) return
        pushesWhileOpen += 1
    }

    /**
     * ON-05 (iOS: the APNs token from `AppDelegate`). Kept for parity; Android has no caller until FCM exists, since
     * an FCM token is not an `apnsToken`.
     */
    suspend fun pushTokenReceived(token: ByteArray) {
        if (settings.mode == null || sessionExpired) return
        val hex = NotificationRouter.hex(token)
        if (hex == sentPushToken) return
        // Marked before the request: a second callback with the same token while it is in flight sends nothing.
        sentPushToken = hex
        val epoch = pushTokenEpoch
        try {
            repository.updateMe(DeviceUpdate(apnsToken = hex))
        } catch (error: Exception) {
            // Sent again on the next activation, unless a new registration has taken over meanwhile.
            if (epoch == pushTokenEpoch && sentPushToken == hex) sentPushToken = null
            if (error.isCancellation) return
            Log.app.error("Push token sync failed", error)
        }
    }

    /** iOS registers for APNs at every launch. Android: keeps the Guardian check scheduled while notifications are on. */
    suspend fun registerForPushIfAllowed() {
        if (settings.mode == null || sessionExpired) return
        if (notifications.status() != NotificationAuthorization.AUTHORIZED) return
        Log.app.info("Notification check scheduled")
        registerForPush()
    }

    /** After ON-05: the tabs replace onboarding. */
    fun finishOnboarding() {
        settings.onboardingCompleted = true
        // PR-03: an invite link opened before or during onboarding. The tabs open the join sheet with its code
        // (`presentInviteAfterOnboarding`), so the only step left is the Hubungkan tap (T11).
        router.dropExpiredInvite()
        opensInviteAfterOnboarding = router.pendingJoinCode != null
    }

    /** The tabs are on screen after onboarding: the join sheet for a waiting invite code. An older build's Protected
     * registration gets Connect. */
    fun presentInviteAfterOnboarding() {
        if (!opensInviteAfterOnboarding) return
        opensInviteAfterOnboarding = false
        router.dropExpiredInvite()
        if (router.pendingJoinCode == null) return
        when (settings.mode) {
            UserMode.GUARDIAN -> router.showJoinFamily()
            UserMode.PROTECTED -> router.showConnect()
            null -> Unit
        }
    }

    /** Android only: the `getSession` reply for the Firefox add-on (`AddonBridge`), or null before onboarding / in the
     * demo. */
    fun addonSession(): JSONObject? = session?.addonSession()

    /** Android only: `AddonBridge` handed this session to the add-on: Shoo counts as Active from now on. */
    fun addonLinked(now: Instant = Instant.now()) {
        ExtensionStatus.recordLinked(appGroupDefaults, now)
    }

    companion object {
        /** How long a profile call is shared: covers the heartbeat `PATCH` that runs before the sync's own ask. */
        const val profileShareWindowSeconds: Long = 10

        /**
         * The app at launch: `ApiRepository` against `AppConfig.apiBaseURL`. Debug builds (PORTING.md: Debug default
         * backend = mock) use the fixtures of `MockRepository` unless the launch extra `-debug.backend cloud|local`
         * picks the API. iOS launch arguments are Intent string extras here (`adb shell am start … --es -mock.scenario
         * figma`), read in Debug builds only.
         */
        fun live(context: Context, arguments: Map<String, String> = emptyMap()): AppEnvironment {
            val app = context.applicationContext
            fun value(flag: String): String? =
                if (BuildConfig.DEBUG) arguments[flag] ?: arguments[flag.removePrefix("-")] else null

            val settingsPrefs = app.getSharedPreferences(AppSettings.PREFS, Context.MODE_PRIVATE)
            if (value("-UITestReset") == "YES") AppSettings.clear(settingsPrefs)
            // iOS UserDefaults argument domain: `-settings.mode protected`, `-settings.onboardingCompleted YES`… set a
            // stored setting for this launch (QA screenshots, UI tests). Debug builds only (`value` is null in Release).
            settingsPrefs.edit().apply {
                for (key in AppSettings.Keys.all) {
                    val raw = value("-$key") ?: continue
                    when (raw) {
                        "YES", "true" -> putBoolean(key, true)
                        "NO", "false" -> putBoolean(key, false)
                        "NIL" -> remove(key)
                        else -> raw.toIntOrNull()?.takeIf { key == AppSettings.Keys.textSize }
                            ?.let { putInt(key, it) } ?: putString(key, raw)
                    }
                }
            }.commit()
            val backend = value("-debug.backend")
            if (backend == "local") AppConfig.usesLocalAPI = true
            val usesMockFixtures = BuildConfig.DEBUG &&
                (value("-UITestMock") == "YES" || (backend == null && value("-UITestMock") != "NO"))
            val settings = AppSettings(settingsPrefs)
            val usesMock = usesMockFixtures || settings.demoMode
            val appGroup = AppGroup.defaults(app)
            val fixtures = MockRepository.assetFixtures(app.assets)
            val expiry = SessionExpiry()
            val makeLiveBackend: () -> Pair<ShooRepository, SessionStore> = {
                // Live QA on a local stack: `-debug.aiBaseURL http://10.0.2.2:8788` gives the add-on layers 3–4
                // (Debug has no AI URL). `SessionStore.isAllowed` still rejects anything but HTTPS or the local host.
                val store = SessionStore.create(
                    app,
                    aiBaseURL = value("-debug.aiBaseURL") ?: AppConfig.aiBaseURL,
                    onlineCheckAllowed = settings.dataConsent == DataConsent.GRANTED,
                )
                val client = ApiClient(
                    baseURL = AppConfig.apiBaseURL,
                    token = { store.readToken() },
                    onUnauthorized = { expiry.report(it) },
                )
                ApiRepository(client, store) to store
            }
            val repository: ShooRepository
            val session: SessionStore?
            if (usesMock) {
                val scenario = MockRepository.Scenario.from(value("-mock.scenario")) ?: MockRepository.Scenario.STANDARD
                // Error states: `-mock.fail me,setVerdict=verdict_not_allowed`. Loading states: `-mock.latency 8000`.
                val failures = MockRepository.failures(value("-mock.fail"))
                val latency = value("-mock.latency")?.toLongOrNull() ?: 300L
                repository = MockRepository(
                    mode = settings.mode ?: UserMode.GUARDIAN, scenario = scenario, latencyMillis = latency,
                    fixtures = fixtures, pageCopies = value("-debug.replicaFixture") == "YES", failures = failures,
                )
                session = null
                // Fixtures only, nothing leaves the phone: UI tests don't answer the question unless they test it.
                // Android Debug builds run on fixtures by default (PORTING.md), so only an explicit UI-test launch
                // (`-UITestMock YES`) skips the question; a plain Debug launch asks it like iOS does.
                if (value("-UITestMock") == "YES" && value("-debug.askDataConsent") != "YES") {
                    settings.dataConsent = settings.dataConsent ?: DataConsent.GRANTED
                }
            } else {
                val (liveRepository, liveSession) = makeLiveBackend()
                repository = liveRepository
                session = liveSession
            }
            var notifications: NotificationPermission = SystemNotificationPermission(app)
            var extensionStatus: suspend () -> ExtensionStatus = { ExtensionStatus.load(app) }
            if (BuildConfig.DEBUG) {
                // UI tests: no system prompt, and the add-on counts as on without a real link.
                when (value("-UITestNotifications")) {
                    "granted" -> notifications = FixedNotificationPermission(NotificationAuthorization.AUTHORIZED)
                    "denied" -> notifications = FixedNotificationPermission(NotificationAuthorization.DENIED)
                }
                if (value("-UITestExtensionActive") == "YES") extensionStatus = { ExtensionStatus.Active(Instant.now()) }
                // ON-04 messages (#135): `-UITestExtensionStatus switchedOff|someSitesOnly|notSeen|unchecked|offTwoDays`.
                when (value("-UITestExtensionStatus")) {
                    "switchedOff" -> extensionStatus = { ExtensionStatus.Off(null, ExtensionStatus.OffReason.SWITCHED_OFF) }
                    "someSitesOnly" -> extensionStatus = { ExtensionStatus.Off(Instant.now(), ExtensionStatus.OffReason.SOME_SITES_ONLY) }
                    "notSeen" -> extensionStatus = { ExtensionStatus.Off(null, ExtensionStatus.OffReason.NOT_SEEN) }
                    "unchecked" -> extensionStatus = { ExtensionStatus.Active(null) }
                    // Activity "Perlindungan mati" (PR-05): switched off, last sign of life two days ago.
                    "offTwoDays" -> extensionStatus = {
                        ExtensionStatus.Off(Instant.now().minusSeconds(2 * 86_400), ExtensionStatus.OffReason.SWITCHED_OFF)
                    }
                }
                // "Mengecek Shoo…" (1681:5275): the browser takes this many seconds to answer, `-UITestExtensionDelay 3`.
                value("-UITestExtensionDelay")?.toDoubleOrNull()?.let { seconds ->
                    val read = extensionStatus
                    extensionStatus = {
                        delay((seconds * 1000).toLong())
                        read()
                    }
                }
                // Activity empty states (PR-05): the extension's counters as in Figma (#183).
                if (value("-UITestCheckStats") == "YES") {
                    val lastChecked = ZonedDateTime.now(ZoneId.systemDefault()).withHour(10).withMinute(42).withSecond(0).withNano(0)
                    appGroup.edit()
                        .putInt(CheckStats.Key.checked, 1284)
                        .putLong(CheckStats.Key.lastCheckedAt, lastChecked.toInstant().toEpochMilli())
                        .apply()
                }
            }
            val environment = AppEnvironment(
                repository = repository, settings = settings, notifications = notifications, session = session,
                appGroupDefaults = appGroup, extensionStatus = extensionStatus,
                registerForPush = { GuardianCheckJob.sync(app) },
                clearDeliveredPushes = { DeliveredPushes.clear(app) },
                fixtures = fixtures,
            )
            environment.makeLiveBackend = makeLiveBackend
            expiry.environment = environment
            environment.checkStoredSession()
            if (BuildConfig.DEBUG) {
                // UI gate for the "Session expired" screen: `-debug.sessionExpired YES`.
                if (value("-debug.sessionExpired") == "YES") environment.markSessionExpired()
                // Screenshots for the UI gate: `-debug.tab activity`, `-debug.profile YES`.
                AppTab.from(value("-debug.tab"))?.let { environment.router.selectedTab = it }
                if (value("-debug.profile") == "YES") environment.router.openProfile()
                // Figma parity screenshots of a Profile page: `-debug.profilePage editProfile|notifications|…`.
                val pages = mapOf(
                    "mode" to ProfilePage.MODE, "editProfile" to ProfilePage.EDIT_PROFILE,
                    "connection" to ProfilePage.CONNECTION, "notifications" to ProfilePage.NOTIFICATIONS,
                    "language" to ProfilePage.LANGUAGE, "theme" to ProfilePage.THEME,
                    "accessibility" to ProfilePage.ACCESSIBILITY, "about" to ProfilePage.ABOUT,
                    "licenses" to ProfilePage.LICENSES,
                )
                value("-debug.profilePage")?.let { pages[it] }?.let { page ->
                    environment.router.openProfile()
                    environment.router.show(Route.ProfilePage(page))
                }
                // A family member's detail (PF-01): `-debug.member dev_dad`.
                value("-debug.member")?.let { deviceId ->
                    environment.router.openProfile()
                    environment.router.show(Route.Member(deviceId))
                }
                // ON-01: UI tests that don't test the launch splash start on their screen (`-UITestSkipSplash YES`).
                if (value("-UITestSkipSplash") == "YES") environment.launchSplash = LaunchSplashPhase.DONE
                environment.launchSplashHold = value("-UITestSplashSeconds")?.toDoubleOrNull()
                // iOS also turns UIKit animations off here; Android screens read `LocalReduceMotion`.
                if (value("-UITestReduceMotion") == "YES" || value("-UITestStillLoops") == "YES") {
                    environment.reducesMotionForUITests = true
                }
                // Detail (fase 03): `-debug.detail <scanId>` opens it on the selected tab.
                value("-debug.detail")?.let { environment.router.showDetail(it) }
            }
            return environment
        }

        /** Previews: fixtures, no latency, onboarding done. Pass `MockRepository.assetFixtures(context.assets)` for data. */
        fun preview(
            mode: UserMode = UserMode.GUARDIAN,
            language: AppLanguage = AppLanguage.ENGLISH,
            fixtures: (String) -> String? = { null },
        ): AppEnvironment {
            val settings = AppSettings(InMemoryPreferences())
            settings.chooseMode(mode)
            settings.language = language
            settings.onboardingCompleted = true
            settings.dataConsent = DataConsent.GRANTED
            val environment = AppEnvironment(
                repository = MockRepository(mode = mode, latencyMillis = 0, fixtures = fixtures),
                settings = settings,
                fixtures = fixtures,
            )
            environment.launchSplash = LaunchSplashPhase.DONE
            return environment
        }
    }
}

/** Hands a 401 from any network thread to the environment on the main thread. */
class SessionExpiry {
    /** Written once in `live()`, before any request can run. */
    @Volatile
    var environment: AppEnvironment? = null

    fun report(usedToken: String) {
        val environment = environment ?: return
        environment.scope.launch { environment.handleUnauthorized(usedToken) }
    }
}

/** One shared `GET /devices/me` (OPT-06): asked by the foreground sync (`forSync`) or by Home, under `token` and the
 * repository `source`, at `startedAt`. `taken`: the other side used it already. */
internal class ProfileCall(
    val task: Deferred<DeviceProfile>,
    val token: String?,
    val source: ShooRepository,
    val startedAt: Instant,
    val forSync: Boolean,
) {
    var taken = false
}
