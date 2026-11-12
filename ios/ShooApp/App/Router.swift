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

    /// Every sheet and cover the tabs can show (BH-28: a push used to push Detail underneath the
    /// "Become supervised" sheet or the Guardian intro cover).
    private func closeSheets() {
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
