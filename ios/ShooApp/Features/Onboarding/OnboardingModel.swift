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
/// mode off); connecting to a guardian or protecting others happens later from Home and Profile. Only an
/// invite link goes through Connect (PR-01) before ON-04.
enum OnboardingStep: Equatable {
    /// ON-01
    case splash
    /// ON-02
    case name
    /// Invite link only, while the online check question is unanswered: `DataConsentView` before Connect.
    /// A join registers the device and gives the extension its token, so the answer comes first (fase 27d, F-A1).
    case consent
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
/// also not after a relaunch, except from Connect after an invite join that failed: Back or "Not now" there
/// deletes the device again (`AppSettings.inviteRegistrationPending`, fase 27d K6).
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
    /// The ON-04 checkbox answered the question on this screen: it stays visible after the answer is saved.
    private(set) var keepsConsentCheckbox = false
    /// The last step change was a Back tap, so the screens slide the other way.
    private(set) var movedBack = false
    /// The avatar from `POST /devices` (the pick, or random if the server did not keep it). The token is not kept here (fase 13 stores it in the Keychain).
    private(set) var avatarId: String?
    private(set) var isWorking = false
    private(set) var registrationFailed = false

    @ObservationIgnored private let environment: AppEnvironment
    /// Kept across steps: Back from ON-04 finds the joined guardian.
    @ObservationIgnored private var connectModel: ConnectModel?
    /// The invite link's code, taken at the name's Next: `RootView` empties the router's copy when the app
    /// goes to the background (the consent screen's privacy policy, a look at WhatsApp).
    @ObservationIgnored private var inviteCode: String?
    /// Protected switches cleared when a failed invite registration is deleted. `nil`: the App Group's.
    @ObservationIgnored private let linked: LinkedAccountSettings?

