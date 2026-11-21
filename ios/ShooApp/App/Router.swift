import Foundation
import Observation

/// Screens that are pushed on a tab's navigation stack.
enum Route: Hashable {
    case detail(scanId: String)
    /// PF-01 Profile, from the avatar button on either tab.
    case profile
    case profilePage(ProfilePage)
    /// "Guardian/Detail Orang Dilindungi": one protected member, from Profile's family list.
    case member(deviceId: String)
    /// "Lihat semua" on the member detail: that member's Activity.
    case memberActivity(deviceId: String)
}

/// Profile's sub-screens (PF-01, Figma "Pengaturan/*").
enum ProfilePage: Hashable {
    case mode
    /// "Kelola profil": avatar, name (edited in a sheet), status, Hapus akun.
    case editProfile
    /// Protected: "Terhubung", the guardian and Disconnect.
    case connection
    case notifications
    case language
    case theme
    case accessibility
    case about
    /// "Lisensi pihak ketiga" from Tentang Shoo.
    case licenses
}

/// What the invite banner says (PR-03, Figma "Flow · Protected buka link undangan").
enum InviteNotice: Equatable {
    /// Pribadi (or a guardian protecting nobody): "Kamu dapat undangan keluarga" with Lihat / Nanti saja.
    case invited
    /// A guardian still protecting someone: the join would be refused (`has_members`).
    case hasMembers
    /// Already protected: only that guardian can disconnect this iPhone.
    case alreadyProtected(guardian: String)
}

/// What just changed, said by a toast at the top of Home (plan/alief/proposal/pairing-feedback.md, Option A):
/// every role or pairing change ends on Home, the screen that changed, and this names the change.
enum HomeNotice: Equatable {
    /// Family mode on ("Mulai" on "To be guardian", ⇆, Account mode, Profile's Guardian card).
    case guardianOn
    /// Family mode off. `keepsFamily`: this guardian still protects someone, and the toast says they stay linked (F11).
    case personalOn(keepsFamily: Bool)
    /// Someone joined with this guardian's code while the invite was on screen.
    case memberJoined(name: String)
    /// This iPhone joined a guardian's family ("Selanjutnya" after "Berhasil Terhubung").
    case connected(guardian: String)
    /// The guardian disconnected someone.
    case disconnected(name: String)
}

/// Tabs of the main screen.
enum AppTab: String, Hashable, CaseIterable {
    case shield
    case activity
}

/// Navigation state for the whole app. Deep links (contracts/app-group-keys.md) land here:
/// `shoo://join` (fase 14), `shoo://scan/{id}` + `shoo://activity` and push taps (fase 15).
@Observable
final class Router {
    var selectedTab: AppTab = .shield
    var shieldPath: [Route] = []
    var activityPath: [Route] = []
    /// Protected after onboarding: Connect (PR-01) as a sheet, from Shield or an invite link.
    var isConnectPresented = false
    /// From `shoo://join?code=` or `https://<api host>/j/<code>` (PR-03): fills the Connect field, never joins by itself (T11).
    /// Memory only. It survives a trip to Settings (ON-04 turns the extension on there) but never outlives a code
    /// (`FamilyCodeModel.codeLifetime`): `takePendingJoinCode` and `dropExpiredInvite` drop an older one.
    var pendingJoinCode: String? {
        didSet { pendingJoinCodeAt = pendingJoinCode == nil ? nil : now() }
    }
    /// PR-03 banner on Home for a link opened after onboarding (Figma "Notif undangan").
    var inviteNotice: InviteNotice?
    /// The toast on Home after a role or pairing change (`HomeNotice`). Memory only.
    var homeNotice: HomeNotice?
    /// Bumped with every new `homeNotice`, so the same notice twice still shows again.
    private(set) var homeNoticeCount = 0
    /// Empty Family Home has a ready invite code: the "Mode Guardian aktif" toast offers "Undang".
    var canShareInvite = false
    /// "Undang" on the toast: Home's invite card opens the iOS share sheet.
    private(set) var inviteShareRequests = 0
    /// The one-time tip at ⇆ ("Pindah mode di sini"): Family mode turned on for the first time, so ⇆ just appeared.
    private(set) var isSwitchTipPresented = false
    /// The toast that waits for the tip to close: both sit at the top, so they never show together.
    @ObservationIgnored private var noticeAfterTip: HomeNotice?
    /// Someone just joined: "Baru terhubung" under their avatar on Home, once (no ring: Alief, 20 Nov 2026).
    var newMemberId: String?
    /// Shield's "Turn on" sheet (PR-04). Here, not in the view, so a link can close it first.
    var isTurnOnPresented = false
    /// Figma "To be guardian": before Family mode turns on for the first time.
    var isGuardianIntroPresented = false
    /// Pribadi "Mode Terawasi" → Hubungkan: join a guardian's family as protected.
    var isJoinFamilyPresented = false
    /// GD-01: the "Notifications are off" popup was shown this launch. Memory only, so the next launch reminds again.
    var notificationReminderShown = false
    /// An invite link asked for Connect while another sheet was up: shown once that one is gone.
    private(set) var wantsConnect = false
    /// An invite link asked for "Become supervised" (Pribadi) while another sheet was up: shown once that one is gone.
    private(set) var wantsJoinFamily = false
    @ObservationIgnored private var pendingJoinCodeAt: Date?
    @ObservationIgnored private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// A push tap or `shoo://scan/{id}` (GD-06): Detail on the Activity tab, whatever was open.
    func openDetail(scanId: String) {
        closeSheets()
        selectedTab = .activity
        shieldPath.removeAll()
        activityPath = [.detail(scanId: scanId)]
    }

    /// `shoo://activity`: the Activity list, newest first.
    func openActivity() {
        closeSheets()
        popToRoot()
        selectedTab = .activity
    }

