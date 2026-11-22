import Foundation
import Testing
@testable import Shoo

/// Answers the notification prompt the way a test needs, without a system alert.
final class FakeNotificationPermission: NotificationPermission, @unchecked Sendable {
    var current: NotificationAuthorization
    var answer: NotificationAuthorization
    private(set) var requestCount = 0

    init(current: NotificationAuthorization = .notDetermined, answer: NotificationAuthorization = .authorized) {
        self.current = current
        self.answer = answer
    }

    func status() async -> NotificationAuthorization { current }

    func request() async -> NotificationAuthorization {
        requestCount += 1
        current = answer
        return answer
    }
}

struct NameRuleTests {
    @Test(arguments: ["", "   ", "\n"])
    func emptyNameIsRejected(name: String) {
        #expect(NameRule.validate(name) == .failure(.empty))
    }

    @Test func twentyOneCharactersAreRejected() {
        #expect(NameRule.validate(String(repeating: "a", count: 21)) == .failure(.tooLong))
    }

    @Test(arguments: ["A", String(repeating: "b", count: 20)])
    func oneToTwentyCharactersAreAccepted(name: String) {
        #expect(NameRule.validate(name) == .success(name))
    }

    @Test func spacesAreTrimmedBeforeCounting() {
        #expect(NameRule.validate("  Rina  ") == .success("Rina"))
        #expect(NameRule.validate(" " + String(repeating: "c", count: 20) + " ") == .success(String(repeating: "c", count: 20)))
    }

    @Test(arguments: ["\u{200B}", "\u{2060}\u{FEFF}", " \u{200B} ", "\u{0007}"])
    func invisibleCharactersAreNotAName(name: String) {
        #expect(NameRule.validate(name) == .failure(.empty))
    }

    /// BH-26: the server (and the database, `char_length`) counts code points, so the app does too: a name
    /// the app accepts must never come back as a 422 that no retry can fix. "👨‍👩‍👧" is 5 code points.
    @Test func charactersAreCountedAsTheServerCountsThem() {
        let family = "👨‍👩‍👧"
        #expect(NameRule.validate(String(repeating: family, count: 4)) == .success(String(repeating: family, count: 4)))
        #expect(NameRule.validate(String(repeating: family, count: 3) + "abcdef") == .failure(.tooLong))
        #expect(NameRule.length(family) == 5)
    }

    /// BH-26: control and bidi characters (the server refuses them) are dropped from the name before it is sent.
    @Test func bidiAndControlCharactersAreDropped() {
        #expect(NameRule.validate("Ri\u{202E}na") == .success("Rina"))
        #expect(NameRule.validate("\u{2066}Bu Ani\u{2069}") == .success("Bu Ani"))
        #expect(NameRule.validate("Rina\u{0007}") == .success("Rina"))
        #expect(NameRule.validate("\u{200F}") == .failure(.empty))
    }
}

@MainActor
struct OnboardingModelTests {
    final class StatusBox: @unchecked Sendable {
        var status: ExtensionStatus = .off(lastSeen: nil)
    }

    let box = StatusBox()
    let settings: AppSettings
    let notifications: FakeNotificationPermission
    let env: AppEnvironment

