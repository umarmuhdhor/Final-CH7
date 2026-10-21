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

    func model(mode: UserMode, deletion: Bool = false) -> (ProfileModel, MockRepository, AppSettings) {
        let repository = MockRepository(mode: mode, latency: .zero)
        let settings = settings(mode: mode)
        return (ProfileModel(repository: repository, settings: settings, dataDeletionEnabled: deletion), repository, settings)
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
        let model = ProfileModel(repository: repository, settings: settings(mode: .guardian), dataDeletionEnabled: false)
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

    @Test func deleteMyDataIsHiddenUntilTheContractExists() async {
        let (model, _, _) = model(mode: .guardian)
        #expect(!model.canDeleteData)
        #expect(await model.deleteMyData() == false)
    }

    @Test func deleteMyDataStartsOverWithAFreshInstall() async throws {
        let (model, repository, settings) = model(mode: .guardian, deletion: true)
        await model.load()
        #expect(model.canDeleteData)
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
        let model = ProfileModel(repository: repository, settings: settings(mode: .guardian), dataDeletionEnabled: false)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.profile?.name == "Adhella")
        #expect(model.membersFailed)
    }

    @Test func editingTheNameClearsTheOldError() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        let model = ProfileModel(repository: repository, settings: settings(mode: .guardian), dataDeletionEnabled: false)
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
}
