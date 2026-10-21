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

    let owner: ScanOwnerFilter
    private(set) var state: State = .loading
    private(set) var filter: ActivityFilter = .all
    private(set) var items: [ScanResult] = []
    private(set) var isLoadingMore = false
    private var nextCursor: String?

    @ObservationIgnored private let repository: any ShooRepository
    /// Bumped on every new first-page request, so an older answer never overwrites a newer one.
    @ObservationIgnored private var generation = 0

    init(repository: any ShooRepository, owner: ScanOwnerFilter, filter: ActivityFilter = .all) {
        self.repository = repository
        self.owner = owner
        self.filter = filter
    }

    var hasMore: Bool { nextCursor != nil }
    /// Loaded fine and nothing matches the filter (each filter has its own empty text).
    var isEmpty: Bool { state == .loaded && items.isEmpty }

    func load() async {
        await loadFirstPage()
    }

    /// Pull to refresh: keeps the current items on screen until the new first page arrives.
    func refresh() async {
        await loadFirstPage()
    }

    func select(_ filter: ActivityFilter) async {
        self.filter = filter
        items = []
        nextCursor = nil
        state = .loading
        await loadFirstPage()
    }

    /// Called when the last row appears.
    func loadMore() async {
        guard let cursor = nextCursor, state == .loaded, !isLoadingMore else { return }
        let request = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repository.scans(owner: owner, status: filter.status, cursor: cursor)
            guard request == generation else { return }
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
        } catch {
            // The list stays as it is; the next scroll to the end tries again.
            Log.ui.error("Activity next page failed", error)
        }
    }

    private func loadFirstPage() async {
        generation += 1
        let request = generation
        do {
            let page = try await repository.scans(owner: owner, status: filter.status, cursor: nil)
            guard request == generation else { return }
            items = page.items
            nextCursor = page.nextCursor
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard request == generation else { return }
            Log.ui.error("Activity load failed", error)
            items = []
            nextCursor = nil
            state = .failed
        }
    }
}