    init() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        settings = AppSettings(defaults: defaults)
        settings.dataConsent = .granted
        notifications = FakeNotificationPermission()
        let box = box
        env = AppEnvironment(
            repository: MockRepository(mode: .guardian, latency: .zero),
            settings: settings,
            notifications: notifications,
            extensionStatus: { box.status }
        )
    }

    func model() -> OnboardingModel { OnboardingModel(environment: env) }

    /// Pribadi: name, then ON-04 with the box ticked and the first tap (registers).
    func registeredPersonal(consent: Bool = true) async -> OnboardingModel {
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        model.consentChecked = consent
        _ = await model.activateExtension()
        return model
    }

    /// ON-04: once the yes is saved the box stays; unticking it takes the consent back, ticking gives it again.
    @Test func untickingTheSavedConsentTakesItBack() async {
        settings.dataConsent = nil
        let model = await registeredPersonal()
        #expect(settings.dataConsent == .granted)
        model.consentChecked = false
        #expect(settings.dataConsent == .declined)
        model.consentChecked = true
        #expect(settings.dataConsent == .granted)
    }

    @Test func freshInstallStartsAtSplash() {
        #expect(model().step == .splash)
    }

    @Test func skipGoesStraightToName() {
        // Figma "Flow": no separate consent screen and no mode choice.
        settings.dataConsent = nil
        let model = model()
        model.skipSplash()
        #expect(model.step == .name)
        model.goBack()
        #expect(model.step == .splash)
    }

    @Test func aRegisteredDeviceWithoutAnAnswerIsAskedOnce() {
        #expect(!env.needsDataConsent)
        #expect(settings.chooseMode(.guardian))
        settings.onboardingCompleted = true
        settings.dataConsent = nil
        #expect(env.needsDataConsent)
        env.setDataConsent(.declined)
        #expect(!env.needsDataConsent)
    }

    @Test func invalidNameStaysOnNameStep() {
        let model = model()
        model.skipSplash()
        model.name = "   "
        #expect(!model.canSubmitName)
        model.submitName()
        #expect(model.step == .name)
        model.name = "Rina"
        #expect(model.canSubmitName)
        model.submitName()
        #expect(model.step == .turnOnExtension)
        #expect(settings.mode == nil)
    }

    /// Guideline 5.1.1(iv): Turn on works with the box unticked. The tap saves a no (on-device checks only),
    /// registers, and the box stays to change the answer later.
    @Test func turnOnWithoutTheBoxDeclinesTheOnlineCheck() async {
        settings.dataConsent = nil
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        #expect(!model.consentChecked)
        #expect(await model.activateExtension())
        #expect(settings.mode == .guardian)
        #expect(settings.dataConsent == .declined)
        #expect(model.showsConsentCheckbox)
        model.consentChecked = true
        #expect(settings.dataConsent == .granted)
    }

    /// An answer given before (the invite path's consent step) is never overwritten by the unticked box.
    @Test func turnOnKeepsAnEarlierAnswer() async {
        settings.dataConsent = .granted
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        model.consentChecked = false
        #expect(await model.activateExtension())
        #expect(settings.dataConsent == .granted)
    }

    @Test func firstTapSavesConsentAndRegistersPersonal() async {
        settings.dataConsent = nil
        let model = await registeredPersonal()
        #expect(settings.dataConsent == .granted)
        #expect(settings.mode == .guardian)
        #expect(!settings.familyModeOn)
        #expect(model.avatarId.map(AvatarCatalog.ids.contains) == true)
        #expect(!settings.onboardingCompleted)
        // Registered: no way back to the name any more.
        #expect(!model.canGoBackFromExtension)
        model.goBack()
        #expect(model.step == .turnOnExtension)
    }

    @Test func backReachesNameUntilTheDeviceIsRegistered() {
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        #expect(model.canGoBackFromExtension)
        model.goBack()
        #expect(model.step == .name)
    }

    @Test func registrationErrorStaysOnTurnOn() async throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        let env = AppEnvironment(
            repository: FailingRepository(), settings: settings, notifications: notifications, extensionStatus: { .off(lastSeen: nil) }
        )
        let model = OnboardingModel(environment: env)
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        model.consentChecked = true
        #expect(!(await model.activateExtension()))
        #expect(model.step == .turnOnExtension)
        #expect(model.registrationFailed)
        #expect(!model.registrationLimited)
        #expect(settings.mode == nil)
    }

    /// EGM audit B9: the sign-up limit (429) says to wait, not to check the connection.
    @Test func signUpLimitIsToldApart() async throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        let env = AppEnvironment(
            repository: FailingRepository(error: .api(.rateLimited, message: "HTTP 429")), settings: settings,
            notifications: notifications, extensionStatus: { .off(lastSeen: nil) }
        )
        let model = OnboardingModel(environment: env)
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        model.consentChecked = true
        #expect(!(await model.activateExtension()))
        #expect(model.registrationFailed)
        #expect(model.registrationLimited)
        model.goBack()
        #expect(!model.registrationLimited)
    }

    /// F6: iOS closed the app in Settings with Shoo still off: the relaunch carries on at ON-04, not Home.
    @Test func relaunchWithShooOffResumesAtTurnOn() async {
        _ = await registeredPersonal()
        let relaunched = model()
        #expect(relaunched.step == .turnOnExtension)
        await relaunched.resumeAfterRelaunch()
        #expect(relaunched.step == .turnOnExtension)
        #expect(!settings.onboardingCompleted)
    }

    /// F6: Shoo was switched on in Settings before iOS closed the app: on to Safari Default.
    @Test func relaunchWithShooOnResumesAtSafariDefault() async {
        _ = await registeredPersonal()
        box.status = .active(lastSeen: Date())
        let relaunched = model()
        await relaunched.resumeAfterRelaunch()
        #expect(relaunched.step == .safariDefault)
        // Only once per launch: Back from Safari Default stays on ON-04.
        relaunched.goBack()
        await relaunched.resumeAfterRelaunch()
        #expect(relaunched.step == .turnOnExtension)
    }

    /// F6: the switch is on but Safari still asks per site (or no page has said): ON-04 shows what is missing.
    @Test(arguments: [
        ExtensionStatus.off(lastSeen: Date(), reason: .someSitesOnly),
        .active(lastSeen: nil),
        .off(lastSeen: nil, reason: .switchedOff),
    ])
    func relaunchWithoutEverySiteStaysOnTurnOn(status: ExtensionStatus) async {
        _ = await registeredPersonal()
        box.status = status
        let relaunched = model()
        await relaunched.resumeAfterRelaunch()
        #expect(relaunched.step == .turnOnExtension)
    }

    /// F6: the online check was never answered (the box was the only place to answer it): ON-04 asks first.
    @Test func relaunchWithoutAnAnswerStaysOnTurnOn() async {
        _ = await registeredPersonal()
        settings.dataConsent = nil
        box.status = .active(lastSeen: Date())
        let relaunched = model()
        await relaunched.resumeAfterRelaunch()
        #expect(relaunched.step == .turnOnExtension)
        #expect(relaunched.showsConsentCheckbox)
    }

    /// F6: past Safari Default (it can't be read, so a flag says so): the success screen and its question.
    @Test func relaunchAfterSafariDefaultResumesAtSuccess() async {
        let first = await registeredPersonal()
        await reachSuccess(first)
        #expect(settings.onboardingSafariDefaultPassed)
        let relaunched = model()
        #expect(relaunched.step == .extensionOn)
        await relaunched.requestNotifications()
        #expect(settings.onboardingCompleted)
        #expect(model().step == .done)
    }

    @Test func resetForgetsSafariDefault() async {
        let model = await registeredPersonal()
        await reachSuccess(model)
        settings.reset()
        #expect(!settings.onboardingSafariDefaultPassed)
    }

    @Test func extensionOffStaysActiveContinues() async {
        let model = await registeredPersonal()
        await model.refreshExtensionStatus()
        #expect(model.step == .turnOnExtension)
        box.status = .active(lastSeen: Date())
        // Shoo is on, but ON-04 never moves on by itself: the consent box is seen again, then Next.
        await model.refreshExtensionStatus()
        #expect(model.step == .turnOnExtension)
        await model.skipExtensionCheck()
        #expect(model.step == .safariDefault)
        // "Check & continue" reads the same status the rest of the app uses.
        #expect(await model.safariCheckStatus() == box.status)
        model.continueFromSafariDefault()
        #expect(model.step == .extensionOn)
    }

    @Test func extensionAlreadyOnWaitsForTheFirstTap() async {
        // Switched on before (reinstall): the status alone never registers the device.
        box.status = .active(lastSeen: Date())
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        await model.refreshExtensionStatus()
        #expect(model.step == .turnOnExtension)
        model.consentChecked = true
        await model.skipExtensionCheck()
        #expect(model.step == .safariDefault)
        #expect(settings.mode == .guardian)
    }

    @Test func backFromSafariDefaultStaysOnTurnOn() async {
        let model = await registeredPersonal()
        box.status = .active(lastSeen: Date())
        await model.refreshExtensionStatus()
        await model.skipExtensionCheck()
        #expect(model.step == .safariDefault)
        model.goBack()
        #expect(model.step == .turnOnExtension)
        // The screen re-reads the status on appear: Shoo is on, but Back must not bounce forward.
        await model.refreshExtensionStatus()
        #expect(model.step == .turnOnExtension)
        await model.skipExtensionCheck()
        #expect(model.step == .safariDefault)
    }

    @Test func switchOnWithoutAPageWaitsForTheCheckOrASkip() async {
        let model = await registeredPersonal()
        // #135: Safari's switch is on, but no page has said whether Shoo may read every site.
        box.status = .active(lastSeen: nil)
        let status = await model.refreshExtensionStatus()
        #expect(status == .active(lastSeen: nil))
        #expect(model.step == .turnOnExtension)
        await model.skipExtensionCheck()
        #expect(model.step == .safariDefault)
    }

    @Test func narrowedAccessStaysOnTurnOn() async {
        let model = await registeredPersonal()
        box.status = .off(lastSeen: Date(), reason: .someSitesOnly)
        #expect(await model.refreshExtensionStatus()?.nextStep == .allowEveryWebsite)
        #expect(model.step == .turnOnExtension)
        box.status = .active(lastSeen: Date())
        await model.refreshExtensionStatus()
        #expect(model.step == .turnOnExtension)
        await model.skipExtensionCheck()
        #expect(model.step == .safariDefault)
    }

    /// Back from Settings with Shoo on, an unticked box can still be ticked before Next: the answer is a yes.
    @Test func backFromSettingsTheBoxCanStillBeTickedBeforeNext() async {
        settings.dataConsent = nil
        let model = await registeredPersonal(consent: false)
        #expect(settings.dataConsent == .declined)
        box.status = .active(lastSeen: Date())
        await model.refreshExtensionStatus()
        #expect(model.step == .turnOnExtension)
        #expect(model.showsConsentCheckbox)
        model.consentChecked = true
        #expect(settings.dataConsent == .granted)
        await model.skipExtensionCheck()
        #expect(model.step == .safariDefault)
        #expect(settings.dataConsent == .granted)
    }

    /// Through ON-04 and Safari Default to the success screen.
    func reachSuccess(_ model: OnboardingModel) async {
        model.consentChecked = true
        box.status = .active(lastSeen: Date())
        await model.refreshExtensionStatus()
        await model.skipExtensionCheck()
        model.continueFromSafariDefault()
    }

    @Test func personalFinishesEvenWhenPermissionIsDenied() async {
        notifications.answer = .denied
        let model = await registeredPersonal()
        await reachSuccess(model)
        await model.requestNotifications()
        #expect(notifications.requestCount == 1)
        #expect(model.step == .done)
        #expect(settings.onboardingCompleted)
        #expect(NotificationReminder.isShown(status: .denied, mode: .guardian))
    }

    @Test func notificationsAreOnlyAskedFromTheSuccessScreen() async {
        let model = await registeredPersonal()
        await model.requestNotifications()
        #expect(notifications.requestCount == 0)
        #expect(!settings.onboardingCompleted)
    }

    @Test func alreadyDecidedPermissionIsNotAskedAgain() async {
        notifications.current = .authorized
        let model = await registeredPersonal()
        await reachSuccess(model)
        await model.requestNotifications()
        #expect(notifications.requestCount == 0)
        #expect(settings.onboardingCompleted)
    }

    /// F6: Next shows Shoo's dialog before the one-time iOS prompt.
    @Test func nextShowsTheNotificationDialogFirst() async {
        let model = await registeredPersonal()
        await reachSuccess(model)
        await model.continueFromSuccess()
        #expect(model.asksNotifications)
        #expect(notifications.requestCount == 0)
        #expect(model.step == .extensionOn)
        #expect(!settings.onboardingCompleted)
        // A second tap while it is up changes nothing.
        await model.continueFromSuccess()
        #expect(notifications.requestCount == 0)
    }

    @Test func turnOnInTheDialogAsksThenFinishes() async {
        let model = await registeredPersonal()
        await reachSuccess(model)
        await model.continueFromSuccess()
        await model.requestNotifications()
        #expect(notifications.requestCount == 1)
        #expect(!model.asksNotifications)
        #expect(model.step == .done)
        #expect(settings.onboardingCompleted)
    }

    @Test func notNowFinishesWithoutAsking() async {
        let model = await registeredPersonal()
        await reachSuccess(model)
        await model.continueFromSuccess()
        model.skipNotifications()
        #expect(notifications.requestCount == 0)
        #expect(!model.asksNotifications)
        #expect(model.step == .done)
        #expect(settings.onboardingCompleted)
        #expect(await notifications.status() == .notDetermined)
    }

    @Test func decidedPermissionSkipsTheDialog() async {
        notifications.current = .denied
        let model = await registeredPersonal()
        await reachSuccess(model)
        await model.continueFromSuccess()
        #expect(!model.asksNotifications)
        #expect(notifications.requestCount == 0)
        #expect(model.step == .done)
    }

    @Test func notNowOnlyWorksOnTheSuccessScreen() async {
        let model = await registeredPersonal()
        model.skipNotifications()
        #expect(!settings.onboardingCompleted)
        await model.continueFromSuccess()
        #expect(!model.asksNotifications)
    }

    @Test func familyModeShowsTheGuardianIntroOnce() async {
        _ = await registeredPersonal()
        env.requestFamilyMode()
        #expect(env.router.isGuardianIntroPresented)
        #expect(!settings.familyModeOn)
        env.startGuardian()
        #expect(settings.familyModeOn)
        #expect(!env.router.isGuardianIntroPresented)
        settings.familyModeOn = false
        env.requestFamilyMode()
        #expect(settings.familyModeOn)
        #expect(!env.router.isGuardianIntroPresented)
    }

    @Test(arguments: [
        (NotificationAuthorization.denied, UserMode.guardian, true),
        (.notDetermined, .guardian, true),
        (.authorized, .guardian, false),
        (.denied, .protected, false),
    ])
    func reminderOnlyForGuardianWithoutPermission(status: NotificationAuthorization, mode: UserMode, shown: Bool) {
        #expect(NotificationReminder.isShown(status: status, mode: mode) == shown)
    }
}

