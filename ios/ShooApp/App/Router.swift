import Foundation
import Observation

/// Screens that are pushed on a tab's navigation stack.
enum Route: Hashable {
    case detail(scanId: String)
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
    var isProfilePresented = false
    /// Protected after onboarding: Connect (PR-01) as a sheet, from Shield or an invite link.
    var isConnectPresented = false
    /// From `shoo://join?code=` (PR-03): fills the Connect field, never joins by itself (T11).
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
        isProfilePresented = false
        isTurnOnPresented = false
        isConnectPresented = false
        wantsConnect = false
    }

    /// Shows Connect now, or right after the open sheet is dismissed (SwiftUI shows one sheet at a time).
    func showConnect() {
        guard !isConnectPresented else { return }
        popToRoot()
        selectedTab = .shield
        if isProfilePresented || isTurnOnPresented {
            wantsConnect = true
            isProfilePresented = false
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