    /// Bumped by `closeSheets()`: a screen closes the sheets it owns itself (Home's "Why is it safe?", Activity's
    /// "Turn on"), which stay on screen over a tab switch and would hide Detail like BH-28.
    private(set) var screenSheetsClosed = 0

    /// Every sheet and cover the tabs can show (BH-28: a push used to push Detail underneath the
    /// "Become supervised" sheet or the Guardian intro cover).
    private func closeSheets() {
        screenSheetsClosed += 1
        // A push tap opens Detail on Activity: the tip at Home's ⇆ (and its waiting toast) must not stay over it.
        isSwitchTipPresented = false
        noticeAfterTip = nil
        isTurnOnPresented = false
        isConnectPresented = false
        isJoinFamilyPresented = false
        isGuardianIntroPresented = false
        wantsConnect = false
        wantsJoinFamily = false
    }

    /// Pribadi's invite link (BH-10): "Become supervised" with the code filled in, on Shield. Like
    /// `showConnect`, after the open "Turn on" sheet is dismissed (SwiftUI shows one sheet at a time).
    func showJoinFamily() {
        guard !isJoinFamilyPresented else { return }
        popToRoot()
        selectedTab = .shield
        if isTurnOnPresented {
            wantsJoinFamily = true
            isTurnOnPresented = false
        } else {
            isJoinFamilyPresented = true
        }
    }

    /// Shows Connect now, or right after the open sheet is dismissed (SwiftUI shows one sheet at a time).
    func showConnect() {
        guard !isConnectPresented else { return }
        popToRoot()
        selectedTab = .shield
        if isTurnOnPresented {
            wantsConnect = true
            isTurnOnPresented = false
        } else {
            isConnectPresented = true
        }
    }

    /// `onDismiss` of every other sheet.
    func sheetDismissed() {
        if wantsJoinFamily {
            wantsJoinFamily = false
            isJoinFamilyPresented = true
        }
        guard wantsConnect else { return }
        wantsConnect = false
        isConnectPresented = true
    }

    func showDetail(scanId: String) {
        append(.detail(scanId: scanId))
    }

    /// The avatar button: Profile on top of the current tab.
    func openProfile() {
        guard currentPath.last != .profile else { return }
        append(.profile)
    }

    func show(_ route: Route) {
        append(route)
    }

    /// Profile's back button and the end of a member or connection flow.
    func pop() {
        switch selectedTab {
        case .shield: if !shieldPath.isEmpty { shieldPath.removeLast() }
        case .activity: if !activityPath.isEmpty { activityPath.removeLast() }
        }
    }

    private var currentPath: [Route] {
        selectedTab == .shield ? shieldPath : activityPath
    }

    func popToRoot() {
        shieldPath.removeAll()
        activityPath.removeAll()
    }

    /// Back to a fresh start (disconnect, delete my data): no pushed screens, no sheet, first tab.
    func reset() {
        popToRoot()
        selectedTab = .shield
        closeSheets()
    }

    /// Back on Home with a toast that says what changed (Option A).
    func landOnHome(saying notice: HomeNotice) {
        reset()
        show(notice)
    }

    /// Family mode is on for the first time: Home, the tip at ⇆ first; the toast (and the invite glow) once it closes.
    /// The tip waits for a tap and the toast leaves by itself, so the tip goes first.
    func landOnHomeWithSwitchTip(then notice: HomeNotice) {
        reset()
        noticeAfterTip = notice
        isSwitchTipPresented = true
    }

    /// A tap anywhere (⇆ too) closes the tip; it never presses what is under it.
    func closeSwitchTip() {
        guard isSwitchTipPresented else { return }
        isSwitchTipPresented = false
        if let notice = noticeAfterTip {
            noticeAfterTip = nil
            show(notice)
        }
    }

    func show(_ notice: HomeNotice) {
        homeNotice = notice
        homeNoticeCount += 1
    }

    /// "Undang" on the "Mode Guardian aktif" toast.
    func shareInvite() {
        homeNotice = nil
        inviteShareRequests += 1
    }

    /// The account was deleted: its invite banner ("You're already protected by Budi") and waiting code must not
    /// greet the next account (delete = gone at once). `reset()` alone keeps them: a join closes its screens with it.
    func forgetInvite() {
        inviteNotice = nil
        homeNotice = nil
        newMemberId = nil
        pendingJoinCode = nil
    }

    /// Hands the pending invite code to Connect once, unless it is older than a code lives.
    func takePendingJoinCode() -> String? {
        dropExpiredInvite()
        defer { pendingJoinCode = nil }
        return pendingJoinCode
    }

    /// When the app comes back: a code older than a code lives is gone, and so is its banner.
    func dropExpiredInvite() {
        guard let at = pendingJoinCodeAt, now().timeIntervalSince(at) > FamilyCodeModel.codeLifetime else { return }
        pendingJoinCode = nil
        if inviteNotice == .invited { inviteNotice = nil }
    }

    /// "Lihat" on the invite banner: the join sheet, with the code still waiting for it.
    func acceptInvite() {
        inviteNotice = nil
        showJoinFamily()
    }

    /// "Nanti saja", "Tutup" or "Oke" on the invite banner: the code is not used.
    func dismissInviteNotice() {
        inviteNotice = nil
        pendingJoinCode = nil
    }

    /// "Buka Profil" on the "still protecting someone" banner: Profile, where members are disconnected.
    func openProfileFromInviteNotice() {
        dismissInviteNotice()
        selectedTab = .shield
        popToRoot()
        append(.profile)
    }

    private func append(_ route: Route) {
        switch selectedTab {
        case .shield: shieldPath.append(route)
        case .activity: activityPath.append(route)
        }
    }
}
