package com.shoo.app.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shoo.app.data.ApiRepository
import java.time.Duration
import java.time.Instant

/** Screens that are pushed on a tab's back stack. */
sealed interface Route {
    data class Detail(val scanId: String) : Route

    /** PF-01 Profile, from the avatar button on either tab. */
    data object Profile : Route

    data class ProfilePage(val page: com.shoo.app.app.ProfilePage) : Route

    /** "Guardian/Detail Orang Dilindungi": one protected member, from Profile's family list. */
    data class Member(val deviceId: String) : Route

    /** "Lihat semua" on the member detail: that member's Activity. */
    data class MemberActivity(val deviceId: String) : Route
}

/** Profile's sub-screens (PF-01, Figma "Pengaturan/…"). */
enum class ProfilePage {
    MODE,
    /** "Kelola profil": avatar, name (edited in a sheet), status, Hapus akun. */
    EDIT_PROFILE,
    /** Protected: "Terhubung", the guardian and Disconnect. */
    CONNECTION,
    NOTIFICATIONS,
    LANGUAGE,
    THEME,
    ACCESSIBILITY,
    ABOUT,
    /** "Lisensi pihak ketiga" from Tentang Shoo. */
    LICENSES,
}

/** What the invite banner says (PR-03, Figma "Flow · Protected buka link undangan"). */
sealed interface InviteNotice {
    /** Pribadi (or a guardian protecting nobody): "Kamu dapat undangan keluarga" with Lihat / Nanti saja. */
    data object Invited : InviteNotice

    /** A guardian still protecting someone: the join would be refused (`has_members`). */
    data object HasMembers : InviteNotice

    /** Already protected: only that guardian can disconnect this phone. */
    data class AlreadyProtected(val guardian: String) : InviteNotice
}

/** Tabs of the main screen. */
enum class AppTab(val rawValue: String) {
    SHIELD("shield"),
    ACTIVITY("activity");

