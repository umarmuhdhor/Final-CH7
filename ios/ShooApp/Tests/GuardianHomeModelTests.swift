import Foundation
import Testing
@testable import Shoo

@MainActor
struct GuardianHomeModelTests {
    /// A few hours after the newest fixture scan (2026-10-21T04:05:00Z).
    nonisolated static let fixtureNow = Date(timeIntervalSince1970: 1_792_584_000) // 2026-10-21T12:00:00Z

    func settings() throws -> AppSettings {
        AppSettings(defaults: try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)")))
    }

    func model(
        repository: any ShooRepository = MockRepository(mode: .guardian, latency: .zero),
        settings: AppSettings,
        now: Date = fixtureNow,
        scope: GuardianHomeModel.Scope = .family,
        extensionStatus: ExtensionStatus = .active(lastSeen: nil)
    ) -> GuardianHomeModel {
        GuardianHomeModel(repository: repository, settings: settings, scope: scope, extensionStatus: { extensionStatus }, now: { now })
    }

    @Test func newestUndecidedFamilySiteDrivesTheState() async throws {
        let model = model(settings: try settings())
        await model.refresh()
        #expect(model.state == .loaded)
        // Mom's blocked 92 % site; the guardian's own warning (dev_me) never gets a card.
        #expect(model.pendingScan?.domain == "bca-verifikasi.site")
        #expect(model.level == .danger)
        #expect(model.canDecide)
    }

    @Test func closingTheCardMovesOnAndIsRemembered() async throws {
        let settings = try settings()
        let model = model(settings: settings)
        await model.refresh()
        model.dismissPending()
        #expect(model.pendingScan?.domain == "promo-undian-shopee.click")
        #expect(model.level == .warning)
        model.dismissPending()
        #expect(model.pendingScan == nil)
        #expect(model.level == .normal)

        // A new screen (relaunch) keeps both cards closed.
        let again = self.model(settings: settings)
        await again.refresh()
        #expect(again.level == .normal)
    }

    @Test func sitesOlderThanADayGetNoCard() async throws {
        let model = model(settings: try settings(), now: Self.fixtureNow.addingTimeInterval(2 * 24 * 60 * 60))
        await model.refresh()
        #expect(model.pendingScan == nil)
        #expect(model.level == .normal)
    }

    @Test func personalLevelFollowsTheLastDay() async throws {
        let repository = MockRepository(mode: .guardian, latency: .zero)
        let scans = try await repository.scans(owner: .me, status: nil, cursor: nil).items
        let warning = try #require(scans.first { $0.status == .warning })

        let fresh = model(repository: repository, settings: try settings(), now: warning.detectedAt.addingTimeInterval(60), scope: .personal)
        await fresh.refresh()
        #expect(fresh.level == .warning)

        let later = model(repository: repository, settings: try settings(), now: warning.detectedAt.addingTimeInterval(2 * 24 * 60 * 60), scope: .personal)
        await later.refresh()
        #expect(later.level == .normal)
    }

    @Test func scamCardOnlyOnThePersonalSide() async throws {
        let repository = MockRepository(mode: .guardian, scenario: .figma, latency: .zero)
        let personal = model(repository: repository, settings: try settings(), scope: .personal)
        await personal.refresh()
        #expect(personal.scamCases == MockScenarios.scamCases)
        let family = model(repository: repository, settings: try settings(), scope: .family)
        await family.refresh()
        #expect(family.scamCases.isEmpty)
    }

    @Test func recentListsTheMembersSites() async throws {
        let model = model(settings: try settings())
        await model.refresh()
        // Members' sites only, newest first (GD-05): the guardian's own scans stay on the personal side.
        let members = model.scans.filter { $0.ownerDeviceId != MockRepository.guardianProfile.deviceId }
        #expect(model.recent.map(\.id) == Array(members.prefix(GuardianHomeModel.recentCount)).map(\.id))
    }

