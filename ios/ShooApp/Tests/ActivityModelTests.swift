import Foundation
import Testing
@testable import Shoo

@MainActor
struct ActivityModelTests {
    func model(mode: UserMode = .protected, owner: ScanOwnerFilter = .me, scenario: MockRepository.Scenario = .standard, pageSize: Int = 20) -> ActivityModel {
        ActivityModel(
            repository: MockRepository(mode: mode, scenario: scenario, latency: .zero, pageSize: pageSize),
            owner: owner
        )
    }

    @Test func allIsNewestFirst() async {
        let model = model()
        await model.load()
        #expect(!model.items.isEmpty)
        #expect(model.items.map(\.detectedAt) == model.items.map(\.detectedAt).sorted(by: >))
        #expect(model.items.allSatisfy { $0.ownerDeviceId == "dev_mom" })
        #expect(model.state == .loaded)
    }

    @Test(arguments: [(ActivityFilter.warning, ScanStatus.warning), (.blocked, .blocked)])
    func filterShowsOnlyThatStatus(filter: ActivityFilter, status: ScanStatus) async {
        let model = model(mode: .guardian, owner: .family)
        await model.select(filter)
        #expect(model.filter == filter)
        #expect(!model.items.isEmpty)
        #expect(model.items.allSatisfy { $0.status == status })
    }

    @Test func backToAllShowsEverything() async {
        let model = model(mode: .guardian, owner: .family)
        await model.select(.blocked)
        let blocked = model.items.count
        await model.select(.all)
        #expect(model.items.count > blocked)
    }

    @Test func loadMoreFollowsTheCursorWithoutDuplicates() async {
        // Fixture pages of 2: [mom, guardian], [mom, dad], [mom]; the guardian's own row is left out.
        let model = model(mode: .guardian, owner: .family, pageSize: 2)
        await model.load()
        #expect(model.items.count == 1)
        #expect(model.hasMore)
        await model.loadMore()
        await model.loadMore()
        await model.loadMore()
        #expect(model.items.count == 4)
        #expect(Set(model.items.map(\.id)).count == 4)
        #expect(!model.hasMore)
        #expect(model.items.map(\.detectedAt) == model.items.map(\.detectedAt).sorted(by: >))
    }

    @Test func refreshStartsOverAtTheFirstPage() async {
        let model = model(mode: .guardian, owner: .family, pageSize: 2)
        await model.load()
        await model.loadMore()
        await model.refresh()
        #expect(model.items.count == 1)
        #expect(model.hasMore)
    }

