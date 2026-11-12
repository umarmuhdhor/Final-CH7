import Foundation
import Observation

/// ON-02: a name is 1–20 characters after trimming spaces. Characters are counted as the server and the
/// database count them (code points, `char_length`), so "👨‍👩‍👧" is 5 (BH-26): a name the app accepts must never
/// come back as a 422 that no retry can fix.
enum NameRule {
    enum Problem: Error, Equatable {
        case empty
        case tooLong
    }

    static let maxLength = 20

    /// Characters as the server counts them (backend `codePoints`).
    static func length(_ name: String) -> Int { name.unicodeScalars.count }

    /// The trimmed name, or why it is not allowed.
    static func validate(_ raw: String) -> Result<String, Problem> {
        // Control and bidi characters: the server refuses them (backend `displayName`), and a bidi override
        // could disguise a name in push text. Dropped here, so the name is sent without them.
        let cleaned = String(String.UnicodeScalarView(raw.unicodeScalars.filter { !isUnsafe($0) }))
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        // Zero-width characters would show as a blank name in "Hi, …" and the family list.
        let invisible = trimmed.unicodeScalars.allSatisfy {
            $0.properties.isWhitespace || [.format, .control].contains($0.properties.generalCategory)
        }
        if invisible { return .failure(.empty) }
        if length(trimmed) > maxLength { return .failure(.tooLong) }
        return .success(trimmed)
    }

    /// Backend `UNSAFE_TEXT`: `\p{Cc}`, U+200E, U+200F, U+202A–U+202E, U+2066–U+2069.
    private static func isUnsafe(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: true
        default: scalar.properties.generalCategory == .control
        }
    }
}

/// Onboarding screens in order (Figma "Flow" 1205:4696). Everyone starts as Pribadi (a Guardian with Family
/// mode off), also from an invite link (PR-03): the link's code waits in the router, and the join sheet opens
/// with it once onboarding is done (`AppEnvironment.finishOnboarding`).
enum OnboardingStep: Equatable {
    /// ON-01
    case splash
    /// ON-02
    case name
    /// ON-04, with the online check question (`DataConsent`) as a checkbox (Figma 1328:13421).
    case turnOnExtension
    /// ON-04 passed (Figma "Jadikan Safari Default"): Shoo only runs in Safari.
    case safariDefault
    /// "Yeay, you're better protected!" Its Next asks for notifications (ON-05 has no screen of its own).
    case extensionOn
    case done
}

/// State of the whole onboarding flow (ON-01 … ON-05). The device registers on the first tap on ON-04, so
/// until then Back reaches the name. After that there is no way back to it, also not after a relaunch.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var step: OnboardingStep
    var name = ""
    /// ON-02 avatar picker. Sent as `avatarId` in `POST /devices` (#120); the response is the source of truth.
    var selectedAvatarId = OnboardingAvatar.ids[0]
    /// ON-04 "Saya setuju halaman dicek secara online." Its Turn on stays off until it is ticked (Figma).
    var consentChecked = false
    /// The ON-04 checkbox answered the question on this screen: it stays visible after the answer is saved.
    private(set) var keepsConsentCheckbox = false
    /// The last step change was a Back tap, so the screens slide the other way.
    private(set) var movedBack = false
    /// The avatar from `POST /devices` (the pick, or random if the server did not keep it). The token is not kept here (fase 13 stores it in the Keychain).
    private(set) var avatarId: String?
    private(set) var isWorking = false
    private(set) var registrationFailed = false

    @ObservationIgnored private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        let settings = environment.settings
        // Left by an older build that registered invite joins during onboarding: nothing uses it any more.
        if settings.inviteRegistrationPending { settings.inviteRegistrationPending = false }
        // Registered earlier but onboarding not finished (app closed in between): Home shows what is still off
        // (Figma note 141:6085). An older build's Protected registration carries on at ON-04: Protected has no
        // Home reminder, so skipping it would leave Shoo off (fase 27d, F-A14).
        switch settings.mode {
        case nil: step = .splash
        case .protected where !settings.onboardingCompleted: step = .turnOnExtension
        default: step = .done
        }
        consentChecked = settings.dataConsent == .granted
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

    /// ON-02 Next: ON-04. An invite link's code stays in the router for after onboarding (PR-03).
    func submitName() {
        guard step == .name, canSubmitName, !isWorking else { return }
        movedBack = false
        registrationFailed = false
        step = .turnOnExtension
    }

    /// Back follows Figma: every step has one, except where it would undo a saved registration.
    func goBack() {
        guard !isWorking else { return }
        switch (step, mode) {
        case (.name, nil): step = .splash
        case (.turnOnExtension, nil): step = .name
        case (.safariDefault, _): step = .turnOnExtension
        default: return
        }
        movedBack = true
        registrationFailed = false
    }

    /// ON-04 shows Back until the device is registered (its name can no longer change here).
    var canGoBackFromExtension: Bool { mode == nil }

    /// Saves the device (`POST /devices`) as Pribadi, once.
    func ensureRegistered() async throws {
        guard mode == nil else { return }
        guard case .success(let trimmed) = NameRule.validate(name) else {
            throw RepositoryError.network
        }
        avatarId = try await environment.register(name: trimmed, mode: .guardian, avatarId: selectedAvatarId).avatarId
        environment.settings.familyModeOn = false
    }

    /// ON-04 asks the question only when nothing answered it before (an earlier install's answer). Once ticked
    /// here it stays on screen.
    var showsConsentCheckbox: Bool { environment.settings.dataConsent == nil || keepsConsentCheckbox }

    /// ON-04's buttons: on once the question is answered, here or before.
    var canTurnOn: Bool { !showsConsentCheckbox || consentChecked }

    /// ON-04 Turn on / Next: saves the ticked consent, then registers. A failure shows on the screen and the
    /// tap can be repeated. `true` once Settings may open.
    func activateExtension() async -> Bool {
        guard step == .turnOnExtension, canTurnOn, !isWorking else { return false }
        // Only an unanswered question gets the checkbox's yes: a "no" given earlier is never overwritten.
        if environment.settings.dataConsent == nil {
            environment.setDataConsent(.granted)
            keepsConsentCheckbox = true
        }
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

    /// Called on appear and every time the app comes back to the foreground (ON-04). Moves on only once
    /// the device is registered and Shoo is on and has checked in from Safari, so a new install never shows
    /// On before "Allow" (#135). After Back it stays, or Back would bounce straight forward again; the screen
    /// then offers Next.
    @discardableResult
    func refreshExtensionStatus() async -> ExtensionStatus? {
        guard step == .turnOnExtension else { return nil }
        let status = await environment.extensionStatus()
        // The step may have moved on (Back) while Safari answered.
        guard step == .turnOnExtension, status.nextStep == nil, !movedBack, mode != nil, canTurnOn else { return status }
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
        // Figma's ON-04 has the checkbox; the mock has answered the question already.
        keepsConsentCheckbox = step == .turnOnExtension
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
