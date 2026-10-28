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
    /// "Kelola profil": avatar, name, @handle, Hapus akun.
    case editProfile
    /// "Nama tampilan" from Kelola profil.
    case editName
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
    /// Memory only, dropped when the app goes to the background.
    var pendingJoinCode: String?
    /// Shield's "Turn on" sheet (PR-04). Here, not in the view, so a link can close it first.
    var isTurnOnPresented = false
    /// An invite link asked for Connect while another sheet was up: shown once that one is gone.
    private(set) var wantsConnect = false

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

    private func closeSheets() {
        isTurnOnPresented = false
        isConnectPresented = false
        wantsConnect = false
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

    /// Hands the pending invite code to Connect once.
    func takePendingJoinCode() -> String? {
        defer { pendingJoinCode = nil }
        return pendingJoinCode
    }

    private func append(_ route: Route) {
        switch selectedTab {
        case .shield: shieldPath.append(route)
        case .activity: activityPath.append(route)
        }
    }
}
