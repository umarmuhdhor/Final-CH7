import Foundation
import Observation

/// Profile (PF-01) for both modes: name, language, the guardian link (Protected) or the family (Guardian).
@MainActor
@Observable
final class ProfileModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed
    }

    private(set) var state: State = .loading
    private(set) var profile: DeviceProfile?
    /// Guardian only: the people connected (x/3).
    private(set) var members: [FamilyMember] = []
    private(set) var isWorking = false
    /// Last failure in plain words; cleared by the next action.
    private(set) var errorMessage: String.LocalizationValue?
    var nameDraft = ""

    @ObservationIgnored private let repository: any ShooRepository
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let dataDeletionEnabled: Bool

    init(repository: any ShooRepository, settings: AppSettings, dataDeletionEnabled: Bool = AppConfig.dataDeletionEnabled) {
        self.repository = repository
        self.settings = settings
        self.dataDeletionEnabled = dataDeletionEnabled
    }

    var showsFamilyCode: Bool { settings.mode == .guardian }
    var showsDisconnect: Bool { settings.mode == .protected }
    /// "Delete my data" waits for `DELETE /devices/me` in contracts (TODO C19).
    var canDeleteData: Bool { dataDeletionEnabled }

    /// Same rule as ON-02.
    var nameProblem: NameRule.Problem? {
        if case .failure(let problem) = NameRule.validate(nameDraft) { return problem }
        return nil
    }

    func load() async {
        do {
            let me = try await repository.me()
            members = settings.mode == .guardian ? try await repository.familyMembers() : []
            profile = me
            nameDraft = me.name
            state = .loaded
        } catch {
            guard !error.isCancellation else { return }
            Log.ui.error("Profile load failed", error)
            if state != .loaded { state = .failed }
        }
    }

    /// Saves the edited name; `false` when it breaks the rule or the server says no (old name stays).
    func saveName() async -> Bool {
        guard case .success(let trimmed) = NameRule.validate(nameDraft), !isWorking else { return false }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.updateMe(DeviceUpdate(name: trimmed))
            profile?.name = trimmed
            nameDraft = trimmed
            return true
        } catch {
            Log.ui.error("Name save failed", error)
            errorMessage = "Couldn't save. Check your connection and try again."
            return false
        }
    }

    /// The app switches at once; the server learns it for localized pushes (D-alief-05).
    func setLanguage(_ language: AppLanguage) async {
        guard language != settings.language else { return }
        settings.language = language
        errorMessage = nil
        do {
            try await repository.updateMe(DeviceUpdate(language: language.code))
            profile?.language = language.code
        } catch {
            // The app keeps the choice; pushes stay in the old language until the next save.
            Log.ui.error("Language save failed", error)
            errorMessage = "Couldn't save. Check your connection and try again."
        }
    }

    /// Protected leaves their guardian (`DELETE /family/guardian`) and goes back to Connect.
    func disconnect() async -> Bool {
        guard showsDisconnect, !isWorking else { return false }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.leaveGuardian()
            profile?.guardian = nil
            settings.onboardingConnectPassed = false
            settings.onboardingCompleted = false
            return true
        } catch {
            Log.ui.error("Disconnect failed", error)
            errorMessage = "Couldn't disconnect. Check your connection and try again."
            return false
        }
    }

    /// SECURITY §3 P3: gone on the server first, then a fresh install here (onboarding from the start).
    func deleteMyData() async -> Bool {
        guard canDeleteData, !isWorking else { return false }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.deleteMe()
            // TODO(sync:alief): also clear the Keychain token and App Group session keys — replace after fase 13
            settings.reset()
            return true
        } catch {
            Log.ui.error("Delete data failed", error)
            errorMessage = "Couldn't delete your data. Check your connection and try again."
            return false
        }
    }
}
