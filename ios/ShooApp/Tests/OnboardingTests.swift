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

    @Test func emojiCountsAsOneCharacter() {
        let family = "👨‍👩‍👧"
        #expect(NameRule.validate(String(repeating: family, count: 20)) == .success(String(repeating: family, count: 20)))
        #expect(NameRule.validate(String(repeating: family, count: 21)) == .failure(.tooLong))
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
        settings = AppSettings(defaults: defaults, preferredLanguages: ["en"])
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
    func registeredPersonal() async -> OnboardingModel {
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        model.consentChecked = true
        _ = await model.activateExtension()
        return model
    }

    /// Protected from an invite link: name, Connect, join.
    func joinedProtected() async -> OnboardingModel {
        env.router.pendingJoinCode = "482193"
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        await model.connect().join()
        return model
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

    @Test func turnOnNeedsTheConsentBox() async {
        settings.dataConsent = nil
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        #expect(!model.consentChecked)
        #expect(!(await model.activateExtension()))
        #expect(settings.mode == nil)
        #expect(settings.dataConsent == nil)
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
        let settings = AppSettings(defaults: defaults, preferredLanguages: ["en"])
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
        #expect(settings.mode == nil)
    }

    @Test func inviteLinkGoesThroughConnect() {
        env.router.pendingJoinCode = "482193"
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        #expect(model.step == .connect)
        #expect(model.selectedMode == .protected)
        // Connect still gets the code: nothing joins until the user taps Connect (T11).
        #expect(model.connect().code == "482193")
        #expect(model.connect().state == .entering)
        #expect(model.canGoBackToName)
        model.goBack()
        #expect(model.step == .name)
    }

    @Test func notNowOnConnectContinuesAsPersonal() async {
        env.router.pendingJoinCode = "482193"
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        await model.skipConnect()
        #expect(model.step == .turnOnExtension)
        #expect(model.selectedMode == .guardian)
        #expect(settings.mode == nil)
    }

    @Test func joiningRegistersFirstAndStaysPassedAfterRelaunch() async {
        let model = await joinedProtected()
        let connect = model.connect()
        #expect(settings.mode == .protected)
        guard case .joined = connect.state else {
            Issue.record("expected joined, got \(connect.state)")
            return
        }
        #expect(settings.onboardingConnectPassed)
        // Back from ON-04 finds the same guardian, not an empty form.
        model.continueFromConnect()
        model.goBack()
        #expect(model.step == .connect)
        #expect(model.connect() === connect)
    }

    @Test func personalRelaunchGoesHome() async {
        _ = await registeredPersonal()
        #expect(model().step == .done)
    }

    @Test func extensionOffStaysActiveContinues() async {
        let model = await registeredPersonal()
        await model.refreshExtensionStatus()
        #expect(model.step == .turnOnExtension)
        box.status = .active(lastSeen: Date())
        await model.refreshExtensionStatus()
        #expect(model.step == .safariDefault)
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
        #expect(model.step == .safariDefault)
    }

    /// Through ON-04 and Safari Default to the success screen.
    func reachSuccess(_ model: OnboardingModel) async {
        if model.step == .connect { model.continueFromConnect() }
        model.consentChecked = true
        box.status = .active(lastSeen: Date())
        await model.refreshExtensionStatus()
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

    @Test func protectedIsAskedForNotificationsToo() async {
        let model = await joinedProtected()
        await reachSuccess(model)
        await model.requestNotifications()
        #expect(notifications.requestCount == 1)
        #expect(settings.onboardingCompleted)
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

struct ExtensionSetupTests {
    @Test(arguments: [
        // Figma "Aktifkan Ekstensi": three steps; what Safari still needs shows as a note once back (#135).
        (17, 5, [ExtensionSetup.Step.openSettingsLegacy, .switchOn, .comeBack]),
        (18, 0, [.openSettingsModern, .switchOn, .comeBack]),
        (26, 1, [.openSettingsModern, .switchOn, .comeBack]),
        (26, 2, [.tapTurnOn, .switchOn, .comeBack]),
        (27, 0, [.tapTurnOn, .switchOn, .comeBack]),
    ])
    func stepsFollowIOSVersion(major: Int, minor: Int, expected: [ExtensionSetup.Step]) {
        #expect(ExtensionSetup.steps(for: OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)) == expected)
    }

    @Test func extensionIdentifierIsDerivedFromTheAppBundle() throws {
        let app = try #require(Bundle.main.bundleIdentifier)
        #expect(ExtensionSetup.extensionIdentifier == app + ".extension")
    }
}
