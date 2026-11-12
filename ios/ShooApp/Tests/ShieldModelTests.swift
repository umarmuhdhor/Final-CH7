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

    /// "Mengecek Shoo…" (1681:5275) until Safari has answered once, then the status itself.
    @Test func checksTheExtensionBeforeSayingAnything() async {
        let model = model(lastSeen: now.addingTimeInterval(-60))
        #expect(!model.extensionChecked)
        await model.refresh()
        #expect(model.extensionChecked)
    }

    /// "Coba lagi" on "Gagal memuat" keeps the failed page (the card's button spins) instead of a spinner page.
    @Test func retryAfterAFailureStaysFailedWhileStillOffline() async {
        let model = ShieldModel(
            repository: MockRepository(mode: .protected, latency: .zero, failures: ["me": .network]),
            extensionStatus: { .active(lastSeen: nil) }
        )
        await model.refresh()
        #expect(model.state == .failed)
        await model.retry()
        #expect(model.state == .failed)
    }

    @Test func showsTheGuardian() async {
        let model = model()
        await model.refresh()
        #expect(model.guardian?.name == "Adhella")
        #expect(model.state == .loaded)
    }

    @Test func lastScanIsTheNewestScanOfThisDevice() async throws {
        let repository = MockRepository(mode: .protected, latency: .zero)
        let model = ShieldModel(repository: repository, extensionStatus: { .off(lastSeen: nil) })
        await model.refresh()
        let own = try await repository.scans(owner: .me, status: nil, cursor: nil).items
        let card = try #require(model.lastScan)
        #expect(card.id == own.max(by: { $0.detectedAt < $1.detectedAt })?.id)
        #expect(card.ownerDeviceId == "dev_mom")
    }

    /// protected/Home/warning 1363:12167 and the decided frames (1373:13100, 1373:12376): a warning or a site the
    /// guardian already decided still takes the card for a day.
    @Test(arguments: [MockRepository.Scenario.protectedWarning, .protectedWarningSafe, .protectedBlockedScam])
    func cardTakesWarningsAndDecidedSites(_ scenario: MockRepository.Scenario) async throws {
        let model = model(scenario: scenario)
        await model.refresh()
        let card = try #require(model.cardScan)
        #expect(card.id == "home-card")
        #expect(!model.recent.contains { $0.id == card.id })
    }

    @Test func noCardWhenNothingHappenedToday() async {
        let model = model(scenario: .protectedQuiet)
        await model.refresh()
        #expect(model.cardScan == nil)
        #expect(model.recent.count == 3)
    }

    @Test func recentComesFromOwnScans() async throws {
        let repository = MockRepository(mode: .protected, latency: .zero)
        let model = ShieldModel(repository: repository, extensionStatus: { .off(lastSeen: nil) })
        await model.refresh()
        let own = try await repository.scans(owner: .me, status: nil, cursor: nil).items
        #expect(model.recent.count == min(own.count, ShieldModel.recentCount))
        #expect(model.recent.map(\.detectedAt) == model.recent.map(\.detectedAt).sorted(by: >))
    }

    @Test func cardOnlyForTheLastDay() async throws {
        let repository = MockRepository(mode: .protected, latency: .zero)
        let probe = ShieldModel(repository: repository, extensionStatus: { .off(lastSeen: nil) })
        await probe.refresh()
        let blocked = try #require(probe.lastScan)
        let soon = ShieldModel(repository: repository, extensionStatus: { .off(lastSeen: nil) }, now: { blocked.detectedAt.addingTimeInterval(60) })
        await soon.refresh()
        #expect(soon.cardScan?.id == blocked.id)
        // The big card's site is not listed twice.
        #expect(!soon.recent.contains { $0.id == blocked.id })
        let later = ShieldModel(repository: repository, extensionStatus: { .off(lastSeen: nil) },
                                now: { blocked.detectedAt.addingTimeInterval(ShieldModel.cardWindow + 60) })
        await later.refresh()
        #expect(later.cardScan == nil)
    }

    @Test func nothingBlockedYet() async {
        let model = model(scenario: .empty)
        await model.refresh()
        #expect(model.state == .loaded)
        #expect(model.lastScan == nil)
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
        let blocked = try #require(model.lastScan)
        repository.failure = RepositoryError.network
        await model.refresh()
        #expect(model.state == .loaded)
        #expect(model.lastScan == blocked)
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
        #expect(model.cardScan?.id == "scan-0")
        #expect(model.recent.map(\.id) == ["scan-1", "scan-2", "scan-3"])
    }

    @Test func onlyTheBlockedCardLeavesTheListEmpty() async throws {
        let now = now
        let model = ShieldModel(repository: try await repository(scans: 1), extensionStatus: { .off(lastSeen: nil) }, now: { now })
        await model.refresh()
        #expect(model.cardScan?.id == "scan-0")
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
