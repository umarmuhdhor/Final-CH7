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
        let model = model(mode: .guardian, owner: .family, pageSize: 2)
        await model.load()
        #expect(model.items.count == 2)
        #expect(model.hasMore)
        await model.loadMore()
        await model.loadMore()
        await model.loadMore()
        #expect(model.items.count == 5)
        #expect(Set(model.items.map(\.id)).count == 5)
        #expect(!model.hasMore)
        #expect(model.items.map(\.detectedAt) == model.items.map(\.detectedAt).sorted(by: >))
    }

    @Test func refreshStartsOverAtTheFirstPage() async {
        let model = model(mode: .guardian, owner: .family, pageSize: 2)
        await model.load()
        await model.loadMore()
        await model.refresh()
        #expect(model.items.count == 2)
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
}
