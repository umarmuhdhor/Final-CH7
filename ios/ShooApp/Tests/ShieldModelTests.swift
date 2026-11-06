import Foundation
import Testing
@testable import Shoo

@MainActor
struct ShieldModelTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func model(
        mode: UserMode = .protected,
        scenario: MockRepository.Scenario = .standard,
        lastSeen: Date? = nil
    ) -> ShieldModel {
        let now = now
        return ShieldModel(
            repository: MockRepository(mode: mode, scenario: scenario, latency: .zero),
            extensionStatus: { ExtensionStatus.evaluate(lastSeen: lastSeen, now: now) }
        )
    }

    @Test func recentHeartbeatIsActive() async {
        let model = model(lastSeen: now.addingTimeInterval(-60))
        await model.refresh()
        #expect(model.extensionStatus.isActive)
    }

    @Test func staleOrMissingHeartbeatIsOff() async {
        let stale = model(lastSeen: now.addingTimeInterval(-AppGroup.extensionActiveWindow - 1))
        await stale.refresh()
        #expect(!stale.extensionStatus.isActive)
        let never = model(lastSeen: nil)
        await never.refresh()
        #expect(!never.extensionStatus.isActive)
    }

    @Test func showsTheGuardian() async {
        let model = model()
        await model.refresh()
        #expect(model.guardian?.name == "Adhella")
        #expect(model.state == .loaded)
    }

    @Test func lastBlockedIsTheNewestBlockedScanOfThisDevice() async throws {
        let repository = MockRepository(mode: .protected, latency: .zero)
        let model = ShieldModel(repository: repository, extensionStatus: { .off(lastSeen: nil) })
        await model.refresh()
        let blocked = try await repository.scans(owner: .me, status: .blocked, cursor: nil).items
        let card = try #require(model.lastBlocked)
        #expect(card.id == blocked.max(by: { $0.detectedAt < $1.detectedAt })?.id)
        #expect(card.status == .blocked)
        #expect(card.ownerDeviceId == "dev_mom")
    }

    @Test func recentComesFromOwnScans() async throws {
        let repository = MockRepository(mode: .protected, latency: .zero)
        let model = ShieldModel(repository: repository, extensionStatus: { .off(lastSeen: nil) })
        await model.refresh()
        let own = try await repository.scans(owner: .me, status: nil, cursor: nil).items
        #expect(model.recent.count == min(own.count, ShieldModel.recentCount))
        #expect(model.recent.map(\.detectedAt) == model.recent.map(\.detectedAt).sorted(by: >))
    }

    @Test func blockedCardOnlyForTheLastDay() async throws {
        let repository = MockRepository(mode: .protected, latency: .zero)
        let probe = ShieldModel(repository: repository, extensionStatus: { .off(lastSeen: nil) })
        await probe.refresh()
        let blocked = try #require(probe.lastBlocked)
        let soon = ShieldModel(repository: repository, extensionStatus: { .off(lastSeen: nil) }, now: { blocked.detectedAt.addingTimeInterval(60) })
        await soon.refresh()
        #expect(soon.recentBlocked?.id == blocked.id)
        // The big card's site is not listed twice.
        #expect(!soon.recent.contains { $0.id == blocked.id })
        let later = ShieldModel(repository: repository, extensionStatus: { .off(lastSeen: nil) },
                                now: { blocked.detectedAt.addingTimeInterval(ShieldModel.blockedCardWindow + 60) })
        await later.refresh()
        #expect(later.recentBlocked == nil)
    }

    @Test func nothingBlockedYet() async {
        let model = model(scenario: .empty)
        await model.refresh()
        #expect(model.state == .loaded)
        #expect(model.lastBlocked == nil)
    }

    @Test func noGuardianAfterDisconnect() async throws {
        let repository = MockRepository(mode: .protected, latency: .zero)
        try await repository.leaveGuardian()
        let model = ShieldModel(repository: repository, extensionStatus: { .off(lastSeen: nil) })
        await model.refresh()
        #expect(model.guardian == nil)
    }

    @Test func loadFailureKeepsStatusAndShowsError() async {
        let model = ShieldModel(repository: FailingRepository(), extensionStatus: { .active(lastSeen: Date()) })
        await model.refresh()
        #expect(model.state == .failed)
        #expect(model.extensionStatus.isActive)
    }

    @Test func failedForegroundRefreshKeepsWhatIsShown() async throws {
        let repository = DelayedScansRepository(base: MockRepository(mode: .protected, latency: .zero))
        let model = ShieldModel(repository: repository, extensionStatus: { .active(lastSeen: Date()) })
        await model.refresh()
        let blocked = try #require(model.lastBlocked)
        repository.failure = RepositoryError.network
        await model.refresh()
        #expect(model.state == .loaded)
        #expect(model.lastBlocked == blocked)
        #expect(model.guardian?.name == "Adhella")
    }

    @Test func cancelledURLRequestIsNotAFailure() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .protected, latency: .zero))
        repository.failure = URLError(.cancelled)
        let model = ShieldModel(repository: repository, extensionStatus: { .off(lastSeen: nil) })
        await model.refresh()
        #expect(model.state == .loading)
    }

    // MARK: Recent list, scam card, paging (review of #299)

    /// `count` own scans an hour apart before `now`, the newest one blocked, as one scripted page.
    func repository(scans count: Int, pageSize: Int? = nil) async throws -> CountingScansRepository {
        let base = MockRepository(mode: .protected, latency: .zero)
        let own = try await base.scans(owner: .me, status: nil, cursor: nil).items
        let blocked = try #require(own.first { $0.status == .blocked })
        let warning = try #require(own.first { $0.status != .blocked })
        let scans = (0..<count).map { index in
            var scan = index == 0 ? blocked : warning
            scan.id = "scan-\(index)"
            scan.verdict = nil
            scan.detectedAt = now.addingTimeInterval(-Double(index + 1) * 3600)
            return scan
        }
        let repository = CountingScansRepository(base: base)
        let size = pageSize ?? count
        for start in stride(from: 0, to: count, by: size) {
            let end = min(start + size, count)
            repository.pages[start == 0 ? "" : String(start)] =
                ScanPage(items: Array(scans[start..<end]), nextCursor: end < count ? String(end) : nil)
        }
        return repository
    }

    @Test func recentKeepsThreeRowsUnderTheBlockedCard() async throws {
        let now = now
        let model = ShieldModel(repository: try await repository(scans: 10), extensionStatus: { .off(lastSeen: nil) }, now: { now })
        await model.refresh()
        #expect(model.recentBlocked?.id == "scan-0")
        #expect(model.recent.map(\.id) == ["scan-1", "scan-2", "scan-3"])
    }

    @Test func onlyTheBlockedCardLeavesTheListEmpty() async throws {
        let now = now
        let model = ShieldModel(repository: try await repository(scans: 1), extensionStatus: { .off(lastSeen: nil) }, now: { now })
        await model.refresh()
        #expect(model.recentBlocked?.id == "scan-0")
        #expect(model.recent.isEmpty)
    }

    @Test func failedScamCasesKeepTheCard() async throws {
        let repository = try await repository(scans: 4)
        let cases = [ScamCase(id: "case", title: "Situs palsu", detail: "Hari ini")]
        repository.latestScamsResult = .success(cases)
        let model = ShieldModel(repository: repository, extensionStatus: { .off(lastSeen: nil) })
        await model.refresh()
        #expect(model.scamCases == cases)
        repository.latestScamsResult = .failure(.network)
        await model.refresh()
        #expect(model.state == .loaded)
        #expect(model.scamCases == cases)
    }

    @Test func pagingStopsPastTheLastDay() async throws {
        let now = now
        // 60 scans an hour apart, 10 a page: the last day ends in the third page.
        let repository = try await repository(scans: 60, pageSize: 10)
        let model = ShieldModel(repository: repository, extensionStatus: { .off(lastSeen: nil) }, now: { now })
        await model.refresh()
        #expect(repository.scanCalls == 3)
        #expect(model.scans.count == 30)
    }
}
