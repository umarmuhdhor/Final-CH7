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

    func model(mode: UserMode) -> (ProfileModel, MockRepository, AppSettings) {
        let repository = MockRepository(mode: mode, latency: .zero)
        let settings = settings(mode: mode)
        return (ProfileModel(repository: repository, settings: settings), repository, settings)
    }

    @Test func guardianSeesNameMembersAndFamilyCode() async {
        let (model, _, _) = model(mode: .guardian)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.profile?.name == "Adhella")
        #expect(model.members.count == 2)
        #expect(model.showsFamilyCode)
        #expect(!model.showsDisconnect)
    }

    @Test func protectedSeesGuardianAndDisconnectButNoFamilyCode() async {
        let (model, _, _) = model(mode: .protected)
        await model.load()
        #expect(model.profile?.guardian?.name == "Adhella")
        #expect(model.members.isEmpty)
        #expect(!model.showsFamilyCode)
        #expect(model.showsDisconnect)
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

    @Test func disconnectSendsProtectedBackToConnect() async throws {
        let (model, repository, settings) = model(mode: .protected)
        var ended = false
        model.onSessionEnd = { ended = true }
        await model.load()
        #expect(await model.disconnect())
        #expect(ended)
        #expect(try await repository.me().guardian == nil)
        #expect(!settings.onboardingCompleted)
        #expect(!settings.onboardingConnectPassed)
        #expect(settings.mode == .protected)
    }

    @Test func deleteMyDataStartsOverWithAFreshInstall() async throws {
        let (model, repository, settings) = model(mode: .guardian)
        await model.load()
        #expect(await model.deleteMyData())
        #expect(settings.mode == nil)
        #expect(!settings.onboardingCompleted)
        #expect(try await repository.familyMembers().isEmpty)
    }

    @Test func disconnectThatAlreadyHappenedCountsAsDone() async throws {
        let (model, repository, settings) = model(mode: .protected)
        await model.load()
        try await repository.leaveGuardian()
        #expect(await model.disconnect())
        #expect(!settings.onboardingCompleted)
    }

    @Test func membersFailingStillShowsTheProfile() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        repository.membersFailure = RepositoryError.network
        let model = ProfileModel(repository: repository, settings: settings(mode: .guardian))
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.profile?.name == "Adhella")
        #expect(model.membersFailed)
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
        notifications: (any NotificationPermission)? = nil
    ) -> ProfileModel {
        let settings = settings(mode: mode)
        settings.familyModeOn = familyMode
        return ProfileModel(
            repository: repository ?? MockRepository(mode: mode, latency: .zero), settings: settings,
            notifications: notifications, now: { Self.start.addingTimeInterval(2 * 86_400) }
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

    @Test func personalStatsAreDaysBlockedWarnings() async {
        let model = redesignModel(mode: .guardian)
        await model.load()
        #expect(model.stats(language: .english).map(\.value) == ["3", "3", "5"])
    }

    @Test func protectedStatsAreBlockedAndOpened() async {
        let model = redesignModel(mode: .protected)
        await model.load()
        #expect(model.stats(language: .english).map(\.value) == ["3", "1"])
    }

    /// People, days since the earliest member still connected, the members' blocked total (Mom 3 + Dad 1).
    @Test func guardianStatsSumTheMembers() async {
        let model = redesignModel(mode: .guardian, familyMode: true)
        await model.load()
        #expect(model.stats(language: .english).map(\.value) == ["2", "3", "4"])
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

    @Test func handleIsTheNameInLowerCaseWithTheMode() async {
        let personal = redesignModel(mode: .guardian)
        await personal.load()
        #expect(personal.handle(language: .english) == "@adhella · Personal")
        #expect(personal.handle(language: .indonesian) == "@adhella · Pribadi")

        let guardian = redesignModel(mode: .guardian, familyMode: true)
        await guardian.load()
        #expect(guardian.handle(language: .english) == "@adhella · Guardian")

        let protected = redesignModel(mode: .protected)
        await protected.load()
        #expect(protected.handle(language: .english) == "@mom")
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
        #expect(empty.deleteMessage(language: .english).hasSuffix("This can't be undone."))
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
    }
}
