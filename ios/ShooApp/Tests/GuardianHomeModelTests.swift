import Foundation
import Testing
@testable import Shoo

@MainActor
struct GuardianHomeModelTests {
    /// A few hours after the newest fixture scan (2026-10-21T04:05:00Z).
    static let fixtureNow = Date(timeIntervalSince1970: 1_792_584_000) // 2026-10-21T12:00:00Z

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

    @Test func statsCountTheFamilyScans() async throws {
        let model = model(settings: try settings())
        await model.refresh()
        let lastDay = model.scans.filter { $0.detectedAt >= Self.fixtureNow.addingTimeInterval(-24 * 60 * 60) }.count
        #expect(model.stats == .init(blocked: 3, warnings: 2, suspiciousHosts: 5, recentScans: lastDay))
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
        #expect(model.members.isEmpty)
        #expect(!model.hasNoFamily)
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
}