    @Test func personalHomeShowsOnlyOwnScansAndNoCard() async throws {
        let model = model(settings: try settings(), scope: .personal)
        await model.refresh()
        #expect(model.state == .loaded)
        #expect(!model.scans.isEmpty)
        #expect(model.scans.allSatisfy { $0.ownerDeviceId == MockRepository.guardianProfile.deviceId })
        #expect(model.pendingScan == nil)
        #expect(!model.hasNoFamily)
        // Someone is looked after: no "Mode Terawasi" card.
        #expect(!model.members.isEmpty)
        #expect(!model.showsSupervisedCard)
    }

    @Test func personalHomeOffersSupervisedModeUntilClosed() async throws {
        let settings = try settings()
        let model = model(repository: MockRepository(mode: .guardian, scenario: .homePribadiAlone, latency: .zero),
                          settings: settings, scope: .personal)
        await model.refresh()
        #expect(model.showsSupervisedCard)
        model.dismissSupervisedCard()
        #expect(!model.showsSupervisedCard)
        #expect(settings.supervisedCardDismissed)
    }

    @Test func familyHomeShowsAtMostThreePeople() async throws {
        let model = model(repository: MockRepository(mode: .guardian, scenario: .threeMembers, latency: .zero), settings: try settings())
        await model.refresh()
        #expect(model.shownMembers.count <= FamilyShieldModel.maxMembers)
        #expect(!model.hasNoFamily)
        let empty = self.model(repository: MockRepository(mode: .guardian, scenario: .empty, latency: .zero), settings: try settings())
        await empty.refresh()
        #expect(empty.hasNoFamily)
    }

    @Test func verdictOnABlockedSiteClearsTheCard() async throws {
        let model = model(settings: try settings())
        await model.refresh()
        await model.decide(.notSafe)
        #expect(!model.verdictFailed)
        #expect(model.scans.first { $0.domain == "bca-verifikasi.site" }?.verdict?.value == .notSafe)
        #expect(model.pendingScan?.domain == "promo-undian-shopee.click")
    }

    /// K8 (F-A15): a saved Home verdict tells the app (Activity reloads when it shows again); a failed one does not.
    @Test func onlyASavedVerdictTellsTheApp() async throws {
        var told = 0
        let failing = GuardianHomeModel(
            repository: StubRepository(verdictFailures: 1), settings: try settings(), scope: .family,
            extensionStatus: { .active(lastSeen: nil) }, now: { Self.fixtureNow }, onVerdictSaved: { told += 1 }
        )
        await failing.refresh()
        await failing.decide(.notSafe)
        #expect(failing.verdictFailed)
        #expect(told == 0)
        await failing.decide(.notSafe)
        #expect(!failing.verdictFailed)
        #expect(told == 1)
    }

    /// GD-07 (#190, #191): a warning site takes a verdict too.
    @Test func verdictOnAWarningSiteIsSaved() async throws {
        let model = model(settings: try settings())
        await model.refresh()
        model.dismissPending()
        #expect(model.level == .warning)
        #expect(model.canDecide)
        await model.decide(.safe)
        #expect(!model.verdictNotAllowed)
        #expect(!model.verdictFailed)
        #expect(model.scans.first { $0.domain == "promo-undian-shopee.click" }?.verdict?.value == .safe)
    }

    /// K7 (F-N1): a verdict lands on the decided scan only. Bayu's older visit to the same link keeps its
    /// own state until a refresh brings the server's answer.
    @Test func verdictLandsOnTheDecidedScanOnly() async throws {
        // Picked by id, never by order: the figma "today" times are Jakarta times clamped to the clock, so on a
        // UTC runner the three newest rows can share one timestamp and swap places.
        let repository = MockRepository(mode: .guardian, scenario: .figma, latency: .zero)
        let target = try await repository.scan(id: "figma-warning-72")
        let settings = try settings()
        let model = model(repository: repository, settings: settings, now: target.detectedAt.addingTimeInterval(60))
        await model.refresh()
        for scan in model.scans where scan.id != target.id { settings.dismissHomeScan(scan.id) }
        let decided = try #require(model.pendingScan)
        try #require(decided.id == "figma-warning-72")
        let untouched = model.scans.filter { $0.id != decided.id }
        try #require(untouched.contains { $0.ownerDeviceId == decided.ownerDeviceId && $0.domain == decided.domain })

        await model.decide(.safe)

        #expect(model.scans.first { $0.id == decided.id }?.verdict?.value == .safe)
        #expect(model.scans.filter { $0.id != decided.id } == untouched)
    }

