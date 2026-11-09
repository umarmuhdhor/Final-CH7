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

/// Onboarding screens in order (Figma "Flow" 1205:4696). Everyone starts as Pribadi (a Guardian with Family
/// mode off); connecting to a guardian or protecting others happens later from Home and Profile. Only an
/// invite link goes through Connect (PR-01) before ON-04.
enum OnboardingStep: Equatable {
    /// ON-01
    case splash
    /// ON-02
    case name
    /// Invite link only: PR-01.
    case connect
    /// ON-04, with the online check question (`DataConsent`) as a checkbox (Figma 1328:13421).
    case turnOnExtension
    /// ON-04 passed (Figma "Jadikan Safari Default"): Shoo only runs in Safari.
    case safariDefault
    /// "Yeay, you're better protected!" Its Next asks for notifications (ON-05 has no screen of its own).
    case extensionOn
    case done
}

/// State of the whole onboarding flow (ON-01 … ON-05). The device registers on the first tap on ON-04
/// (or a join on Connect), so until then Back reaches the name. After that there is no way back to it,
/// also not after a relaunch.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var step: OnboardingStep
    var name = ""
    /// ON-02 avatar picker. Sent as `avatarId` in `POST /devices` (#120); the response is the source of truth.
    var selectedAvatarId = OnboardingAvatar.ids[0]
    /// Pribadi unless an invite link was opened (then Protected joins on Connect).
    private(set) var selectedMode: UserMode = .guardian
    /// ON-04 "Saya setuju halaman dicek secara online." Its Turn on stays off until it is ticked (Figma).
    var consentChecked = false
    /// The last step change was a Back tap, so the screens slide the other way.
    private(set) var movedBack = false
    /// The brand splash shows once per launch, not again after Back from ON-02.
    var brandSplashShown = false
    /// The avatar from `POST /devices` (the pick, or random if the server did not keep it). The token is not kept here (fase 13 stores it in the Keychain).
    private(set) var avatarId: String?
    private(set) var isWorking = false
    private(set) var registrationFailed = false

    @ObservationIgnored private let environment: AppEnvironment
    /// Kept across steps: Back from ON-04 finds the joined guardian.
    @ObservationIgnored private var connectModel: ConnectModel?

    init(environment: AppEnvironment) {
        self.environment = environment
        // Registered earlier but onboarding not finished (app closed in between): Home shows what is still off
        // (Figma note 141:6085). Protected from an invite link continues at Connect until it was passed once.
        switch environment.settings.mode {
        case nil: step = .splash
        case .protected where !environment.settings.onboardingConnectPassed: step = .connect
        default: step = .done
        }
        consentChecked = environment.settings.dataConsent == .granted
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
        step = .name
    }

    /// Opened from an invite link (PR-03, WhatsApp/QR): only a Protected joins with a code, so Connect opens
    /// with the code filled in.
    var opensWithInvite: Bool { environment.router.pendingJoinCode != nil }

    /// ON-02 Next: ON-04, or Connect for an invite link.
    func submitName() {
        guard step == .name, canSubmitName, !isWorking else { return }
        movedBack = false
        registrationFailed = false
        if opensWithInvite {
            selectedMode = .protected
            step = .connect
        } else {
            selectedMode = .guardian
            step = .turnOnExtension
        }
    }

    /// Back follows Figma: every step has one, except where it would undo a saved registration.
    func goBack() {
        guard !isWorking else { return }
        switch (step, mode) {
        case (.name, nil): step = .splash
        case (.connect, nil), (.turnOnExtension, nil): step = .name
        case (.turnOnExtension, .protected): step = .connect
        case (.safariDefault, _): step = .turnOnExtension
        default: return
        }
        movedBack = true
        registrationFailed = false
    }

    /// ON-04 shows Back until a Pribadi device is registered (its name can no longer change here).
    var canGoBackFromExtension: Bool { mode != .guardian }

    /// Whether Back on Connect still reaches the name.
    var canGoBackToName: Bool { mode == nil }

    /// Saves the device (`POST /devices`), once.
    func ensureRegistered() async throws {
        guard mode == nil else { return }
        guard case .success(let trimmed) = NameRule.validate(name) else {
            throw RepositoryError.network
        }
        avatarId = try await environment.register(name: trimmed, mode: selectedMode, avatarId: selectedAvatarId).avatarId
        if selectedMode == .guardian { environment.settings.familyModeOn = false }
    }

    /// ON-04 Turn on / Next: saves the ticked consent, then registers. A failure shows on the screen and the
    /// tap can be repeated. `true` once Settings may open.
    func activateExtension() async -> Bool {
        guard step == .turnOnExtension, consentChecked, !isWorking else { return false }
        if environment.settings.dataConsent != .granted { environment.setDataConsent(.granted) }
        guard mode == nil else { return true }
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

    /// "Not now" on Connect: ON-04 as Pribadi instead (nothing is saved yet).
    func skipConnect() async {
        guard step == .connect, !isWorking else { return }
        if mode == nil {
            selectedMode = .guardian
            movedBack = false
            step = .turnOnExtension
        } else {
            continueFromConnect()
        }
    }

    func continueFromConnect() {
        guard step == .connect else { return }
        environment.settings.onboardingConnectPassed = true
        movedBack = false
        step = .turnOnExtension
    }

    /// Called on appear and every time the app comes back to the foreground (ON-04). Moves on only once
    /// the device is registered and Shoo is on and has checked in from Safari, so a new install never shows
    /// On before "Allow" (#135). After Back it stays, or Back would bounce straight forward again; the screen
    /// then offers Next.
    @discardableResult
    func refreshExtensionStatus() async -> ExtensionStatus? {
        guard step == .turnOnExtension else { return nil }
        let status = await environment.extensionStatus()
        // The step may have moved on (Back) while Safari answered.
        guard step == .turnOnExtension, status.nextStep == nil, !movedBack, mode != nil, consentChecked else { return status }
        step = .safariDefault
        return status
    }

    /// "Continue without checking" (Safari says the switch is on, but no page has checked in yet), or Next
    /// after Back from Safari Default, or when Shoo was already on before the first tap.
    func skipExtensionCheck() async {
        guard await activateExtension() else { return }
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
    /// UI-gate screenshots only (`-debug.onboardingStep turnOnExtension`): shows a step with sample data.
    func showForScreenshot(_ step: OnboardingStep) {
        // The name step starts empty, as in Figma "Atur Nama · kosong".
        name = step == .name ? "" : "Rina"
        selectedMode = step == .connect ? .protected : .guardian
        avatarId = "avatar_05"
        movedBack = false
        self.step = step
    }
    #endif

    /// The sample family (debug only since the Figma splash has no demo link, `-debug.demo YES`).
    func startDemo() {
        environment.startDemo()
        step = .done
    }

    private func finish() {
        environment.finishOnboarding()
        step = .done
    }
}