    @Test func emptyStateIsPerFilter() async {
        let model = model(scenario: .empty)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.items.isEmpty)
        #expect(model.isEmpty)
        await model.select(.blocked)
        #expect(model.isEmpty)
    }

    @Test func failureShowsErrorAndKeepsNothing() async {
        let model = ActivityModel(repository: FailingRepository(), owner: .me)
        await model.load()
        #expect(model.state == .failed)
        #expect(model.items.isEmpty)
        #expect(!model.isEmpty)
    }

    @Test func staleResponseFromThePreviousFilterIsIgnored() async {
        // The "All" request answers after the "Blocked" one.
        let repository = DelayedScansRepository(
            base: MockRepository(mode: .guardian, latency: .zero), delays: [.milliseconds(300), .zero]
        )
        let model = ActivityModel(repository: repository, owner: .family)
        async let slowAll: Void = model.select(.all)
        try? await Task.sleep(for: .milliseconds(20))
        await model.select(.blocked)
        await slowAll
        #expect(model.filter == .blocked)
        #expect(model.items.allSatisfy { $0.status == .blocked })
    }

    @Test func failedRefreshKeepsTheList() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        let model = ActivityModel(repository: repository, owner: .family)
        await model.load()
        let shown = model.items
        repository.failure = RepositoryError.network
        await model.refresh()
        #expect(model.state == .loaded)
        #expect(model.items == shown)
        #expect(model.refreshFailed)
        repository.failure = nil
        await model.refresh()
        #expect(!model.refreshFailed)
    }

    @Test func pageForTheOldListIsDroppedAfterARefresh() async {
        // load (0) → refresh in flight (100 ms) → loadMore starts during it (300 ms) and answers last.
        let repository = DelayedScansRepository(
            base: MockRepository(mode: .guardian, latency: .zero, pageSize: 2),
            delays: [.zero, .milliseconds(100), .milliseconds(300)]
        )
        let model = ActivityModel(repository: repository, owner: .family)
        await model.load()
        async let refresh: Void = model.refresh()
        try? await Task.sleep(for: .milliseconds(20))
        async let more: Void = model.loadMore()
        _ = await (refresh, more)
        #expect(model.items.count == 1)
        #expect(!model.isLoadingMore)
    }

    @Test func failedNextPageCanBeRetried() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero, pageSize: 2))
        let model = ActivityModel(repository: repository, owner: .family)
        await model.load()
        repository.failure = RepositoryError.network
        await model.loadMore()
        #expect(model.loadMoreFailed)
        #expect(model.items.count == 1)
        repository.failure = nil
        await model.loadMore()
        #expect(!model.loadMoreFailed)
        #expect(model.items.count == 3)
    }

    @Test func cancelledURLRequestIsNotAFailure() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        repository.failure = URLError(.cancelled)
        let model = ActivityModel(repository: repository, owner: .family)
        await model.load()
        #expect(model.state == .loading)
    }

    @Test func tappingTheActiveFilterKeepsTheList() async {
        let model = model(mode: .guardian, owner: .family)
        await model.load()
        let shown = model.items
        await model.select(.all)
        #expect(model.items == shown)
        #expect(model.state == .loaded)
    }

    @Test func rowLinkHidesQueryAndFragment() throws {
        let url = try #require(URL(string: "https://bca-verify.top/login?user=ibu%40mail.com&otp=123456#step2"))
        #expect(ActivityRow.displayLink(url) == "bca-verify.top/login")
        let root = try #require(URL(string: "https://bca-verify.top/?ref=wa"))
        #expect(ActivityRow.displayLink(root) == "bca-verify.top")
    }

    @Test func familyActivityListsThePeopleToFilterBy() async {
        let model = model(mode: .guardian, owner: .family)
        await model.load()
        #expect(model.people.map(\.name) == ["Mom", "Dad"])
        #expect(Set(model.items.map(\.ownerDeviceId)) == ["dev_mom", "dev_dad"])
    }

    @Test func familyActivityLeavesOutTheGuardiansOwnRows() async {
        let model = model(mode: .guardian, owner: .family)
        await model.load()
        #expect(!model.items.isEmpty)
        #expect(!model.items.contains { $0.ownerDeviceId == "dev_me" })
    }

    @Test func ownDeviceFromTheSessionWinsOverTheProfileRequest() async {
        // The session's id is used as-is: here it names Mom, so her rows go and the mock's `dev_me` stays.
        let model = ActivityModel(
            repository: MockRepository(mode: .guardian, latency: .zero), owner: .family, ownDeviceId: "dev_mom"
        )
        await model.load()
        #expect(!model.items.isEmpty)
        #expect(!model.items.contains { $0.ownerDeviceId == "dev_mom" })
        #expect(model.items.contains { $0.ownerDeviceId == "dev_me" })
    }

    @Test func firstPageEmptyAfterFilteringLoadsTheNextPage() async {
        // Warnings, 1 per page: [guardian], [mom]. The first page is all the guardian's own.
        let repository = CountingScansRepository(base: MockRepository(mode: .guardian, latency: .zero, pageSize: 1))
        let model = ActivityModel(repository: repository, owner: .family, filter: .warning)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.items.map(\.ownerDeviceId) == ["dev_mom"])
        #expect(repository.scanCalls == 2)
        #expect(!model.hasMore)
    }

    @Test func nextPageEmptyAfterFilteringLoadsTheOneAfter() async {
        // 1 per page: [mom], [guardian], [mom], [dad], [mom].
        let model = model(mode: .guardian, owner: .family, pageSize: 1)
        await model.load()
        #expect(model.items.count == 1)
        await model.loadMore()
        #expect(model.items.count == 2)
        #expect(model.items.allSatisfy { $0.ownerDeviceId != "dev_me" })
        #expect(model.hasMore)
    }

    @Test func ownListKeepsTheGuardiansRows() async {
        let model = model(mode: .guardian, owner: .me)
        await model.load()
        #expect(model.items.map(\.ownerDeviceId) == ["dev_me"])
    }

    @Test func rowsGroupByDayNewestFirst() async throws {
        let model = model(mode: .guardian, owner: .family)
        await model.load()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let days = ActivityDay.group(model.items, calendar: utc)
        #expect(days.map(\.items.count) == [2, 1, 1])
        #expect(days.map(\.id) == days.map(\.id).sorted(by: >))
        #expect(days.flatMap(\.items) == model.items)
        let formatter = ISO8601DateFormatter()
        #expect(days.first?.id == formatter.date(from: "2026-10-21T00:00:00Z"))
    }

    @Test func ownActivityHasNoPeopleFilter() async {
        let model = model(mode: .guardian, owner: .me)
        await model.load()
        #expect(model.people.isEmpty)
        #expect(model.items.allSatisfy { $0.ownerDeviceId == "dev_me" })
    }

    @Test(arguments: [(ActivityPerson.device("dev_mom"), "dev_mom"), (.device("dev_dad"), "dev_dad")])
    func personFilterShowsOnlyThatPerson(person: ActivityPerson, deviceId: String) async {
        let model = model(mode: .guardian, owner: .family)
        await model.load()
        await model.select(person: person)
        #expect(model.person == person)
        #expect(!model.items.isEmpty)
        #expect(model.items.allSatisfy { $0.ownerDeviceId == deviceId })
    }

    @Test func personAndStatusFiltersCombine() async {
        let model = model(mode: .guardian, owner: .family)
        await model.load()
        await model.select(person: .device("dev_mom"))
        await model.select(.blocked)
        #expect(!model.items.isEmpty)
        #expect(model.items.allSatisfy { $0.ownerDeviceId == "dev_mom" && $0.status == .blocked })
        await model.select(person: .everyone)
        #expect(model.filter == .blocked)
        #expect(model.items.allSatisfy { $0.status == .blocked })
        #expect(model.items.contains { $0.ownerDeviceId == "dev_dad" })
    }

    @Test func removedPersonFallsBackToEveryone() async throws {
        let repository = MockRepository(mode: .guardian, latency: .zero)
        let model = ActivityModel(repository: repository, owner: .family)
        await model.load()
        await model.select(person: .device("dev_dad"))
        try await repository.removeMember(deviceId: "dev_dad")
        await model.refresh()
        #expect(model.people.map(\.name) == ["Mom"])
        #expect(model.person == .everyone)
        #expect(model.state == .loaded)
        #expect(!model.items.contains { $0.ownerDeviceId == "dev_dad" })
    }
}