    /// F-A4: a Home refresh that read the list before the verdict must not bring the decided card back.
    @Test func homeVerdictIsNotUndoneByAnOlderRefresh() async throws {
        let repository = GatedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        let model = model(repository: repository, settings: try settings())
        await model.refresh()
        let decided = try #require(model.pendingScan)

        await repository.hold(.first)
        async let refresh: Void = model.refresh()
        await repository.waitUntilHeld() // the list is read, the verdict is not saved yet
        await model.decide(.notSafe)
        await repository.release()
        await refresh

        #expect(model.scans.first { $0.id == decided.id }?.verdict?.value == .notSafe, "older refresh wiped the verdict just made")
        #expect(model.pendingScan?.id != decided.id)
    }

    /// A refresh that starts after the verdict was saved takes the server's list as it is.
    @Test func refreshAfterTheVerdictTakesTheServerList() async throws {
        let repository = MockRepository(mode: .guardian, latency: .zero)
        let model = model(repository: repository, settings: try settings())
        await model.refresh()
        let decided = try #require(model.pendingScan)
        await model.decide(.notSafe)
        // Changed on the server since (another Guardian device, or the Detail screen).
        let replaced = try await repository.setVerdict(scanId: decided.id, value: .safe)
        await model.refresh()
        #expect(model.scans.first { $0.id == decided.id }?.verdict == replaced)
    }

    @Test func failureShowsError() async throws {
        let model = model(repository: FailingRepository(), settings: try settings())
        await model.refresh()
        #expect(model.state == .failed)
    }

    @Test func failedRefreshKeepsWhatIsShown() async throws {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        let model = model(repository: repository, settings: try settings())
        await model.refresh()
        repository.failure = RepositoryError.network
        await model.refresh()
        #expect(model.state == .loaded)
        #expect(model.scans.count == 5)
    }

    @Test func extensionStatusComesFromTheReader() async throws {
        let model = model(settings: try settings(), extensionStatus: .off(lastSeen: nil, reason: .switchedOff))
        await model.refresh()
        #expect(!model.extensionStatus.isActive)
    }

    @Test func personalPagingStopsPastTheLastDayFamilyReadsAll() async throws {
        let base = MockRepository(mode: .guardian, latency: .zero)
        let template = try #require(try await base.scans(owner: .me, status: nil, cursor: nil).items.first)
        let now = Self.fixtureNow
        // 60 scans an hour apart, 10 a page: the last day ends in the third page.
        let scans = (0..<60).map { index in
            var scan = template
            scan.id = "scan-\(index)"
            scan.detectedAt = now.addingTimeInterval(-Double(index + 1) * 3600)
            return scan
        }
        func repository() -> CountingScansRepository {
            let repository = CountingScansRepository(base: base)
            for start in stride(from: 0, to: 60, by: 10) {
                repository.pages[start == 0 ? "" : String(start)] =
                    ScanPage(items: Array(scans[start..<start + 10]), nextCursor: start + 10 < 60 ? String(start + 10) : nil)
            }
            return repository
        }
        let personalRepository = repository()
        await model(repository: personalRepository, settings: try settings(), now: now, scope: .personal).refresh()
        #expect(personalRepository.scanCalls == 3)
        let familyRepository = repository()
        await model(repository: familyRepository, settings: try settings(), now: now, scope: .family).refresh()
        #expect(familyRepository.scanCalls == 6)
    }
}
