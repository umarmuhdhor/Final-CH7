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
    /// The family list could not be read; the rest of Profile still works.
    private(set) var membersFailed = false
    private(set) var isWorking = false
    /// Why the name was not saved; cleared as soon as the name is edited.
    private(set) var nameError: String.LocalizationValue?
    /// Disconnect / delete / language failures, shown as an alert.
    var actionError: String.LocalizationValue?
    var nameDraft = "" {
        didSet { if nameDraft != oldValue { nameError = nil } }
    }
    /// The running language sync; a newer choice cancels it.
    private(set) var languageTask: Task<Void, Never>?
    /// Called right before disconnect or delete hands the app back to onboarding
    /// (close the sheet, clear pushed screens).
    @ObservationIgnored var onSessionEnd: () -> Void = {}

    @ObservationIgnored private let repository: any ShooRepository
    @ObservationIgnored private let settings: AppSettings

    init(repository: any ShooRepository, settings: AppSettings) {
        self.repository = repository
        self.settings = settings
    }

    var showsFamilyCode: Bool { settings.mode == .guardian }
    var showsDisconnect: Bool { settings.mode == .protected }

    /// Same rule as ON-02.
    var nameProblem: NameRule.Problem? {
        if case .failure(let problem) = NameRule.validate(nameDraft) { return problem }
        return nil
    }

    func load() async {
        do {
            let me = try await repository.me()
            // Keep a name the user is still editing.
            if nameDraft.isEmpty || nameDraft == profile?.name { nameDraft = me.name }
            profile = me
            state = .loaded
            // The server missed the last language change (offline then): send it again.
            if me.language != settings.language.code { chooseLanguage(settings.language, force: true) }
        } catch {
            guard !error.isCancellation else { return }
            Log.ui.error("Profile load failed", error)
            if state != .loaded { state = .failed }
            return
        }
        guard settings.mode == .guardian else { return }
        do {
            members = try await repository.familyMembers()
            membersFailed = false
        } catch {
            guard !error.isCancellation else { return }
            Log.ui.error("Profile members failed", error)
            membersFailed = true
        }
    }

    /// "Try again": shows the spinner while it retries.
    func retry() async {
        state = .loading
        await load()
    }

    /// Saves the edited name; `false` when it breaks the rule or the server says no (old name stays).
    func saveName() async -> Bool {
        guard case .success(let trimmed) = NameRule.validate(nameDraft), !isWorking else { return false }
        nameError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.updateMe(DeviceUpdate(name: trimmed))
            profile?.name = trimmed
            nameDraft = trimmed
            return true
        } catch {
            Log.ui.error("Name save failed", error)
            nameError = "Couldn't save. Check your connection and try again."
            return false
        }
    }

    /// The app switches at once; the server learns it for localized pushes (D-alief-05).
    /// Only the newest choice is sent.
    func chooseLanguage(_ language: AppLanguage, force: Bool = false) {
        guard force || language != settings.language else { return }
        settings.language = language
        languageTask?.cancel()
        languageTask = Task { [repository] in
            do {
                try await repository.updateMe(DeviceUpdate(language: language.code))
                guard !Task.isCancelled else { return }
                profile?.language = language.code
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                // The app keeps the choice; `load()` sends it again next time.
                Log.ui.error("Language save failed", error)
                actionError = "Couldn't save. Check your connection and try again."
            }
        }
    }

    /// Protected leaves their guardian (`DELETE /family/guardian`) and goes back to Connect.
    func disconnect() async -> Bool {
        guard showsDisconnect, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.leaveGuardian()
        } catch RepositoryError.api(.notFound, _) {
            // Already disconnected (an earlier answer got lost): same end state.
        } catch {
            Log.ui.error("Disconnect failed", error)
            actionError = "Couldn't disconnect. Check your connection and try again."
            return false
        }
        onSessionEnd()
        settings.onboardingConnectPassed = false
        settings.onboardingCompleted = false
        return true
    }

    /// SECURITY §3 P3: gone on the server first, then a fresh install here (onboarding from the start).
    func deleteMyData() async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.deleteMe()
        } catch RepositoryError.api(.notFound, _), RepositoryError.api(.unauthorized, _) {
            // Already deleted (an earlier answer got lost): same end state.
        } catch {
            Log.ui.error("Delete data failed", error)
            actionError = "Couldn't delete your data. Check your connection and try again."
            return false
        }
        // TODO(sync:alief): also clear the Keychain token and App Group session keys — replace after fase 13
        onSessionEnd()
        settings.reset()
        return true
    }
}