    init(environment: AppEnvironment, linked: LinkedAccountSettings? = nil) {
        self.environment = environment
        self.linked = linked
        let settings = environment.settings
        // The app died during `POST /devices` for an invite join: nothing was saved, so nothing to undo.
        if settings.mode == nil, settings.inviteRegistrationPending { settings.inviteRegistrationPending = false }
        // Registered earlier but onboarding not finished (app closed in between): Home shows what is still off
        // (Figma note 141:6085). Protected from an invite link continues at Connect until it was passed once,
        // then at ON-04: Protected has no Home reminder, so skipping it would leave Shoo off (fase 27d, F-A14).
        switch settings.mode {
        case nil: step = .splash
        case .protected where !settings.onboardingConnectPassed: step = .connect
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

    /// Opened from an invite link (PR-03, WhatsApp/QR): only a Protected joins with a code, so Connect opens
    /// with the code filled in.
    var opensWithInvite: Bool { inviteCode != nil || environment.router.pendingJoinCode != nil }

    /// ON-02 Next: ON-04, or for an invite link the consent question (when unanswered) and Connect.
    func submitName() {
        guard step == .name, canSubmitName, !isWorking else { return }
        movedBack = false
        registrationFailed = false
        if let pending = environment.router.takePendingJoinCode() {
            inviteCode = pending
            connectModel?.prefill(pending)
        }
        if inviteCode != nil {
            selectedMode = .protected
            step = environment.settings.dataConsent == nil ? .consent : .connect
        } else {
            selectedMode = .guardian
            step = .turnOnExtension
        }
    }

    /// The invite path's consent step: saved at once (it decides what the extension may send), then Connect.
    func answerConsent(_ consent: DataConsent) {
        guard step == .consent else { return }
        environment.setDataConsent(consent)
        movedBack = false
        step = .connect
    }

    /// Back follows Figma: every step has one, except where it would undo a saved registration. Connect with
    /// a registration to undo goes through `backFromConnect`.
    func goBack() {
        guard !isWorking else { return }
        switch (step, mode) {
        case (.name, nil): step = .splash
        // The invite code stays: Next comes back here.
        case (.consent, nil): step = .name
        case (.connect, nil), (.turnOnExtension, nil): step = .name
        // Only with this launch's Connect: after a relaunch a new one would just answer `already_connected`.
        case (.turnOnExtension, .protected) where connectModel != nil: step = .connect
        case (.safariDefault, _): step = .turnOnExtension
        default: return
        }
        movedBack = true
        registrationFailed = false
    }

    /// ON-04 shows Back until a Pribadi device is registered (its name can no longer change here), and for a
    /// Protected back to this launch's Connect.
    var canGoBackFromExtension: Bool { mode == nil || (mode == .protected && connectModel != nil) }

    /// The device registered for an invite join that has not gone through: Back or "Not now" deletes it.
    private var undoesInviteRegistration: Bool {
        mode == .protected && environment.settings.inviteRegistrationPending && !environment.settings.onboardingConnectPassed
    }

    /// Whether Connect shows Back to the name: nothing registered yet, or a registration that can be undone.
    var canGoBackFromConnect: Bool { mode == nil || undoesInviteRegistration }

    /// A join is on its way, or a registration is being undone: Connect, Back and "Not now" wait.
    var isConnectBusy: Bool { isWorking || connectModel?.isBusy == true }

    /// Back on Connect: to the name. A failed invite join's registration is deleted first; if that fails the
    /// screen says why and stays.
    func backFromConnect() async {
        guard step == .connect, !isConnectBusy else { return }
        guard mode != nil else { return goBack() }
        guard undoesInviteRegistration, await cancelInviteRegistration() else { return }
        movedBack = true
        step = .name
    }

    /// Saves the device (`POST /devices`), once.
    func ensureRegistered() async throws {
        guard mode == nil else { return }
        guard case .success(let trimmed) = NameRule.validate(name) else {
            throw RepositoryError.network
        }
        avatarId = try await environment.register(name: trimmed, mode: selectedMode, avatarId: selectedAvatarId).avatarId
        if selectedMode == .guardian { environment.settings.familyModeOn = false }
    }

    /// ON-04 asks the question only when nothing answered it before (the invite path's consent step, an
    /// earlier install's answer). Once ticked here it stays on screen.
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

    /// PR-01 inside onboarding: a join registers the device first.
    func connect() -> ConnectModel {
        if let connectModel { return connectModel }
        let code = inviteCode ?? environment.router.takePendingJoinCode()
        let connect = ConnectModel(repository: environment.repository, code: code) { [weak self] code in
            guard let self else { throw CancellationError() }
            try await self.registerForInvite()
            let guardian: GuardianInfo
            do {
                guardian = try await self.environment.repository.joinFamily(code: code)
            } catch let error as RepositoryError
                where error.apiCode == .alreadyConnected && self.environment.settings.inviteRegistrationPending {
                guardian = try await self.guardianOfLostJoin(else: error)
            }
            self.markJoined()
            return guardian
        }
        connectModel = connect
        return connect
    }

    /// Registers for an invite join. The flag goes on first, so a crash after `POST /devices` still finds a
    /// registration to undo; it goes off again when the registration fails (nothing to undo then).
    private func registerForInvite() async throws {
        guard mode == nil else { return }
        environment.settings.inviteRegistrationPending = true
        do {
            try await ensureRegistered()
        } catch {
            // Nothing saved here, so nothing to undo. A cancelled request may still have reached the server:
            // the flag then stays and the next launch drops it (no mode), as for a crash.
            if mode == nil, !error.isCancellation { environment.settings.inviteRegistrationPending = false }
            throw error
        }
    }

    /// `already_connected` for our own fresh registration: an earlier join went through on the server, but its
    /// answer got lost (backend `family.ts`). `GET /devices/me` names the guardian. Without an answer, the
    /// offline message (the flag stays, so the next try asks again).
    private func guardianOfLostJoin(else error: RepositoryError) async throws -> GuardianInfo {
        let profile: DeviceProfile
        do {
            profile = try await environment.repository.me()
        } catch let meError {
            if meError.isCancellation { throw meError }
            throw RepositoryError.network
        }
        guard let guardian = profile.guardian else { throw error }
        return guardian
    }

    private func markJoined() {
        environment.settings.onboardingConnectPassed = true
        environment.settings.inviteRegistrationPending = false
        // Used up: nothing keeps an invite code longer than it needs to.
        inviteCode = nil
    }

    /// Undoes a failed invite join's registration (P13: a Protected mode is for good on the server, so the
    /// honest way back is deleting the device). `true` once it is gone here and there. Asks the server first:
    /// a guardian there means a join did go through after all, which then shows as joined (never deleted).
    private func cancelInviteRegistration() async -> Bool {
        let connect = connect()
        isWorking = true
        connect.hold(true)
        defer {
            isWorking = false
            connect.hold(false)
        }
        let profile: DeviceProfile
        do {
            profile = try await environment.repository.me()
        } catch {
            guard !error.isCancellation else { return false }
            Log.app.error("Profile check before undoing the registration failed", error)
            connect.report(error)
            return false
        }
        if let guardian = profile.guardian {
            markJoined()
            connect.showJoined(guardian)
            return false
        }
        do {
            try await environment.repository.deleteMe()
        } catch RepositoryError.api(.notFound, _), RepositoryError.api(.unauthorized, _) {
            // Already gone (an earlier answer got lost, or the unused device expired): same end state.
        } catch {
            guard !error.isCancellation else { return false }
            Log.app.error("Undoing the registration failed", error)
            connect.report(error)
            return false
        }
        // `ApiRepository.deleteMe` has already cleared the Keychain token and App Group session keys.
        AppEnvironment.forgetDeletedDevice(linked: linked ?? LinkedAccountSettings())
        environment.settings.forgetInviteRegistration()
        connectModel = nil
        selectedMode = .guardian
        avatarId = nil
        // Forgotten with the device: the name's Next now continues as Pribadi.
        inviteCode = nil
        return true
    }

    /// "Not now" on Connect: ON-04 as Pribadi instead. Nothing is saved yet, or a failed invite join's
    /// registration is deleted first (on failure the screen says why and stays).
    func skipConnect() async {
        guard step == .connect, !isConnectBusy else { return }
        if undoesInviteRegistration {
            guard await cancelInviteRegistration() else { return }
        }
        if mode == nil {
            selectedMode = .guardian
            inviteCode = nil
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
        selectedMode = [.consent, .connect].contains(step) ? .protected : .guardian
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
