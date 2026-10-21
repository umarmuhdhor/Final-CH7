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
/// `shoo://join` in fase 14, `shoo://scan/{id}` + `shoo://activity` in fase 15.
@Observable
final class Router {
    var selectedTab: AppTab = .shield
    var shieldPath: [Route] = []
    var activityPath: [Route] = []
    var isProfilePresented = false

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
        isProfilePresented = false
    }

    private func append(_ route: Route) {
        switch selectedTab {
        case .shield: shieldPath.append(route)
        case .activity: activityPath.append(route)
        }
    }
}
