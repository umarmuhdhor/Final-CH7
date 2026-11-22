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
    /// ON-04 "Saya setuju halaman dicek secara online." The first tap on Turn on saves it as the answer: ticked is
    /// a yes, unticked a no (Guideline 5.1.1(iv): Shoo works without the online check, so it can't be required).
    var consentChecked = false {
        // Once this screen saved the yes (`keepsConsentCheckbox`), the box is the saved answer: unticking it
        // takes the consent back (online checks off), ticking it again gives it again.
        didSet {
            guard keepsConsentCheckbox, consentChecked != oldValue else { return }
            environment.setDataConsent(consentChecked ? .granted : .declined)
        }
    }
    /// The ON-04 checkbox answered the question on this screen: it stays visible after the answer is saved.
    private(set) var keepsConsentCheckbox = false
    /// The last step change was a Back tap, so the screens slide the other way.
    private(set) var movedBack = false
    /// The avatar from `POST /devices` (the pick, or random if the server did not keep it). The token is not kept here (fase 13 stores it in the Keychain).
    private(set) var avatarId: String?
    private(set) var isWorking = false
    /// F6 (goldfish 21 Nov 2026): Shoo's "Turn on notifications?" dialog is up on the success screen, before
    /// the one-time iOS prompt. The dialog sets this back to false when it closes.
    var asksNotifications = false
    private(set) var registrationFailed = false
    /// The failure was the server's sign-up limit (429 `rate_limited`, 30 per network an hour): retrying
    /// at once can't help, so the screen says to wait instead of "check your connection" (EGM audit B9).
    private(set) var registrationLimited = false
    /// F6: this launch resumed a registered device at ON-04; `resumeAfterRelaunch` checks the extension once.
    private var resumesAtTurnOn = false

    @ObservationIgnored private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        let settings = environment.settings
        // Left by an older build that registered invite joins during onboarding: nothing uses it any more.
        if settings.inviteRegistrationPending { settings.inviteRegistrationPending = false }
        // F6 (goldfish 21 Nov 2026): registered earlier but onboarding not finished (iOS closed the app in
        // Settings). It carries on at the first step not done, so Safari Default and the notification question
        // are not lost: past Safari Default the success screen, otherwise ON-04, which moves on to Safari Default
        // once Shoo is found on (`resumeAfterRelaunch`). An older build's Protected registration too (F-A14).
        if settings.mode == nil {
            step = .splash
        } else if settings.onboardingCompleted {
            step = .done
        } else if settings.onboardingSafariDefaultPassed {
            step = .extensionOn
        } else {
            step = .turnOnExtension
            resumesAtTurnOn = true
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
        registrationLimited = false
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
        registrationLimited = false
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

    /// ON-04 Turn on / Next: saves the checkbox as the answer, then registers. A failure shows on the screen and
    /// the tap can be repeated. `true` once Settings may open.
    func activateExtension() async -> Bool {
        guard step == .turnOnExtension, !isWorking else { return false }
        // Only an unanswered question takes the checkbox's answer: an earlier answer is never overwritten. The
        // box stays on screen and keeps changing the saved answer (`consentChecked`).
        if environment.settings.dataConsent == nil {
            environment.setDataConsent(consentChecked ? .granted : .declined)
            keepsConsentCheckbox = true
        }
        guard mode == nil else { return true }
        isWorking = true
        registrationFailed = false
        registrationLimited = false
        defer { isWorking = false }
        do {
            try await ensureRegistered()
            return true
        } catch {
            Log.app.error("Registration failed", error)
            registrationFailed = true
            registrationLimited = (error as? RepositoryError)?.apiCode == .rateLimited
            return false
        }
    }

    /// Called on appear and every time the app comes back to the foreground (ON-04). Only reads the status:
    /// ON-04 never moves on by itself, so the consent box is seen once more after Settings and the user taps
    /// Next (`skipExtensionCheck`). A new install still never shows On before "Allow" (#135).
    @discardableResult
    func refreshExtensionStatus() async -> ExtensionStatus? {
        guard step == .turnOnExtension else { return nil }
        return await environment.extensionStatus()
    }

    /// ON-04 Next once Shoo is on: back from Settings, after Back from Safari Default, or when Shoo was already
    /// on before the first tap.
    func skipExtensionCheck() async {
        guard await activateExtension() else { return }
        movedBack = false
        step = .safariDefault
    }

    /// F6: once per launch that resumed at ON-04. Shoo already on and checked in (switch on, every site
    /// allowed), with the online check answered: straight on to Safari Default. Otherwise ON-04 stays, with
    /// the step that is still missing.
    func resumeAfterRelaunch() async {
        guard resumesAtTurnOn else { return }
        resumesAtTurnOn = false
        guard step == .turnOnExtension, environment.settings.dataConsent != nil else { return }
        let status = await environment.extensionStatus()
        // The user may have tapped on while the status was read.
        guard step == .turnOnExtension, !isWorking, status.nextStep == nil else { return }
        movedBack = false
        step = .safariDefault
    }

    /// Safari Default's "Check & continue" (`SafariCheck`): the extension status as now.
    func safariCheckStatus() async -> ExtensionStatus {
        await environment.extensionStatus()
    }

    /// The check passed, or the user chose "Continue anyway" after it failed. Saved, so a relaunch does not ask
    /// again (F6).
    func continueFromSafariDefault() {
        guard step == .safariDefault else { return }
        environment.settings.onboardingSafariDefaultPassed = true
        movedBack = false
        step = .extensionOn
    }

    /// Next on the success screen. iOS asks only once, so while the permission is undecided Shoo's dialog
    /// explains it first (F6); otherwise onboarding ends straight away.
    func continueFromSuccess() async {
        guard step == .extensionOn, !isWorking, !asksNotifications else { return }
        if await environment.notifications.status() == .notDetermined {
            asksNotifications = true
        } else {
            await requestNotifications()
        }
    }

    /// ON-05, "Turn on" in the dialog (or Next when the answer is already known): asks once; whatever the
    /// answer, onboarding ends (a Guardian who said no gets the Home reminder).
    func requestNotifications() async {
        guard step == .extensionOn, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        asksNotifications = false
        if await environment.notifications.status() == .notDetermined {
            _ = await environment.notifications.request()
        }
        await environment.registerForPushIfAllowed()
        finish()
    }

    /// "Not now" in the dialog: the iOS prompt stays unused, so Profile or the Home reminder can still ask later.
    func skipNotifications() {
        guard step == .extensionOn, !isWorking else { return }
        asksNotifications = false
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
        resumesAtTurnOn = false
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