    companion object {
        fun from(raw: String?): AppTab? = entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * Navigation state for the whole app. Deep links (contracts/app-group-keys.md) land here: `shoo://join` (fase 14),
 * `shoo://scan/{id}` + `shoo://activity` and notification taps (fase 15). iOS `NavigationStack(path:)` →
 * [shieldPath] / [activityPath], rendered by `MainTabView`.
 */
class Router(private val now: () -> Instant = Instant::now) {
    var selectedTab by mutableStateOf(AppTab.SHIELD)
    var shieldPath by mutableStateOf<List<Route>>(emptyList())
    var activityPath by mutableStateOf<List<Route>>(emptyList())

    /** Protected after onboarding: Connect (PR-01) as a sheet, from Shield or an invite link. */
    var isConnectPresented by mutableStateOf(false)

    private var _pendingJoinCode by mutableStateOf<String?>(null)
    private var pendingJoinCodeAt: Instant? = null

    /**
     * From `shoo://join?code=` or `https://<api host>/j/<code>` (PR-03): fills the Connect field, never joins by
     * itself (T11). Memory only. It survives a trip to Settings (ON-04) but never outlives a code
     * (`ApiRepository.codeLifetimeSeconds`): `takePendingJoinCode` and `dropExpiredInvite` drop an older one.
     */
    var pendingJoinCode: String?
        get() = _pendingJoinCode
        set(value) {
            _pendingJoinCode = value
            pendingJoinCodeAt = if (value == null) null else now()
        }

    /** PR-03 banner on Home for a link opened after onboarding (Figma "Notif undangan"). */
    var inviteNotice by mutableStateOf<InviteNotice?>(null)

    /** Shield's "Turn on" sheet (PR-04). Here, not in the view, so a link can close it first. */
    var isTurnOnPresented by mutableStateOf(false)

    /** Figma "To be guardian": before Family mode turns on for the first time. */
    var isGuardianIntroPresented by mutableStateOf(false)

    /** Pribadi "Mode Terawasi" → Hubungkan: join a guardian's family as protected. */
    var isJoinFamilyPresented by mutableStateOf(false)

    /** GD-01: the "Notifications are off" popup was shown this launch. Memory only, so the next launch reminds again. */
    var notificationReminderShown by mutableStateOf(false)

    /** An invite link asked for Connect while another sheet was up: shown once that one is gone. */
    var wantsConnect by mutableStateOf(false)
        private set

    /** An invite link asked for "Become supervised" (Pribadi) while another sheet was up: shown once that one is gone. */
    var wantsJoinFamily by mutableStateOf(false)
        private set

    /**
     * Bumped by `closeSheets()`: a screen closes the sheets it owns itself (Home's "Why is it safe?", Activity's
     * "Turn on"), which stay on screen over a tab switch and would hide Detail like BH-28.
     */
    var screenSheetsClosed by mutableIntStateOf(0)
        private set

    /** A notification tap or `shoo://scan/{id}` (GD-06): Detail on the Activity tab, whatever was open. */
    fun openDetail(scanId: String) {
        closeSheets()
        selectedTab = AppTab.ACTIVITY
        shieldPath = emptyList()
        activityPath = listOf(Route.Detail(scanId))
    }

    /** `shoo://activity`: the Activity list, newest first. */
    fun openActivity() {
        closeSheets()
        popToRoot()
        selectedTab = AppTab.ACTIVITY
    }

    /** Every sheet and cover the tabs can show (BH-28: a push used to push Detail underneath the "Become supervised"
     * sheet or the Guardian intro cover). */
    private fun closeSheets() {
        screenSheetsClosed += 1
        isTurnOnPresented = false
        isConnectPresented = false
        isJoinFamilyPresented = false
        isGuardianIntroPresented = false
        wantsConnect = false
        wantsJoinFamily = false
    }

    /** Pribadi's invite link (BH-10): "Become supervised" with the code filled in, on Shield. Like `showConnect`,
     * after the open "Turn on" sheet is dismissed (one sheet at a time, like SwiftUI). */
    fun showJoinFamily() {
        if (isJoinFamilyPresented) return
        popToRoot()
        selectedTab = AppTab.SHIELD
        if (isTurnOnPresented) {
            wantsJoinFamily = true
            isTurnOnPresented = false
        } else {
            isJoinFamilyPresented = true
        }
    }

    /** Shows Connect now, or right after the open sheet is dismissed (one sheet at a time). */
    fun showConnect() {
        if (isConnectPresented) return
        popToRoot()
        selectedTab = AppTab.SHIELD
        if (isTurnOnPresented) {
            wantsConnect = true
            isTurnOnPresented = false
        } else {
            isConnectPresented = true
        }
    }

    /** `onDismiss` of every other sheet. */
    fun sheetDismissed() {
        if (wantsJoinFamily) {
            wantsJoinFamily = false
            isJoinFamilyPresented = true
        }
        if (!wantsConnect) return
        wantsConnect = false
        isConnectPresented = true
    }

    fun showDetail(scanId: String) {
        append(Route.Detail(scanId))
    }

    /** The avatar button: Profile on top of the current tab. */
    fun openProfile() {
        if (currentPath.lastOrNull() == Route.Profile) return
        append(Route.Profile)
    }

    fun show(route: Route) {
        append(route)
    }

    /** Profile's back button and the end of a member or connection flow. */
    fun pop() {
        when (selectedTab) {
            AppTab.SHIELD -> if (shieldPath.isNotEmpty()) shieldPath = shieldPath.dropLast(1)
            AppTab.ACTIVITY -> if (activityPath.isNotEmpty()) activityPath = activityPath.dropLast(1)
        }
    }

    /** The back stack of the tab on screen. */
    val currentPath: List<Route>
        get() = if (selectedTab == AppTab.SHIELD) shieldPath else activityPath

    fun popToRoot() {
        shieldPath = emptyList()
        activityPath = emptyList()
    }

    /** Back to a fresh start (disconnect, delete my data): no pushed screens, no sheet, first tab. */
    fun reset() {
        popToRoot()
        selectedTab = AppTab.SHIELD
        closeSheets()
    }

    /** The account was deleted: its invite banner ("You're already protected by Budi") and waiting code must not
     * greet the next account (delete = gone at once). `reset()` alone keeps them: a join closes its screens with it. */
    fun forgetInvite() {
        inviteNotice = null
        pendingJoinCode = null
    }

    /** Hands the pending invite code to Connect once, unless it is older than a code lives. */
    fun takePendingJoinCode(): String? {
        dropExpiredInvite()
        val code = pendingJoinCode
        pendingJoinCode = null
        return code
    }

    /** When the app comes back: a code older than a code lives is gone, and so is its banner. */
    fun dropExpiredInvite() {
        val at = pendingJoinCodeAt ?: return
        if (Duration.between(at, now()).toMillis() <= ApiRepository.codeLifetimeSeconds * 1000) return
        pendingJoinCode = null
        if (inviteNotice == InviteNotice.Invited) inviteNotice = null
    }

    /** "Lihat" on the invite banner: the join sheet, with the code still waiting for it. */
    fun acceptInvite() {
        inviteNotice = null
        showJoinFamily()
    }

    /** "Nanti saja", "Tutup" or "Oke" on the invite banner: the code is not used. */
    fun dismissInviteNotice() {
        inviteNotice = null
        pendingJoinCode = null
    }

    /** "Buka Profil" on the "still protecting someone" banner: Profile, where members are disconnected. */
    fun openProfileFromInviteNotice() {
        dismissInviteNotice()
        selectedTab = AppTab.SHIELD
        popToRoot()
        append(Route.Profile)
    }

    private fun append(route: Route) {
        when (selectedTab) {
            AppTab.SHIELD -> shieldPath = shieldPath + route
            AppTab.ACTIVITY -> activityPath = activityPath + route
        }
    }
}
