import Foundation
import Observation

/// ON-02: a name is 1–20 characters after trimming spaces. Characters are graphemes, so "👨‍👩‍👧" is one.
enum NameRule {
    enum Problem: Error, Equatable {
        case empty
        case tooLong
    }

    static let maxLength = 20

    /// The trimmed name, or why it is not allowed.
    static func validate(_ raw: String) -> Result<String, Problem> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Zero-width and control characters would show as a blank name in "Hi, …" and the family list.
        let invisible = trimmed.unicodeScalars.allSatisfy {
            $0.properties.isWhitespace || [.format, .control].contains($0.properties.generalCategory)
        }
        if invisible { return .failure(.empty) }
        if trimmed.count > maxLength { return .failure(.tooLong) }
        return .success(trimmed)
    }
}

/// Onboarding screens in order. Protected goes through Connect (PR-01, fase 14) before ON-04.
enum OnboardingStep: Equatable {
    /// ON-01
    case splash
    /// ON-02
    case name
    /// ON-03
    case mode
    /// "Hi, [name]" with the random avatar (D-alief-22).
    case greeting
    /// Protected only: PR-01.
    case connect
    /// Guardian only: "Protect yourself and your loved ones", invite now (GD-04 sheet) or skip.
    case invite
    /// ON-04
    case turnOnExtension
    /// ON-04 passed: "Yeay, you're better protected!"
    case extensionOn
    /// ON-05
    case notifications
    case done
}

/// State of the whole onboarding flow (ON-01 … ON-05). Steps only move forward; once the device is
/// registered there is no way back to the mode choice, also not after a relaunch.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var step: OnboardingStep
    var name = ""
    /// ON-02 avatar picker. Local only: `POST /devices` has no `avatarId` yet (issue #120), so the server
    /// still picks the avatar that is saved and shown after registration.
    var selectedAvatarId = OnboardingAvatar.ids[0]
    var selectedMode: UserMode?
    /// The last step change was a Back tap, so the screens slide the other way.
    private(set) var movedBack = false
    /// The brand splash shows once per launch, not again after Back from ON-02.
    var brandSplashShown = false
    /// The random avatar from `POST /devices`. The token is not kept here (fase 13 stores it in the Keychain).
    private(set) var avatarId: String?
    private(set) var registeredName = ""
    private(set) var isWorking = false
    private(set) var registrationFailed = false

    @ObservationIgnored private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        // Registered earlier but onboarding not finished (app closed in between): never back to ON-03.
        // Protected continues at Connect until it was passed once, everyone else at ON-04.
        switch environment.settings.mode {
        case nil: step = .splash
        case .protected where !environment.settings.onboardingConnectPassed: step = .connect
        default: step = .turnOnExtension
        }
    }

    var mode: UserMode? { environment.settings.mode }

    var nameProblem: NameRule.Problem? {
        if case .failure(let problem) = NameRule.validate(name) { return problem }
        return nil
    }

    var canSubmitName: Bool { nameProblem == nil }

    /// Notifications matter for the Guardian (pushes); Protected may skip ON-05.
    var canSkipNotifications: Bool { mode == .protected }

    func skipSplash() {
        guard step == .splash else { return }
        movedBack = false
        step = .name
    }

    func submitName() {
        guard step == .name, canSubmitName else { return }
        movedBack = false
        step = .mode
    }

    /// Back from ON-02 or ON-03 (only before registration: after that the mode is saved for good),
    /// and from ON-04 to the Guardian's invite screen.
    func goBack() {
        guard !isWorking else { return }
        switch (step, mode) {
        case (.name, nil): step = .splash
        case (.mode, nil): step = .name
        case (.turnOnExtension, .guardian): step = .invite
        default: return
        }
        movedBack = true
        registrationFailed = false
    }

    func register() async {
        guard step == .mode, !isWorking, let selectedMode, case .success(let trimmed) = NameRule.validate(name) else { return }
        isWorking = true
        registrationFailed = false
        defer { isWorking = false }
        do {
            avatarId = try await environment.register(name: trimmed, mode: selectedMode).avatarId
            registeredName = trimmed
            movedBack = false
            step = .greeting
        } catch {
            Log.app.error("Registration failed", error)
            registrationFailed = true
        }
    }

    func continueFromGreeting() {
        guard step == .greeting else { return }
        step = mode == .protected ? .connect : .invite
    }

    /// "Skip", or the invite sheet's Done. Inviting later stays possible from Shield and Profile.
    func continueFromInvite() {
        guard step == .invite else { return }
        movedBack = false
        step = .turnOnExtension
    }

    /// Only Guardians see the invite screen before ON-04, so only they get a way back to it.
    var canGoBackFromExtension: Bool { mode == .guardian }

    func continueFromConnect() {
        guard step == .connect else { return }
        environment.settings.onboardingConnectPassed = true
        step = .turnOnExtension
    }

    /// Called on appear and every time the app comes back to the foreground (ON-04).
    func refreshExtensionStatus() async {
        guard step == .turnOnExtension else { return }
        let isActive = await environment.extensionStatus().isActive
        // The step may have moved on (Back) while Safari answered.
        guard step == .turnOnExtension, isActive else { return }
        movedBack = false
        step = .extensionOn
    }

    func continueFromExtensionOn() {
        guard step == .extensionOn else { return }
        step = .notifications
    }

    /// ON-05: asks once; whatever the answer, onboarding ends (a Guardian who said no gets the Home reminder).
    func requestNotifications() async {
        guard step == .notifications, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        if await environment.notifications.status() == .notDetermined {
            _ = await environment.notifications.request()
        }
        await environment.registerForPushIfAllowed()
        finish()
    }

    func skipNotifications() {
        guard step == .notifications, canSkipNotifications else { return }
        finish()
    }

    #if DEBUG
    /// UI-gate screenshots only (`-debug.onboardingStep greeting`): shows a step with sample data.
    func showForScreenshot(_ step: OnboardingStep) {
        name = "Rina"
        registeredName = "Rina"
        selectedMode = mode ?? .guardian
        avatarId = "avatar_05"
        movedBack = false
        self.step = step
    }
    #endif

    private func finish() {
        environment.finishOnboarding()
        step = .done
    }
}