struct SafariDefaultSetupTests {
    @Test(arguments: [
        (17, 5, SafariDefaultSetup.Step.openSafariLegacy),
        (18, 0, .openAppsSafari),
        (18, 1, .openAppsSafari),
        (18, 2, .openDefaultApps),
        // iOS 18.3+ opens the Default Apps page itself.
        (18, 3, .tapBrowserApp),
        (26, 0, .tapBrowserApp),
    ])
    func stepsFollowTheSettingsPage(major: Int, minor: Int, pick: SafariDefaultSetup.Step) {
        let version = OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
        #expect(SafariDefaultSetup.steps(for: version) == [.tapOpen, pick, .comeBack])
    }
}

/// "Cek & lanjutkan" (Figma 2497:4919): only a heartbeat newer than the tap counts.
struct SafariCheckTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func nothingNewerThanTheTapDecidesNothing() {
        #expect(SafariCheck.result(of: .active(lastSeen: nil), since: start) == nil)
        #expect(SafariCheck.result(of: .active(lastSeen: start.addingTimeInterval(-1)), since: start) == nil)
        #expect(SafariCheck.result(of: .off(lastSeen: nil, reason: .notSeen), since: start) == nil)
        // An old "some sites only" heartbeat is not this check's answer either.
        #expect(SafariCheck.result(of: .off(lastSeen: start.addingTimeInterval(-30), reason: .someSitesOnly), since: start) == nil)
    }

    @Test func aFreshHeartbeatPassesOrAsksForEveryWebsite() {
        let fresh = start.addingTimeInterval(3)
        #expect(SafariCheck.result(of: .active(lastSeen: fresh), since: start) == .passed)
        #expect(SafariCheck.result(of: .active(lastSeen: start), since: start) == .passed)
        #expect(SafariCheck.result(of: .off(lastSeen: fresh, reason: .someSitesOnly), since: start) == .someSitesOnly)
        // Switched off after the page loaded: not passed, keep looking.
        #expect(SafariCheck.result(of: .off(lastSeen: fresh, reason: .switchedOff), since: start) == nil)
    }

    @Test func runStopsAtTheFirstFreshHeartbeat() async {
        var reads = 0
        let result = await SafariCheck.run(since: start, times: 10, every: .zero) {
            reads += 1
            return .active(lastSeen: reads < 3 ? nil : start.addingTimeInterval(1))
        }
        #expect(result == .passed)
        #expect(reads == 3)
    }

    @Test func runReportsSomeSitesOnly() async {
        let result = await SafariCheck.run(since: start, times: 3, every: .zero) {
            .off(lastSeen: start.addingTimeInterval(1), reason: .someSitesOnly)
        }
        #expect(result == .someSitesOnly)
    }

    /// "Ask" with no answer to Safari's prompt, or another default browser: nothing arrives.
    @Test func runEndsAsNotSeenWithoutAFreshHeartbeat() async {
        var reads = 0
        let result = await SafariCheck.run(since: start, times: 4, every: .zero) {
            reads += 1
            return .active(lastSeen: start.addingTimeInterval(-60))
        }
        #expect(result == .notSeen)
        #expect(reads == 4)
    }

    @Test func toastsFollowTheResult() {
        #expect(SafariCheckToast(.passed) == nil)
        #expect(SafariCheckToast(.someSitesOnly)?.pose == .tapHere)
        #expect(SafariCheckToast(.notSeen)?.pose == .think)
    }

    @Test func thePageIsOnJoinShooAiIdInTheAppLanguage() {
        let url = SafariCheck.pageURL(language: .indonesian, api: AppConfig.cloudAPIURL)
        #expect(url.absoluteString == "https://join.shoo.ai.id/safari-check?lang=id")
        // Only `/j/*` is a Universal Link there (backend app-site-association.ts), so this opens in the browser.
        #expect(!url.path().hasPrefix("/j/"))
        #expect(SafariCheck.pageURL(language: .english, api: AppConfig.cloudAPIURL).query() == "lang=en")
    }

    @Test func aLocalWorkerServesThePageItself() {
        let local = URL(string: "http://localhost:8787")!
        #expect(SafariCheck.pageURL(language: .indonesian, api: local).absoluteString == "http://localhost:8787/safari-check?lang=id")
    }
}

