import Foundation
import Testing
@testable import Shoo

@MainActor
struct ProfileModelTests {
    func settings(mode: UserMode, language: AppLanguage = .english) -> AppSettings {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "profile.\(UUID().uuidString)")!)
        settings.chooseMode(mode)
        settings.language = language
        settings.onboardingCompleted = true
        settings.onboardingConnectPassed = true
        return settings
    }

    /// App Group stand-in, so tests never touch the real suite.
    func linked() -> LinkedAccountSettings {
        LinkedAccountSettings(defaults: UserDefaults(suiteName: "linked.\(UUID().uuidString)")!)
    }

    func model(mode: UserMode) -> (ProfileModel, MockRepository, AppSettings) {
        let repository = MockRepository(mode: mode, latency: .zero)
        let settings = settings(mode: mode)
        return (ProfileModel(repository: repository, settings: settings, linked: linked()), repository, settings)
    }

    @Test func guardianSeesNameMembersAndFamilyCode() async {
        let (model, _, _) = model(mode: .guardian)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.profile?.name == "Adhella")
        #expect(model.members.count == 2)
        #expect(model.showsFamilyCode)
    }

    @Test func protectedSeesGuardianButNoFamilyCode() async {
        let (model, _, _) = model(mode: .protected)
        await model.load()
        #expect(model.profile?.guardian?.name == "Adhella")
        #expect(model.members.isEmpty)
        #expect(!model.showsFamilyCode)
    }

    /// BH-29: the Account row says "Not connected" when no Guardian protects this phone, as the page it opens.
    @Test func connectionRowSaysWhetherAGuardianIsLinked() async {
        let (paired, _, _) = model(mode: .protected)
        await paired.load()
        #expect(L10n.string(paired.connectionRowTitle, language: .english) == "Connected")
        let repository = MockRepository(mode: .protected, scenario: .unpaired, latency: .zero)
        let alone = ProfileModel(repository: repository, settings: settings(mode: .protected), linked: linked())
        await alone.load()
        #expect(L10n.string(alone.connectionRowTitle, language: .english) == "Not connected")
    }

    /// QA 2026-11-10 #4: Maria, protected, disconnected by her guardian, got "You still protect someone".
    @Test func protectedWithoutAGuardianCanJoinAgain() async {
        let repository = MockRepository(mode: .protected, scenario: .unpaired, latency: .zero)
        let model = ProfileModel(repository: repository, settings: settings(mode: .protected), linked: linked())
        #expect(!model.canJoinAnotherFamily)  // not loaded yet: no answer before the server's
        await model.load()
        #expect(model.profile?.guardian == nil)
        #expect(model.hasNoGuardian)
        #expect(model.canJoinAnotherFamily)
    }

    @Test func protectedWithAGuardianCannotJoinAnotherFamily() async {
        let (model, _, _) = model(mode: .protected)
        await model.load()
        #expect(!model.hasNoGuardian)
        #expect(!model.canJoinAnotherFamily)
    }

    @Test func savingANameUsesTheOnboardingRule() async throws {
        let (model, repository, _) = model(mode: .guardian)
        await model.load()
        model.nameDraft = "   "
        #expect(model.nameProblem == .empty)
        #expect(await model.saveName() == false)
        model.nameDraft = String(repeating: "a", count: 21)
        #expect(model.nameProblem == .tooLong)
        #expect(await model.saveName() == false)
        #expect(try await repository.me().name == "Adhella")

        model.nameDraft = "  Alief "
        #expect(await model.saveName())
        #expect(model.profile?.name == "Alief")
        #expect(try await repository.me().name == "Alief")
    }

    @Test func failedNameSaveKeepsTheOldNameAndSaysSo() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        let model = ProfileModel(repository: repository, settings: settings(mode: .guardian))
        await model.load()
        repository.updateFailure = RepositoryError.network
        model.nameDraft = "Alief"
        #expect(await model.saveName() == false)
        #expect(model.profile?.name == "Adhella")
        #expect(model.nameError != nil)
    }

    @Test func languageChangesAtOnceAndReachesTheServer() async throws {
        let (model, repository, settings) = model(mode: .guardian)
        await model.load()
        model.chooseLanguage(.indonesian)
        #expect(settings.language == .indonesian)
        await model.languageTask?.value
        #expect(try await repository.me().language == "id")
    }

    @Test func lastLanguageChoiceWins() async throws {
        let (model, repository, settings) = model(mode: .guardian)
        await model.load()
        model.chooseLanguage(.indonesian)
        model.chooseLanguage(.english)
        await model.languageTask?.value
        #expect(settings.language == .english)
        #expect(try await repository.me().language == "en")
    }

    @Test func loadResendsALanguageTheServerMissed() async throws {
        let (model, repository, settings) = model(mode: .guardian)
        settings.language = .indonesian
        await model.load()
        await model.languageTask?.value
        #expect(try await repository.me().language == "id")
    }

    @Test func deleteMyDataStartsOverWithAFreshInstall() async throws {
        let (model, repository, settings) = model(mode: .guardian)
        await model.load()
        #expect(await model.deleteMyData())
        #expect(settings.mode == nil)
        #expect(!settings.onboardingCompleted)
        #expect(try await repository.familyMembers().isEmpty)
    }

    @Test func membersFailingStillShowsTheProfile() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        repository.membersFailure = RepositoryError.network
        let model = ProfileModel(repository: repository, settings: settings(mode: .guardian))
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.profile?.name == "Adhella")
        #expect(model.membersFailed)
        #expect(model.membersLoadFailure == .connection)
    }

    /// A-03 (fase 28m): a family list or profile the app can't read says "Something went wrong", not
    /// "Check your internet connection".
    @Test func aServerFailureShowsTheGeneralSentence() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        repository.membersFailure = RepositoryError.decoding
        let model = ProfileModel(repository: repository, settings: settings(mode: .guardian))
        await model.load()
        #expect(model.membersFailed)
        #expect(L10n.string(model.membersLoadFailure.message(connection: "Check your internet connection, then try again."),
                            language: .english) == "Something went wrong. Try again.")

        let failed = ProfileModel(repository: FailingRepository(error: .api(.internal, message: "HTTP 500")),
                                  settings: settings(mode: .guardian))
        await failed.load()
        #expect(failed.state == .failed)
        #expect(L10n.string(failed.loadFailure.message(connection: "Check your internet connection, then try again."),
                            language: .indonesian) == "Ada yang salah. Coba lagi.")
    }

    @Test func editingTheNameClearsTheOldError() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        let model = ProfileModel(repository: repository, settings: settings(mode: .guardian))
        await model.load()
        repository.updateFailure = RepositoryError.network
        model.nameDraft = "Alief"
        _ = await model.saveName()
        #expect(model.nameError != nil)
        model.nameDraft = "Alie"
        #expect(model.nameError == nil)
    }

    @Test func reloadKeepsANameBeingEdited() async {
        let (model, _, _) = model(mode: .guardian)
        await model.load()
        model.nameDraft = "Ali"
        await model.load()
        #expect(model.nameDraft == "Ali")
    }

    // MARK: PF-01 redesign

    /// 14 Sep 2026, the mock's `since` and members' `connectedAt`.
    static let start = Date(timeIntervalSince1970: 1_789_351_800)

    func redesignModel(
        mode: UserMode, familyMode: Bool = false, repository: (any ShooRepository)? = nil,
        notifications: (any NotificationPermission)? = nil, linked: LinkedAccountSettings? = nil
    ) -> ProfileModel {
        let settings = settings(mode: mode)
        settings.familyModeOn = familyMode
        return ProfileModel(
            repository: repository ?? MockRepository(mode: mode, latency: .zero), settings: settings,
            notifications: notifications, linked: linked ?? self.linked(),
            now: { Self.start.addingTimeInterval(2 * 86_400) }
        )
    }

    @Test(arguments: [
        (UserMode.guardian, false, ProfileModel.Variant.personal),
        (.guardian, true, .guardian),
        (.protected, false, .protected),
        (.protected, true, .protected),
    ])
    func variantFollowsModeAndFamilyMode(mode: UserMode, familyMode: Bool, expected: ProfileModel.Variant) {
        #expect(redesignModel(mode: mode, familyMode: familyMode).variant == expected)
    }

    @Test func familyModeSwitchIsGuardianOnly() {
        let personal = redesignModel(mode: .guardian)
        personal.setFamilyMode(true)
        #expect(personal.variant == .guardian)
        personal.setFamilyMode(false)
        #expect(personal.variant == .personal)

        let protected = redesignModel(mode: .protected)
        protected.setFamilyMode(true)
        #expect(protected.variant == .protected)
    }

    /// "Situs diperiksa" waits for the extension's counter (proposed App Group key `stats.checked`).
    @Test func personalStatsShowADashUntilTheExtensionCounts() async {
        let model = redesignModel(mode: .guardian)
        await model.load()
        #expect(model.stats(language: .english).map(\.value) == ["3", "3", "—"])
    }

    @Test func protectedStatsReadTheExtensionsCheckedCounter() async {
        let defaults = UserDefaults(suiteName: "linked.\(UUID().uuidString)")!
        defaults.set(1284, forKey: LinkedAccountSettings.Key.statsChecked)
        let model = redesignModel(mode: .protected, linked: LinkedAccountSettings(defaults: defaults))
        await model.load()
        #expect(model.stats(language: .english).map(\.value) == ["3", "3", "1,284"])
        #expect(model.stats(language: .indonesian).map(\.value) == ["3", "3", "1.284"])
        defaults.set(1300, forKey: LinkedAccountSettings.Key.statsChecked)
        model.linked.refresh()
        #expect(model.stats(language: .english).last?.value == "1,300")
    }

    @Test func guardianWithNobodyProtectedShowsNoStats() async throws {
        let repository = MockRepository(mode: .guardian, latency: .zero)
        for member in try await repository.familyMembers() { try await repository.removeMember(deviceId: member.deviceId) }
        let model = redesignModel(mode: .guardian, familyMode: true, repository: repository)
        await model.load()
        #expect(model.members.isEmpty)
        #expect(model.stats(language: .english).isEmpty)
    }

    @Test func guardianCardShowsForPribadiUntilClosedOrUsed() {
        let personal = redesignModel(mode: .guardian)
        #expect(personal.showsGuardianCard)
        personal.becomeGuardian()
        #expect(personal.variant == .guardian)
        #expect(!personal.showsGuardianCard)
        personal.setFamilyMode(false)
        #expect(personal.showsGuardianCard)
        personal.dismissGuardianCard()
        #expect(!personal.showsGuardianCard)
        #expect(!redesignModel(mode: .protected).showsGuardianCard)
    }

    /// Alief, 21 Nov 2026: X on Home's "Jadi Penjaga" card leaves Profile's Guardian card.
    @Test func closingHomesGuardianCardKeepsProfiles() {
        let settings = settings(mode: .guardian)
        settings.homeGuardianCardDismissed = true
        let personal = ProfileModel(repository: MockRepository(mode: .guardian, latency: .zero), settings: settings,
                                    notifications: nil, linked: linked(), now: { Self.start })
        #expect(personal.showsGuardianCard)
    }

    @Test func activeSinceIsTheRegistrationDay() async {
        let model = redesignModel(mode: .protected)
        await model.load()
        #expect(model.activeSince(language: .english) == "Active since September 14")
        #expect(model.activeSince(language: .indonesian) == "Aktif sejak 14 September")
    }

    @Test func linkedSwitchesDefaultOnAndClearWithTheAccount() async {
        let defaults = UserDefaults(suiteName: "linked.\(UUID().uuidString)")!
        let linked = LinkedAccountSettings(defaults: defaults)
        #expect(linked.autoSendLinks && linked.shareWarnings && linked.notifyLinkVerified)
        linked.autoSendLinks = false
        linked.notifyLinkVerified = false
        #expect(LinkedAccountSettings(defaults: defaults).autoSendLinks == false)
        #expect(LinkedAccountSettings(defaults: defaults).notifyLinkVerified == false)
        defaults.set(7, forKey: LinkedAccountSettings.Key.statsChecked)

        let model = redesignModel(mode: .protected, linked: linked)
        await model.load()
        #expect(await model.deleteMyData())
        for key in LinkedAccountSettings.Key.all { #expect(defaults.object(forKey: key) == nil) }
    }

    /// Days since the earliest member still connected, the members' blocked total (Mom 3 + Dad 1) and
    /// warning total (Figma 1115:14611).
    @Test func guardianStatsSumTheMembers() async {
        let model = redesignModel(mode: .guardian, familyMode: true)
        await model.load()
        let stats = model.stats(language: .english)
        #expect(stats.count == 3)
        #expect(stats.dropFirst().map(\.value) == ["4", "5"])
    }

    @Test func guardianWithoutMemberListShowsNoStats() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        repository.membersFailure = RepositoryError.network
        let model = redesignModel(mode: .guardian, familyMode: true, repository: repository)
        await model.load()
        #expect(model.stats(language: .english).isEmpty)
    }

    @Test func daysCountTodayAsOne() {
        let model = redesignModel(mode: .guardian)
        #expect(model.days(since: Self.start.addingTimeInterval(2 * 86_400)) == 1)
        #expect(model.days(since: Self.start) == 3)
        #expect(model.days(since: Self.start.addingTimeInterval(10 * 86_400)) == 1)
    }

    @Test func handleIsTheMode() async {
        let personal = redesignModel(mode: .guardian)
        await personal.load()
        #expect(personal.handle(language: .english) == "Personal mode")
        #expect(personal.handle(language: .indonesian) == "Mode Pribadi")

        let guardian = redesignModel(mode: .guardian, familyMode: true)
        await guardian.load()
        #expect(guardian.handle(language: .english) == "Guardian mode")
        #expect(guardian.handle(language: .indonesian) == "Mode Guardian")

        let protected = redesignModel(mode: .protected)
        await protected.load()
        #expect(protected.handle(language: .english).isEmpty)
    }

    @Test func deleteMessageSaysWhoIsAffected() async {
        let guardian = redesignModel(mode: .guardian, familyMode: true)
        await guardian.load()
        #expect(guardian.deleteMessage(language: .english).hasSuffix("2 people you protect will be disconnected."))

        let protected = redesignModel(mode: .protected)
        await protected.load()
        #expect(protected.deleteMessage(language: .english).hasSuffix("Adhella will no longer get your warnings."))

        let empty = redesignModel(mode: .guardian, repository: MockRepository(mode: .guardian, scenario: .empty, latency: .zero))
        await empty.load()
        #expect(empty.deleteMessage(language: .english).hasSuffix("can't be recovered."))
        #expect(empty.deleteMessage(language: .indonesian).hasPrefix("Semua data yang ada di aplikasi ini"))
    }

    /// PF-01 (#494): the family list loaded → the sheet counts the people who lose protection, in both languages.
    @Test(arguments: [(MockRepository.Scenario.oneMember, 1), (.standard, 2), (.threeMembers, 3)])
    func deleteMessageCountsTheLoadedFamily(scenario: MockRepository.Scenario, count: Int) async {
        let model = redesignModel(mode: .guardian, familyMode: true,
                                  repository: MockRepository(mode: .guardian, scenario: scenario, latency: .zero))
        await model.load()
        #expect(model.members.count == count)
        let people = count == 1 ? "person" : "people"
        #expect(model.deleteMessage(language: .english).hasSuffix(" \(count) \(people) you protect will be disconnected."))
        #expect(model.deleteMessage(language: .indonesian).hasSuffix(" \(count) orang yang kamu lindungi akan terputus."))
        #expect(!model.deleteMessage(language: .english).contains("Anyone you protect"))
    }

    /// PF-01 (#494, Umar's wording): the family list did not load → a Guardian still reads that the people they
    /// protect lose protection, without a count. Family mode off (Pribadi) keeps its members too (D Q5).
    @Test(arguments: [true, false])
    func deleteMessageWarnsAboutTheFamilyWhenItsListFailed(familyMode: Bool) async {
        let repository = MockRepository(mode: .guardian, latency: .zero, failures: ["familyMembers": .network])
        let model = redesignModel(mode: .guardian, familyMode: familyMode, repository: repository)
        await model.load()
        #expect(model.membersFailed)
        #expect(model.deleteMessage(language: .english).hasSuffix(" Anyone you protect will be disconnected."))
        #expect(model.deleteMessage(language: .indonesian).hasSuffix(" Semua orang yang kamu lindungi akan terputus."))
    }

    /// PF-01 (#494): a refresh that fails after the list loaded once: the sheet follows the failure card, not
    /// the old count (someone may have joined or left since).
    @Test func deleteMessageDropsAStaleCountWhenARefreshFails() async {
        let repository = MockRepository(mode: .guardian, latency: .zero, failures: ["familyMembers~1": .network])
        let model = redesignModel(mode: .guardian, familyMode: true, repository: repository)
        await model.load()
        #expect(model.deleteMessage(language: .english).hasSuffix("2 people you protect will be disconnected."))
        await model.load()
        #expect(model.membersFailed)
        #expect(model.deleteMessage(language: .english).hasSuffix(" Anyone you protect will be disconnected."))
    }

    /// PF-01 (#494): "Try again" on the family card reads the list again; the count comes back with it.
    @Test func deleteMessageCountsAgainOnceARetryLoadsTheList() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        repository.membersFailure = RepositoryError.network
        let model = redesignModel(mode: .guardian, familyMode: true, repository: repository)
        await model.load()
        #expect(model.deleteMessage(language: .english).hasSuffix(" Anyone you protect will be disconnected."))
        repository.membersFailure = nil
        await model.load()
        #expect(!model.membersFailed)
        #expect(model.deleteMessage(language: .english).hasSuffix(" 2 people you protect will be disconnected."))
    }

    /// PF-01 (#494): a profile refresh that fails stops before the family list, and Profile keeps showing the list it
    /// has, so the sheet keeps that count too.
    @Test func deleteMessageKeepsTheCountWhenOnlyAProfileRefreshFails() async {
        let repository = MockRepository(mode: .guardian, latency: .zero, failures: ["me~1": .network])
        let model = redesignModel(mode: .guardian, familyMode: true, repository: repository)
        await model.load()
        await model.load()
        #expect(model.state == .loaded)
        #expect(!model.membersFailed)
        #expect(model.deleteMessage(language: .english).hasSuffix(" 2 people you protect will be disconnected."))
    }

    /// PF-01 (#494): the profile itself failed, so the family list was never asked for: same general sentence.
    @Test func deleteMessageWarnsAboutTheFamilyWhenItWasNeverRead() async {
        let repository = MockRepository(mode: .guardian, latency: .zero, failures: ["me": .network])
        let model = redesignModel(mode: .guardian, familyMode: true, repository: repository)
        await model.load()
        #expect(model.state == .failed)
        #expect(model.deleteMessage(language: .english).hasSuffix(" Anyone you protect will be disconnected."))
    }

    /// PF-01 (#494): delete is never blocked (Apple 5.1.1(v)), whether the family list loaded or not.
    @Test(arguments: [false, true])
    func deleteWorksWhetherTheFamilyListLoadedOrNot(listFails: Bool) async throws {
        let repository = MockRepository(mode: .guardian, latency: .zero,
                                        failures: listFails ? ["familyMembers": .network] : [:])
        let settings = settings(mode: .guardian)
        settings.familyModeOn = true
        let model = ProfileModel(repository: repository, settings: settings, linked: linked())
        await model.load()
        #expect(model.membersFailed == listFails)
        #expect(await model.deleteMyData())
        #expect(model.actionError == nil)
        #expect(settings.mode == nil)
    }

    final class StubNotifications: NotificationPermission, @unchecked Sendable {
        var current: NotificationAuthorization
        let answer: NotificationAuthorization
        private(set) var requests = 0
        init(_ current: NotificationAuthorization, answer: NotificationAuthorization = .authorized) {
            self.current = current
            self.answer = answer
        }
        func status() async -> NotificationAuthorization { current }
        func request() async -> NotificationAuthorization {
            requests += 1
            current = answer
            return answer
        }
    }

    /// Not asked yet: the system prompt in the app. Asked before: only Settings can change it.
    @Test func notificationsAskInTheAppOnlyTheFirstTime() async {
        let fresh = StubNotifications(.notDetermined)
        let model = redesignModel(mode: .guardian, notifications: fresh)
        #expect(await model.notificationsTapped() == false)
        #expect(fresh.requests == 1)
        #expect(model.notificationStatus == .authorized)

        for status in [NotificationAuthorization.denied, .authorized] {
            let stub = StubNotifications(status)
            let model = redesignModel(mode: .guardian, notifications: stub)
            #expect(await model.notificationsTapped())
            #expect(stub.requests == 0)
        }
    }

    @Test func refreshReadsTheNotificationStatus() async {
        let model = redesignModel(mode: .protected, notifications: StubNotifications(.denied))
        await model.refreshNotifications()
        #expect(model.notificationStatus == .denied)
    }

    @Test func remindMarksTheMemberAndTooSoonSaysSo() async throws {
        let model = redesignModel(mode: .guardian, familyMode: true)
        await model.load()
        let dad = try #require(model.members.first { $0.deviceId == "dev_dad" })
        #expect(await model.remind(dad).map { L10n.string($0, language: .english) } == "Reminder sent to Dad")
        #expect(model.members.first { $0.deviceId == "dev_dad" }?.remindedAt != nil)
        #expect(await model.remind(dad).map { L10n.string($0, language: .english) } == "You already reminded Dad recently")
    }

    @Test func remindWithoutPushTokenExplains() async throws {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        repository.remindFailure = RepositoryError.api(.pushUnavailable, message: "No token")
        let model = redesignModel(mode: .guardian, familyMode: true, repository: repository)
        await model.load()
        let dad = try #require(model.members.first { $0.deviceId == "dev_dad" })
        #expect(await model.remind(dad).map { L10n.string($0, language: .english) } == "Dad hasn't turned on notifications")
        #expect(model.members.first { $0.deviceId == "dev_dad" }?.remindedAt == nil)
        // Shown on screen too, not only to VoiceOver.
        #expect(model.actionError.map { L10n.string($0, language: .english) } == "Dad hasn't turned on notifications")
    }

    /// The family list arrives after the profile: until then the section must not read as "no members".
    @Test func membersAreNotLoadedUntilTheListArrives() async {
        let model = redesignModel(mode: .guardian, familyMode: true)
        #expect(model.membersLoaded == false)
        await model.load()
        #expect(model.membersLoaded)
    }

    // MARK: PF-01 Notifikasi, Ubah foto, Punya kode undangan

    @Test func notificationSwitchChangesAtOnceAndReachesTheServer() async throws {
        let (model, repository, _) = model(mode: .guardian)
        await model.load()
        #expect(model.notificationSettings == .defaults)
        await model.updateNotifications(NotificationSettingsUpdate(weeklySummary: true, quietStart: "23:30"))
        #expect(model.notificationSettings.weeklySummary)
        #expect(model.notificationSettings.quietStart == "23:30")
        let saved = try #require(try await repository.me().notifications)
        #expect(saved.weeklySummary)
        #expect(saved.quietStart == "23:30")
        #expect(saved.blocked)
    }

    @Test func failedNotificationSaveGoesBackAndSaysSo() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        let model = ProfileModel(repository: repository, settings: settings(mode: .guardian))
        await model.load()
        repository.updateFailure = RepositoryError.network
        await model.updateNotifications(NotificationSettingsUpdate(warning: false))
        #expect(model.notificationSettings.warning)
        #expect(model.actionError != nil)
    }

    /// Fase 27i (F-A11/F-N5, K11): a slow switch that fails puts back only its own key, on top of what is on screen
    /// now. Another switch that saved meanwhile stays.
    @Test func failedSwitchRollsBackOnlyItsOwnKey() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        let gate = AsyncGate()
        repository.beforeUpdate = { update in
            guard update.notifications?.warning != nil else { return }
            await gate.hold()
            throw RepositoryError.network
        }
        let model = ProfileModel(repository: repository, settings: settings(mode: .guardian), linked: linked())
        await model.load()
        defer { gate.open() }
        let slow = Task { await model.updateNotifications(NotificationSettingsUpdate(warning: false)) }
        await gate.arrival()
        await model.updateNotifications(NotificationSettingsUpdate(blocked: false))
        gate.open()
        await slow.value
        #expect(model.notificationSettings.warning, "the failed switch goes back")
        #expect(!model.notificationSettings.blocked, "the switch that saved stays")
        #expect(model.actionError != nil)
    }

    /// PF-01: a reload (foreground, push) that read the profile before a switch was saved does not flip it back.
    @Test func aReloadOlderThanASwitchKeepsTheSwitch() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        let model = ProfileModel(repository: repository, settings: settings(mode: .guardian), linked: linked())
        await model.load()
        #expect(model.notificationSettings.blocked)
        let gate = AsyncGate()
        repository.beforeMe = { await gate.hold() }
        defer { gate.open() }
        let reload = Task { await model.load() }
        await gate.arrival()
        await model.updateNotifications(NotificationSettingsUpdate(blocked: false))
        gate.open()
        await reload.value
        #expect(!model.notificationSettings.blocked)
        #expect(model.actionError == nil)
    }

    /// K11: the failed update's key was changed again and saved meanwhile: the newer value stays.
    @Test func failedUpdateKeepsANewerValueOfTheSameKey() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        let gate = AsyncGate()
        repository.beforeUpdate = { update in
            guard update.notifications?.quietStart == "23:00" else { return }
            await gate.hold()
            throw RepositoryError.network
        }
        let model = ProfileModel(repository: repository, settings: settings(mode: .guardian), linked: linked())
        await model.load()
        defer { gate.open() }
        let slow = Task { await model.updateNotifications(NotificationSettingsUpdate(quietStart: "23:00")) }
        await gate.arrival()
        await model.updateNotifications(NotificationSettingsUpdate(quietStart: "21:00"))
        gate.open()
        await slow.value
        #expect(model.notificationSettings.quietStart == "21:00")
    }

    /// K11: off → on → off saved while the first "off" is still on its way, then that first one fails. The value
    /// on screen equals what it set, but newer updates own the key: it stays off, as on the server.
    @Test func failedUpdateKeepsTheKeyWhenANewerUpdateSetTheSameValue() async throws {
        let base = MockRepository(mode: .guardian, latency: .zero)
        let repository = DelayedScansRepository(base: base)
        let gate = AsyncGate()
        let held = HeldOnce()
        repository.beforeUpdate = { update in
            guard update.notifications?.warning == false, await held.take() else { return }
            await gate.hold()
            throw RepositoryError.network
        }
        let model = ProfileModel(repository: repository, settings: settings(mode: .guardian), linked: linked())
        await model.load()
        defer { gate.open() }
        let slow = Task { await model.updateNotifications(NotificationSettingsUpdate(warning: false)) }
        await gate.arrival()
        await model.updateNotifications(NotificationSettingsUpdate(warning: true))
        await model.updateNotifications(NotificationSettingsUpdate(warning: false))
        gate.open()
        await slow.value
        #expect(!model.notificationSettings.warning)
        #expect(try await base.me().notifications?.warning == false)
    }

    /// Fase 27i (F-N6, K11): start = end means "all day" on the server, which the sheet never offers.
    @Test(arguments: [("22:00", "06:00", true), ("00:00", "23:59", true), ("22:00", "22:00", false), ("00:00", "00:00", false)])
    func quietHoursSaveNeedsDifferentStartAndEnd(start: String, end: String, expected: Bool) {
        #expect(ProfileModel.canSaveQuietHours(start: start, end: end) == expected)
    }

    /// The model refuses a window with start = end too, whoever asks.
    @Test func quietHoursWithTheSameStartAndEndAreNotSent() async throws {
        let (model, repository, _) = model(mode: .guardian)
        await model.load()
        await model.updateNotifications(NotificationSettingsUpdate(quietStart: "06:00", quietEnd: "06:00"))
        #expect(model.notificationSettings.quietStart == "22:00")
        let saved = try #require(try await repository.me().notifications)
        #expect(saved.quietStart == "22:00")
        #expect(saved.quietEnd == "06:00")
    }

    @Test func choosingAnAvatarSavesIt() async throws {
        let (model, repository, _) = model(mode: .guardian)
        await model.load()
        let other = try #require(OnboardingAvatar.ids.first { $0 != model.profile?.avatarId })
        #expect(await model.chooseAvatar(other))
        #expect(model.profile?.avatarId == other)
        #expect(try await repository.me().avatarId == other)
    }

    @Test func failedAvatarSaveKeepsTheOldOne() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        let model = ProfileModel(repository: repository, settings: settings(mode: .guardian))
        await model.load()
        let before = model.profile?.avatarId
        repository.updateFailure = RepositoryError.network
        #expect(await model.chooseAvatar(OnboardingAvatar.ids.first { $0 != before } ?? "avatar_01") == false)
        #expect(model.profile?.avatarId == before)
        #expect(model.actionError != nil)
    }

    @Test func onlyAGuardianWithoutMembersCanJoinAnotherFamily() async {
        let (withMembers, _, _) = model(mode: .guardian)
        await withMembers.load()
        #expect(!withMembers.canJoinAnotherFamily)

        let empty = ProfileModel(repository: MockRepository(mode: .guardian, scenario: .empty, latency: .zero), settings: settings(mode: .guardian))
        await empty.load()
        #expect(empty.canJoinAnotherFamily)

        let (protected, _, _) = model(mode: .protected)
        await protected.load()
        #expect(!protected.canJoinAnotherFamily)
    }

    @Test func usernameIsTheNameWithoutSpaces() async {
        let (model, _, _) = model(mode: .guardian)
        await model.load()
        #expect(model.username == "@adhella")
    }

    /// A-08 (fase 28m): a member's heartbeat a few seconds ahead of this phone (a normal clock gap, the server
    /// allows 5 min) or at the same second reads "just now", not "in 0s" / "dlm 0 dtk".
    @Test(arguments: AppLanguage.allCases)
    func BUG_A08_memberLastSeenAheadOfThisPhoneReadsAsJustNow(_ language: AppLanguage) {
        let now = Date(timeIntervalSince1970: 1_792_584_000)
        let justNow = language == .english ? "just now" : "baru saja"
        #expect(MemberText.ago(now.addingTimeInterval(3), now: now, language: language) == justNow)
        #expect(MemberText.ago(now, now: now, language: language) == justNow)
        #expect(MemberText.ago(now.addingTimeInterval(-0.5), now: now, language: language) == justNow)
        // One second ago is the first time that reads as a time ago.
        #expect(MemberText.ago(now.addingTimeInterval(-1), now: now, language: language) != justNow)
        // Guard: two minutes ago still reads as a time ago.
        let past = MemberText.ago(now.addingTimeInterval(-120), now: now, language: language)
        #expect(past != justNow)
        #expect(past.contains("2"))
    }
}
