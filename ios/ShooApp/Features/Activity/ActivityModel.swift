import Foundation
import Observation
import SwiftUI

/// Filter chips of Activity (PR-05, GD-05).
enum ActivityFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case warning
    case blocked

    var status: ScanStatus? {
        switch self {
        case .all: nil
        case .warning: .warning
        case .blocked: .blocked
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .warning: "Warning"
        case .blocked: "Blocked"
        }
    }
}

/// Whose scans Family Activity shows (GD-05): everyone, the guardian, or one member.
enum ActivityPerson: Hashable, Sendable {
    case everyone
    case me
    case device(String)
}

/// Activity list (PR-05; reused by the Guardian's GD-05 with another `owner`): newest first,
/// filter by status, endless scroll on `nextCursor`, pull to refresh.
@MainActor
@Observable
final class ActivityModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed
    }

    /// `.family` turns on the person filter (GD-05); `.me` is the user's own history.
    let baseOwner: ScanOwnerFilter
    private(set) var person: ActivityPerson = .everyone
    /// Family members for the person chips; empty outside Family Activity.
    private(set) var people: [FamilyMember] = []
    private(set) var state: State = .loading
    private(set) var filter: ActivityFilter = .all
    private(set) var items: [ScanResult] = []
    private(set) var isLoadingMore = false
    /// The last pull to refresh failed; the list on screen is the previous one.
    private(set) var refreshFailed = false
    /// The last next-page request failed; the list shows a Retry row.
    private(set) var loadMoreFailed = false
    private var nextCursor: String?

    @ObservationIgnored private let repository: any ShooRepository
    /// Bumped when a first-page request starts and again when one is applied, so neither an older
    /// first page nor a next page meant for the previous list can overwrite the newer one.
    @ObservationIgnored private var generation = 0

    init(repository: any ShooRepository, owner: ScanOwnerFilter, filter: ActivityFilter = .all) {
        self.repository = repository
        baseOwner = owner
        self.filter = filter
    }

    /// The `owner=` actually requested: the person filter narrows Family Activity.
    var owner: ScanOwnerFilter {
        switch person {
        case .everyone: baseOwner
        case .me: .me
        case .device(let id): .device(id)
        }
    }

    var hasMore: Bool { nextCursor != nil }
    /// Loaded fine and nothing matches the filter (each filter has its own empty text).
    var isEmpty: Bool { state == .loaded && items.isEmpty }

    func load() async {
        await refreshPeople()
        guard !Task.isCancelled else { return }
        await loadFirstPage()
    }

    /// Pull to refresh: keeps the current items on screen until the new first page arrives,
    /// and keeps them if it fails.
    func refresh() async {
        await load()
    }

    /// "Try again" on the error screen: shows the spinner while it retries.
    func retry() async {
        if items.isEmpty { state = .loading }
        await load()
    }

    func select(_ filter: ActivityFilter) async {
        guard filter != self.filter || state == .failed else { return }
        self.filter = filter
        await startOver()
    }

    func select(person: ActivityPerson) async {
        guard baseOwner == .family, person != self.person || state == .failed else { return }
        self.person = person
        await startOver()
    }

    private func startOver() async {
        items = []
        nextCursor = nil
        isLoadingMore = false
        loadMoreFailed = false
        refreshFailed = false
        state = .loading
        await loadFirstPage()
    }

    /// Called when the last row appears, and by the Retry row.
    func loadMore() async {
        guard let cursor = nextCursor, state == .loaded, !isLoadingMore else { return }
        let request = generation
        isLoadingMore = true
        loadMoreFailed = false
        do {
            let page = try await repository.scans(owner: owner, status: filter.status, cursor: cursor)
            guard request == generation else { return }
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
            isLoadingMore = false
        } catch {
            // A newer list replaced this one: its own state is already right.
            guard request == generation else { return }
            isLoadingMore = false
            if error.isCancellation { return }
            Log.ui.error("Activity next page failed", error)
            loadMoreFailed = true
        }
    }

    /// Person chips for Family Activity, re-read on every load (members come and go in Profile).
    /// A failure keeps the chips already shown; the list still loads.
    private func refreshPeople() async {
        guard baseOwner == .family else { return }
        do {
            let members = try await repository.familyMembers()
            people = members
            if case .device(let id) = person, !members.contains(where: { $0.deviceId == id }) {
                person = .everyone
            }
        } catch {
            if !error.isCancellation { Log.ui.error("Activity people failed", error) }
        }
    }

    private func loadFirstPage() async {
        generation += 1
        let request = generation
        do {
            let page = try await repository.scans(owner: owner, status: filter.status, cursor: nil)
            guard request == generation else { return }
            generation += 1
            items = page.items
            nextCursor = page.nextCursor
            isLoadingMore = false
            loadMoreFailed = false
            refreshFailed = false
            state = .loaded
        } catch {
            guard request == generation, !error.isCancellation else { return }
            Log.ui.error("Activity load failed", error)
            if state == .loaded {
                refreshFailed = true
            } else {
                items = []
                nextCursor = nil
                state = .failed
            }
        }
    }
}