struct ExtensionSetupTests {
    @Test(arguments: [
        // All Websites → Allow is a required step on every version (usability test 20 Nov 2026).
        (17, 5, [ExtensionSetup.Step.openSettingsLegacy, .switchOn, .allowEveryWebsite, .comeBack]),
        (18, 0, [.openSettingsModern, .switchOn, .allowEveryWebsite, .comeBack]),
        (26, 1, [.openSettingsModern, .switchOn, .allowEveryWebsite, .comeBack]),
        (26, 2, [.tapTurnOn, .switchOn, .allowEveryWebsite, .comeBack]),
        (27, 0, [.tapTurnOn, .switchOn, .allowEveryWebsite, .comeBack]),
    ])
    func stepsFollowIOSVersion(major: Int, minor: Int, expected: [ExtensionSetup.Step]) {
        #expect(ExtensionSetup.steps(for: OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)) == expected)
    }

    @Test func extensionIdentifierIsDerivedFromTheAppBundle() throws {
        let app = try #require(Bundle.main.bundleIdentifier)
        #expect(ExtensionSetup.extensionIdentifier == app + ".extension")
    }
}

/// PR-03 (Figma "Flow · Protected buka link undangan"): everyone onboards as Pribadi. An invite link only keeps
/// its code; the join sheet opens with it once onboarding is done.
extension OnboardingModelTests {
    @Test func inviteLinkStillOnboardsAsPersonal() async {
        env.router.pendingJoinCode = "482193"
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        #expect(model.step == .turnOnExtension)
        model.consentChecked = true
        #expect(await model.activateExtension())
        #expect(settings.mode == .guardian)
        // Registering as Pribadi keeps the code: the join sheet needs it after onboarding.
        #expect(env.router.pendingJoinCode == "482193")
    }

