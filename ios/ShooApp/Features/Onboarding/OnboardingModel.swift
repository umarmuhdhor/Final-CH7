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
    /// The online check question (`DataConsent`), before anything can leave the phone.
    case dataConsent
    /// ON-02
    case name
    /// ON-03
    case mode
    /// Protected only: PR-01.
    case connect
    /// Guardian only: "Protect yourself and your loved ones", invite now (GD-04 sheet) or skip.
    case invite
    /// ON-04
    case turnOnExtension
    /// ON-04 passed (Figma "Jadikan Safari Default"): Shoo only runs in Safari.
    case safariDefault
    /// "Yeay, you're better protected!" Its Next asks for notifications (ON-05 has no screen of its own).
    case extensionOn
    case done
}

/// State of the whole onboarding flow (ON-01 … ON-05). The device registers on the first action on
/// Invite or Connect, so until then Back reaches the mode choice (Figma). After that there is no way
/// back to it, also not after a relaunch.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var step: OnboardingStep
    var name = ""
    /// ON-02 avatar picker. Sent as `avatarId` in `POST /devices` (#120); the response is the source of truth.
    var selectedAvatarId = OnboardingAvatar.ids[0]
    var selectedMode: UserMode?
    /// The last step change was a Back tap, so the screens slide the other way.
    private(set) var movedBack = false
    /// The brand splash shows once per launch, not again after Back from ON-02.
    var brandSplashShown = false
    /// The avatar from `POST /devices` (the pick, or random if the server did not keep it). The token is not kept here (fase 13 stores it in the Keychain).
    private(set) var avatarId: String?
    private(set) var isWorking = false
    private(set) var registrationFailed = false

    @ObservationIgnored private let environment: AppEnvironment
    /// Kept across steps: Back from ON-04 finds the joined guardian, Back to ON-03 keeps an invite code.
    @ObservationIgnored private var connectModel: ConnectModel?

    init(environment: AppEnvironment) {
        self.environment = environment
        // Registered earlier but onboarding not finished (app closed in between): never back to ON-03.
        // Protected continues at Connect until it was passed once. Everyone else goes to Home, which shows
        // what is still off; `OnboardingFlow` ends onboarding for `.done`.
        switch environment.settings.mode {
        case nil: step = .splash
        case .protected where !environment.settings.onboardingConnectPassed: step = .connect
        default: step = .done
        }
    }

    var mode: UserMode? { environment.settings.mode }

    var nameProblem: NameRule.Problem? {
        if case .failure(let problem) = NameRule.validate(name) { return problem }
        return nil
    }

    var canSubmitName: Bool { nameProblem == nil }

    func skipSplash() {
        guard step == .splash else { return }
        movedBack = false
        step = environment.settings.dataConsent == nil ? .dataConsent : .name
    }

    func answerDataConsent(_ consent: DataConsent) {
        guard step == .dataConsent else { return }
        environment.setDataConsent(consent)
        movedBack = false
        step = .name
    }

    /// Opened from an invite link (PR-03, WhatsApp/QR): only a Protected joins with a code, so ON-03 is
    /// skipped and Connect opens with the code filled in.
    var opensWithInvite: Bool { environment.router.pendingJoinCode != nil }

    /// ON-02 Next. An invite link opens Connect right away, with Protected picked.
    func submitName() {
        guard step == .name, canSubmitName, !isWorking else { return }
        movedBack = false
        guard opensWithInvite else {
            step = .mode
            return
        }
        selectedMode = .protected
        step = .connect
    }

    /// ON-03 Next. Nothing is saved yet (see `ensureRegistered`).
    func continueFromMode() {
        guard step == .mode, let selectedMode else { return }
        movedBack = false
        registrationFailed = false
        step = selectedMode == .protected ? .connect : .invite
    }

    /// Back follows Figma: every step has one, except where it would change a saved mode.
    func goBack() {
        guard !isWorking else { return }
        switch (step, mode) {
        case (.dataConsent, nil), (.name, nil): step = .splash
        case (.mode, nil): step = .name
        case (.invite, nil), (.connect, nil): step = .mode
        case (.turnOnExtension, .guardian): step = .invite
        case (.turnOnExtension, .protected): step = .connect
        case (.safariDefault, _): step = .turnOnExtension
        default: return
        }
        movedBack = true
        registrationFailed = false
    }

    /// Whether Back on Invite or Connect still reaches ON-03.
    var canGoBackToMode: Bool { mode == nil }

    /// Saves the mode for good (`POST /devices`), once. Runs on the first action on Invite or Connect.
    func ensureRegistered() async throws {
        guard mode == nil else { return }
        guard let selectedMode, case .success(let trimmed) = NameRule.validate(name) else {
            throw RepositoryError.network
        }
        avatarId = try await environment.register(name: trimmed, mode: selectedMode, avatarId: selectedAvatarId).avatarId
    }

    /// Runs `ensureRegistered` for a tap on Invite; a failure shows on the screen and the tap can be repeated.
    private func registerFromInvite() async -> Bool {
        guard step == .invite, !isWorking else { return false }
        isWorking = true
        registrationFailed = false
        defer { isWorking = false }
        do {
            try await ensureRegistered()
            return true
        } catch {
            Log.app.error("Registration failed", error)
            registrationFailed = true
            return false
        }
    }

    /// "Invite": true once the sheet may open (it needs the device's token for the code).
    func prepareInvite() async -> Bool {
        await registerFromInvite()
    }

    /// "Skip".
    func skipInvite() async {
        guard await registerFromInvite() else { return }
        continueFromInvite()
    }

    /// "Skip", or the invite sheet's Done. Inviting later stays possible from Shield and Profile.
    func continueFromInvite() {
        guard step == .invite else { return }
        movedBack = false
        step = .turnOnExtension
    }

    /// PR-01 inside onboarding: a join registers the device first.
    func connect() -> ConnectModel {
        if let connectModel { return connectModel }
        let connect = ConnectModel(repository: environment.repository, code: environment.router.takePendingJoinCode()) { [weak self] code in
            guard let self else { throw CancellationError() }
            try await self.ensureRegistered()
            let guardian = try await self.environment.repository.joinFamily(code: code)
            self.environment.settings.onboardingConnectPassed = true
            return guardian
        }
        connectModel = connect
        return connect
    }

    /// "Not now": still registers, then ON-04. A failure shows on Connect.
    func skipConnect() async {
        guard step == .connect, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await ensureRegistered()
            continueFromConnect()
        } catch {
            Log.app.error("Registration failed", error)
            connect().report(error)
        }
    }

    func continueFromConnect() {
        guard step == .connect else { return }
        environment.settings.onboardingConnectPassed = true
        movedBack = false
        step = .turnOnExtension
    }

    /// Called on appear and every time the app comes back to the foreground (ON-04). Moves on only once
    /// Shoo is on and has checked in from Safari, so a new install never shows On before "Allow" (#135).
    /// After Back it stays, or Back would bounce straight forward again; the screen then offers Next.
    @discardableResult
    func refreshExtensionStatus() async -> ExtensionStatus? {
        guard step == .turnOnExtension else { return nil }
        let status = await environment.extensionStatus()
        // The step may have moved on (Back) while Safari answered.
        guard step == .turnOnExtension, status.nextStep == nil, !movedBack else { return status }
        step = .safariDefault
        return status
    }

    /// "Continue without checking" (Safari says the switch is on, but no page has checked in yet), or Next
    /// after Back from Safari Default.
    func skipExtensionCheck() {
        guard step == .turnOnExtension else { return }
        movedBack = false
        step = .safariDefault
    }

    /// Nothing can read the default browser, so this trusts the user.
    func continueFromSafariDefault() {
        guard step == .safariDefault else { return }
        movedBack = false
        step = .extensionOn
    }

    /// ON-05, from Next on the success screen: asks once; whatever the answer, onboarding ends (a Guardian
    /// who said no gets the Home reminder).
    func requestNotifications() async {
        guard step == .extensionOn, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        if await environment.notifications.status() == .notDetermined {
            _ = await environment.notifications.request()
        }
        await environment.registerForPushIfAllowed()
        finish()
    }

    #if DEBUG
    /// UI-gate screenshots only (`-debug.onboardingStep invite`): shows a step with sample data.
    func showForScreenshot(_ step: OnboardingStep) {
        // The name and mode steps start empty, as in Figma "Atur Nama · kosong" and "Choose Mode".
        name = step == .name ? "" : "Rina"
        selectedMode = step == .mode ? nil : mode ?? .protected
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
