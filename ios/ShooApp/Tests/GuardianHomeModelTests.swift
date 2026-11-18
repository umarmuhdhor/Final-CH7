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
        #expect(personal.scamCases.map(\.id) == MockScenarios.scamCases(now: Date()).map(\.id))
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

    /// "Gagal menyimpan" → "Coba lagi" (Figma 1665:3183) sends the same answer again.
    @Test func tryAgainResendsTheLastAnswer() async throws {
        let model = GuardianHomeModel(
            repository: StubRepository(verdictFailures: 1), settings: try settings(), scope: .family,
            extensionStatus: { .active(lastSeen: nil) }, now: { Self.fixtureNow }
        )
        await model.refresh()
        let scan = try #require(model.pendingScan)
        await model.decide(.safe)
        #expect(model.verdictFailed)
        #expect(model.lastDecision == .safe)
        await model.retryDecision()
        #expect(!model.verdictFailed)
        #expect(model.scans.first { $0.id == scan.id }?.verdict?.value == .safe)
    }

    /// Review #475 (5): the answer goes to the site the sheet was opened for, even when the card moved on.
    @Test func reasonSheetAnswersTheSiteItWasOpenedFor() async throws {
        let model = model(settings: try settings())
        await model.refresh()
        let first = try #require(model.pendingScan)
        model.dismissPending()
        #expect(model.pendingScan?.id != first.id)
        #expect(await model.decide(.safe, notes: "reasons: other", scanId: first.id))
        #expect(model.scans.first { $0.id == first.id }?.verdict?.value == .safe)
        #expect(model.pendingScan?.verdict == nil)
    }

    /// Review #475 (4): "not allowed" closes the sheet; the card says why, not "check your connection".
    @Test func notAllowedClosesTheSheet() async throws {
        let model = GuardianHomeModel(
            repository: StubRepository(verdictFailures: 1, verdictError: .api(.verdictNotAllowed, message: "no")),
            settings: try settings(), scope: .family, extensionStatus: { .active(lastSeen: nil) }, now: { Self.fixtureNow }
        )
        await model.refresh()
        #expect(await model.decide(.safe, notes: "reasons: other"))
        #expect(model.verdictNotAllowed)
        #expect(!model.verdictFailed)
    }

    /// An error belongs to the card it happened on: when another site's card takes the place (a refresh dropped
    /// the first), it shows no "Couldn't save" or "Can't be marked yet", and its "Try again" can't resend the old answer.
    @Test(arguments: [RepositoryError.network, RepositoryError.api(.verdictNotAllowed, message: "no")])
    func anErrorStaysWithItsCard(error: RepositoryError) async throws {
        let settings = try settings()
        let model = GuardianHomeModel(
            repository: StubRepository(verdictFailures: 1, verdictError: error),
            settings: settings, scope: .family, extensionStatus: { .active(lastSeen: nil) }, now: { Self.fixtureNow }
        )
        await model.refresh()
        let first = try #require(model.pendingScan)
        await model.decide(.notSafe)
        #expect(model.verdictFailed || model.verdictNotAllowed)
        // The card moves on without the X (as a refresh that no longer lists it does).
        settings.dismissHomeScan(first.id)
        #expect(model.pendingScan != nil)
        #expect(model.pendingScan?.id != first.id)
        #expect(!model.verdictFailed)
        #expect(!model.verdictNotAllowed)
    }

    /// #476: `verdict_locked` means the link is already marked safe elsewhere: the sheet closes, no "Couldn't save".
    @Test func lockedClosesTheSheet() async throws {
        let model = GuardianHomeModel(
            repository: StubRepository(verdictFailures: 1, verdictError: .api(.verdictLocked, message: "locked")),
            settings: try settings(), scope: .family, extensionStatus: { .active(lastSeen: nil) }, now: { Self.fixtureNow }
        )
        await model.refresh()
        #expect(await model.decide(.safe, notes: "reasons: other"))
        #expect(!model.verdictFailed)
        #expect(!model.verdictNotAllowed)
    }

    /// GD-07: "Aman" from the Home card sends the reasons as `notes`.
    @Test func safeSendsTheReasons() async throws {
        let repository = MockRepository(mode: .guardian, latency: .zero)
        let model = model(repository: repository, settings: try settings())
        await model.refresh()
        #expect(await model.decide(.safe, notes: "reasons: official_site"))
        #expect(await repository.lastVerdictNotes == "reasons: official_site")
    }

    /// BH-27: a verdict on a card whose scan was deleted (404) drops that card, as Detail shows "gone",
    /// instead of a connection error on a card that can never be saved.
    @Test func verdictOnADeletedScanDropsTheCard() async throws {
        let model = GuardianHomeModel(
            repository: StubRepository(verdictFailures: 1, verdictError: .api(.notFound, message: "gone")), settings: try settings(),
            scope: .family, extensionStatus: { .active(lastSeen: nil) }, now: { Self.fixtureNow }
        )
        await model.refresh()
        let gone = try #require(model.pendingScan)
        await model.decide(.notSafe)
        #expect(!model.verdictFailed)
        #expect(model.pendingScan?.id != gone.id)
        #expect(!model.scans.contains { $0.id == gone.id })
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

    /// A-03 (fase 28m): a list the app can't read says "Something went wrong", not "Check your connection".
    @Test(arguments: [RepositoryError.decoding, .api(.internal, message: "HTTP 500")])
    func aServerFailureShowsTheGeneralSentence(_ error: RepositoryError) async throws {
        let model = model(repository: FailingRepository(error: error), settings: try settings())
        await model.refresh()
        #expect(model.state == .failed)
        #expect(L10n.string(model.loadFailure.message(connection: "Check your connection."), language: .english)
            == "Something went wrong. Try again.")
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

    /// A-01 (fase 28a, K1, D-alief-A12): a failed refresh keeps the loaded Home and says it may be old; the next
    /// good refresh clears that. Before: "Family protected!" stayed with no sign while a member's blocked site waited.
    @Test func BUG_A01_guardianHomeSaysItMayBeOldAfterAFailedRefresh() async throws {
        for scope in [GuardianHomeModel.Scope.family, .personal] {
            let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
            let model = model(repository: repository, settings: try settings(), scope: scope)
            await model.refresh()
            #expect(model.state == .loaded)
            #expect(!model.refreshFailed)
            let shown = model.scans

            repository.failure = RepositoryError.network
            await model.refresh()
            #expect(model.state == .loaded, "\(scope)")
            #expect(model.scans == shown, "\(scope): the old content stays")
            #expect(model.refreshFailed, "\(scope): says it may be old")

            repository.failure = nil
            await model.refresh()
            #expect(!model.refreshFailed, "\(scope): a good refresh clears it")
        }
    }

    /// A first load that fails is the error card, not "may be old" (nothing was shown).
    @Test func firstLoadFailureIsNotARefreshFailure() async throws {
        let model = model(repository: FailingRepository(), settings: try settings())
        await model.refresh()
        #expect(model.state == .failed)
        #expect(!model.refreshFailed)
    }

    /// A-06 (fase 28a, K3): before the first read of the extension's status Pribadi Home has no answer yet,
    /// so the hero cannot say "You're not protected yet".
    @Test func BUG_A06_personalHomeHasNotReadTheExtensionBeforeTheFirstRefresh() async throws {
        let model = model(settings: try settings(), scope: .personal, extensionStatus: .active(lastSeen: Date()))
        #expect(!model.extensionChecked)
        await model.refresh()
        #expect(model.extensionChecked)
        #expect(model.extensionStatus.isActive)
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

    /// Family pages for OPT-02 (fase 28i): `rows[n]` is page n, each row `(owner, hours ago, decided)`. Pages are
    /// newest first, like the server's, and each one but the last points at the next.
    private func familyPages(_ rows: [[(owner: String, hoursAgo: Double, decided: Bool)]]) async throws -> CountingScansRepository {
        let base = MockRepository(mode: .guardian, latency: .zero)
        let template = try #require(try await base.scans(owner: .family, status: nil, cursor: nil).items.first)
        let repository = CountingScansRepository(base: base)
        for (number, page) in rows.enumerated() {
            let items = page.enumerated().map { index, row in
                var scan = template
                scan.id = "p\(number)-\(index)"
                scan.ownerDeviceId = row.owner
                scan.status = .warning
                scan.detectedAt = Self.fixtureNow.addingTimeInterval(-row.hoursAgo * 3600)
                scan.verdict = row.decided
                    ? Verdict(value: .safe, byDeviceId: "dev_me", byName: "Adhella", decidedAt: Self.fixtureNow)
                    : nil
                return scan
            }
            repository.pages[number == 0 ? "" : "c\(number)"] =
                ScanPage(items: items, nextCursor: number + 1 < rows.count ? "c\(number + 1)" : nil)
        }
        return repository
    }

    private var me: String { MockRepository.guardianProfile.deviceId }

    /// OPT-02 (a): page 1 already reaches past the last day and holds 3 members' rows: Family Home has its pending
    /// card and its 3 rows, so it asks for no second page. Before: every page, up to 10 per foreground.
    @Test func BUG_OPT02_familyHomeStopsAfterAPagePastTheLastDayWithThreeMemberRows() async throws {
        let repository = try await familyPages([
            [("dev_mom", 1, false), ("dev_dad", 2, true), ("dev_mom", 3, true), ("dev_dad", 30, true)],
            [("dev_mom", 40, false), ("dev_dad", 50, false)],
            [("dev_mom", 60, false)],
        ])
        let model = model(repository: repository, settings: try settings())
        await model.refresh()
        #expect(repository.scanCalls == 1)
        #expect(model.pendingScan?.id == "p0-0")
        #expect(model.recent.map(\.id) == ["p0-0", "p0-1", "p0-2"])
    }

    /// OPT-02 (b), guard: the guardian's own rows are not listed on Family Home (`recent`), so they don't count
    /// towards the 3 rows: a page 1 of own rows only goes on to page 2.
    @Test func familyHomeReadsOnWhenPageOneHoldsOnlyTheGuardiansOwnRows() async throws {
        let repository = try await familyPages([
            [(me, 1, false), (me, 2, false), (me, 3, false), (me, 30, false)],
            [("dev_mom", 31, false), ("dev_dad", 32, true), ("dev_mom", 33, true)],
        ])
        let model = model(repository: repository, settings: try settings())
        await model.refresh()
        #expect(repository.scanCalls == 2)
        #expect(model.recent.map(\.id) == ["p1-0", "p1-1", "p1-2"])
        #expect(model.pendingScan == nil, "page 2 is older than a day")
    }

    /// OPT-02 (c), guard: 3 members' rows are not enough to stop while the page is still inside the last day: a
    /// member's undecided site on page 2, 20 hours old, still gets the card. Page 1's decided rows don't hide it.
    @Test func familyHomeStillFindsAPendingSiteOnPageTwo() async throws {
        let repository = try await familyPages([
            [("dev_mom", 1, true), ("dev_dad", 2, true), ("dev_mom", 3, true), ("dev_dad", 4, true)],
            [("dev_mom", 20, false), ("dev_dad", 30, false)],
            [("dev_mom", 40, false)],
        ])
        let model = model(repository: repository, settings: try settings())
        await model.refresh()
        #expect(model.pendingScan?.id == "p1-0")
        #expect(model.recent.map(\.id) == ["p0-0", "p0-1", "p0-2"])
        // `>= 2`: on main Family read every page (3 here); this guard holds there and after the fix.
        #expect(repository.scanCalls >= 2)
    }

    /// A last day busier than 10 pages still stops at `maxPages` (a runaway cursor).
    @Test func familyHomeReadsAtMostTenPages() async throws {
        let repository = try await familyPages((0..<12).map { [("dev_mom", Double($0) + 1, false)] })
        await model(repository: repository, settings: try settings()).refresh()
        #expect(repository.scanCalls == GuardianHomeModel.maxPages)
    }

    /// PF-01: a scan's owner shows their picked avatar: a member's from the family list, the guardian's own
    /// from `GET /devices/me`; anyone else (or before the load) gets `nil`, the neutral person.
    @Test func scanOwnerAvatarComesFromTheFamilyOrTheGuardianThemself() async throws {
        let model = model(settings: try settings())
        #expect(model.avatarId(forOwner: "dev_mom") == nil)
        await model.refresh()
        #expect(model.avatarId(forOwner: "dev_mom") == "avatar_03")
        #expect(model.avatarId(forOwner: "dev_dad") == "avatar_07")
        #expect(model.avatarId(forOwner: MockRepository.guardianProfile.deviceId) == MockRepository.guardianProfile.avatarId)
        #expect(model.avatarId(forOwner: "dev_gone") == nil)
    }
}