    @Test func finishingWithAnInviteOpensTheJoinSheetWithTheCode() async {
        env.router.pendingJoinCode = "482193"
        let model = await registeredPersonal()
        await reachSuccess(model)
        await model.requestNotifications()
        #expect(settings.onboardingCompleted)
        // The sheet waits for the tabs: asked for before they show, it would be lost in the cross-fade.
        #expect(!env.router.isJoinFamilyPresented)
        env.presentInviteAfterOnboarding()
        #expect(env.router.isJoinFamilyPresented)
        #expect(env.router.takePendingJoinCode() == "482193")
        // Only once: the next time the tabs show (no new link) nothing opens.
        env.router.isJoinFamilyPresented = false
        env.presentInviteAfterOnboarding()
        #expect(!env.router.isJoinFamilyPresented)
    }

    @Test func finishingWithoutAnInviteOpensNothing() async {
        let model = await registeredPersonal()
        await reachSuccess(model)
        await model.requestNotifications()
        env.presentInviteAfterOnboarding()
        #expect(!env.router.isJoinFamilyPresented)
        #expect(!env.router.isConnectPresented)
    }

    /// An older build registered this device as Protected mid-onboarding: it carries on at ON-04.
    @Test func olderProtectedRegistrationContinuesAtTurnOn() {
        #expect(settings.chooseMode(.protected))
        #expect(model().step == .turnOnExtension)
    }

    @Test func needsDataConsentOnlyAfterOnboarding() {
        // A real fresh install: the question is not answered yet.
        settings.dataConsent = nil
        #expect(settings.chooseMode(.protected))
        #expect(!env.needsDataConsent)
        settings.onboardingCompleted = true
        #expect(env.needsDataConsent)
    }
}
