import Foundation
import Observation
import SwiftUI

/// Segments of Activity (PR-05, GD-05).
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

    /// Figma: "Semua / Waspada / Diblokir" on the own list, "Semua / Waspada / Bahaya" in Family mode.
    func title(family: Bool) -> LocalizedStringKey {
        switch self {
        case .all: "All"
        case .warning: "activity.warning"
        case .blocked: family ? "Danger" : "Blocked"
        }
    }
}

/// Whose scans Family Activity shows (GD-05): every member, or one of them.
enum ActivityPerson: Hashable, Sendable {
    case everyone
    case device(String)
}

/// One day of the list with its rows, newest first (Figma "Hari ini", "25 Oktober").
struct ActivityDay: Identifiable, Equatable {
    /// Start of the day in the given calendar's time zone.
    let id: Date
    let items: [ScanResult]

    /// Groups a newest-first list by calendar day, keeping the order.
    static func group(_ items: [ScanResult], calendar: Calendar = .current) -> [ActivityDay] {
        var days: [ActivityDay] = []
        for scan in items {
            let day = calendar.startOfDay(for: scan.detectedAt)
            if let last = days.last, last.id == day {
                days[days.count - 1] = ActivityDay(id: day, items: last.items + [scan])
            } else {
                days.append(ActivityDay(id: day, items: [scan]))
            }
        }
        return days
    }
}

/// Activity list (PR-05; reused by the Guardian's GD-05 with `owner: .family`): newest first,
/// grouped by day, filter by status, endless scroll on `nextCursor`, pull to refresh.
@MainActor
@Observable
final class ActivityModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed
    }

    /// `.family` turns on the person picker (GD-05); `.me` is the user's own history.
    let baseOwner: ScanOwnerFilter
    private(set) var person: ActivityPerson = .everyone
    /// Family members for the picker; empty outside Family Activity.
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
    /// The guardian's own device: Family Activity shows members only, so its rows are left out.
    private var ownDeviceId: String?
    /// Own list only (Figma 450:8739): the Protected user's guardian, for "Virellia belum melihat
    /// website ini" under a blocked row. Nil for a guardian or a Protected user without one.
    private(set) var guardianName: String?

    @ObservationIgnored private let repository: any ShooRepository
    /// Bumped when a first-page request starts and again when one is applied, so neither an older
    /// first page nor a next page meant for the previous list can overwrite the newer one.
    @ObservationIgnored private var generation = 0

    /// `ownDeviceId` comes from the session; without one (mock, tests) Family Activity asks `me()` once.
    init(
        repository: any ShooRepository, owner: ScanOwnerFilter, ownDeviceId: String? = nil,
        filter: ActivityFilter = .all, person: ActivityPerson = .everyone
    ) {
        self.repository = repository
        baseOwner = owner
        self.ownDeviceId = ownDeviceId
        self.filter = filter
        self.person = owner == .family ? person : .everyone
    }

    var isFamily: Bool { baseOwner == .family }
    /// The user's own history (PR-05), not Family Activity or one member's list.
    var isOwnList: Bool { baseOwner == .me }

    /// The `owner=` actually requested: the person picker narrows Family Activity.
    var owner: ScanOwnerFilter {
        switch person {
        case .everyone: baseOwner
        case .device(let id): .device(id)
        }
    }

    var hasMore: Bool { nextCursor != nil }
    /// Loaded fine and nothing matches the filter (each filter has its own empty text).
    var isEmpty: Bool { state == .loaded && items.isEmpty }
    var days: [ActivityDay] { ActivityDay.group(items) }

    /// The member picked in Family Activity, nil for everyone.
    var selectedMember: FamilyMember? {
        guard case .device(let id) = person else { return nil }
        return people.first { $0.deviceId == id }
    }

    /// Avatar id for a row's owner (Family Activity subline).
    func avatarId(for deviceId: String) -> String? {
        people.first { $0.deviceId == deviceId }?.avatarId
    }

    func load() async {
        await refreshPeople()
        await refreshViewer()
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
        guard isFamily, person != self.person || state == .failed else { return }
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
            guard let page = try await visiblePage(after: cursor, request: request) else { return }
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

    /// Rows the list shows: in Family Activity (everyone) the guardian's own rows are left out (GD-05).
    private func isShown(_ scan: ScanResult) -> Bool {
        guard isFamily, person == .everyone, let ownDeviceId else { return true }
        return scan.ownerDeviceId != ownDeviceId
    }

    /// One page with its hidden rows removed. A page left empty by that is skipped while a next one
    /// exists, so the list never stalls on an empty page. Nil when a newer list replaced this one.
    private func visiblePage(after cursor: String?, request: Int) async throws -> ScanPage? {
        var cursor = cursor
        while true {
            let page = try await repository.scans(owner: owner, status: filter.status, cursor: cursor)
            guard request == generation else { return nil }
            let shown = page.items.filter(isShown)
            if !shown.isEmpty || page.nextCursor == nil {
                return ScanPage(items: shown, nextCursor: page.nextCursor)
            }
            cursor = page.nextCursor
        }
    }

    /// Who is looking at the own list: their device (a verdict they made reads "you") and their
    /// guardian. Re-read on every load (a guardian can connect or leave); a failure keeps the last.
    private func refreshViewer() async {
        guard isOwnList else { return }
        do {
            let me = try await repository.me()
            ownDeviceId = me.deviceId
            guardianName = me.guardian?.name
        } catch {
            if !error.isCancellation { Log.ui.error("Activity profile failed", error) }
        }
    }

    /// Note under an own-list row: the guardian's verdict, or that they have not looked yet.
    func note(for scan: ScanResult) -> ActivityNote? {
        guard isOwnList else { return nil }
        return ActivityNote(scan: scan, guardianName: guardianName, viewerDeviceId: ownDeviceId)
    }

    /// Members for the picker, re-read on every load (members come and go in Profile).
    /// A failure keeps the members already shown; the list still loads.
    private func refreshPeople() async {
        guard isFamily else { return }
        if ownDeviceId == nil {
            ownDeviceId = try? await repository.me().deviceId
        }
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
            guard let page = try await visiblePage(after: nil, request: request) else { return }
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
