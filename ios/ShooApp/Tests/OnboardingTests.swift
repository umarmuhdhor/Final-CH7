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

    func registered(_ mode: UserMode) async -> OnboardingModel {
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        model.selectedMode = mode
        model.continueFromMode()
        try? await model.ensureRegistered()
        return model
    }

    @Test func freshInstallStartsAtSplash() {
        #expect(model().step == .splash)
    }

    @Test func withoutAnAnswerSkipGoesToConsentFirst() {
        settings.dataConsent = nil
        let model = model()
        model.skipSplash()
        #expect(model.step == .dataConsent)
        model.goBack()
        #expect(model.step == .splash)
    }

    @Test(arguments: [DataConsent.granted, .declined])
    func answeringConsentMovesToNameAndIsKept(answer: DataConsent) {
        settings.dataConsent = nil
        let model = model()
        model.skipSplash()
        model.answerDataConsent(answer)
        #expect(model.step == .name)
        #expect(settings.dataConsent == answer)
    }

    @Test func aRegisteredDeviceWithoutAnAnswerIsAskedOnce() {
        #expect(!env.needsDataConsent)
        #expect(settings.chooseMode(.guardian))
        settings.dataConsent = nil
        #expect(env.needsDataConsent)
        env.setDataConsent(.declined)
        #expect(!env.needsDataConsent)
    }

    @Test func skipGoesToName() {
        let model = model()
        model.skipSplash()
        #expect(model.step == .name)
    }

    @Test func invalidNameStaysOnNameStep() async {
        let model = model()
        model.skipSplash()
        model.name = "   "
        #expect(!model.canSubmitName)
        model.submitName()
        #expect(model.step == .name)
        model.name = "Rina"
        #expect(model.canSubmitName)
        model.submitName()
        #expect(model.step == .mode)
    }

    @Test func guardianPath() async {
        let model = await registered(.guardian)
        #expect(model.step == .invite)
        #expect(model.avatarId.map(AvatarCatalog.ids.contains) == true)
        #expect(settings.mode == .guardian)
        #expect(!settings.onboardingCompleted)
        model.continueFromInvite()
        #expect(model.step == .turnOnExtension)
        // Back to the invite screen is allowed; the mode stays saved.
        model.goBack()
        #expect(model.step == .invite)
        #expect(settings.mode == .guardian)
    }

    @Test func protectedPathGoesThroughConnect() async {
        let model = await registered(.protected)
        #expect(model.step == .connect)
        model.continueFromConnect()
        #expect(model.step == .turnOnExtension)
        // Figma: Back from ON-04 is Connect for a Protected, the mode stays saved.
        model.goBack()
        #expect(model.step == .connect)
        #expect(settings.mode == .protected)
    }

    @Test(arguments: [UserMode.guardian, .protected])
    func backReachesModeUntilTheDeviceIsRegistered(mode: UserMode) async throws {
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        model.selectedMode = mode
        model.continueFromMode()
        #expect(model.step == (mode == .guardian ? .invite : .connect))
        #expect(settings.mode == nil)
        #expect(model.canGoBackToMode)
        model.goBack()
        #expect(model.step == .mode)
        model.continueFromMode()
        try await model.ensureRegistered()
        #expect(settings.mode == mode)
        #expect(!model.canGoBackToMode)
        let stuck = model.step
        model.goBack()
        #expect(model.step == stuck)
    }

    @Test func joiningRegistersFirstAndStaysPassedAfterRelaunch() async {
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        model.selectedMode = .protected
        model.continueFromMode()
        let connect = model.connect()
        connect.code = "482193"
        await connect.join()
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

    @Test func modeStepNeedsAMode() {
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        model.continueFromMode()
        #expect(model.step == .mode)
        #expect(settings.mode == nil)
    }

    @Test func registrationErrorStaysOnInvite() async throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults, preferredLanguages: ["en"])
        settings.dataConsent = .granted
        let env = AppEnvironment(
            repository: FailingRepository(), settings: settings, notifications: notifications, extensionStatus: { .off(lastSeen: nil) }
        )
        let model = OnboardingModel(environment: env)
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        model.selectedMode = .guardian
        model.continueFromMode()
        await model.skipInvite()
        #expect(model.step == .invite)
        #expect(model.registrationFailed)
        #expect(settings.mode == nil)
    }

    @Test func registrationErrorStaysOnConnect() async throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults, preferredLanguages: ["en"])
        settings.dataConsent = .granted
        let env = AppEnvironment(
            repository: FailingRepository(), settings: settings, notifications: notifications, extensionStatus: { .off(lastSeen: nil) }
        )
        let model = OnboardingModel(environment: env)
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        model.selectedMode = .protected
        model.continueFromMode()
        await model.skipConnect()
        #expect(model.step == .connect)
        #expect(model.connect().problem != nil)
        #expect(settings.mode == nil)
    }

    @Test func inviteLinkSkipsMode() async {
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
    }

    @Test func modeIsPermanentAfterRegistration() async {
        _ = await registered(.protected)
        #expect(!settings.chooseMode(.guardian))
        #expect(settings.mode == .protected)
        // Relaunch before onboarding finished: never back to ON-03 (Protected resumes at Connect).
        let relaunched = model()
        #expect(relaunched.step == .connect)
    }

    @Test func protectedRelaunchResumesAtConnectUntilPassed() async {
        let first = await registered(.protected)
        #expect(model().step == .connect)
        first.continueFromConnect()
        #expect(model().step == .done)
    }

    @Test func extensionOffStaysActiveContinues() async {
        let model = await registered(.guardian)
        model.continueFromInvite()
        await model.refreshExtensionStatus()
        #expect(model.step == .turnOnExtension)
        box.status = .active(lastSeen: Date())
        await model.refreshExtensionStatus()
        #expect(model.step == .safariDefault)
        model.continueFromSafariDefault()
        #expect(model.step == .extensionOn)
    }

    @Test func backFromSafariDefaultStaysOnTurnOn() async {
        let model = await registered(.guardian)
        model.continueFromInvite()
        box.status = .active(lastSeen: Date())
        await model.refreshExtensionStatus()
        model.goBack()
        #expect(model.step == .turnOnExtension)
        // The screen re-reads the status on appear: Shoo is on, but Back must not bounce forward.
        await model.refreshExtensionStatus()
        #expect(model.step == .turnOnExtension)
        model.skipExtensionCheck()
        #expect(model.step == .safariDefault)
    }

    @Test func switchOnWithoutAPageWaitsForTheCheckOrASkip() async {
        let model = await registered(.guardian)
        model.continueFromInvite()
        // #135: Safari's switch is on, but no page has said whether Shoo may read every site.
        box.status = .active(lastSeen: nil)
        let status = await model.refreshExtensionStatus()
        #expect(status == .active(lastSeen: nil))
        #expect(model.step == .turnOnExtension)
        model.skipExtensionCheck()
        #expect(model.step == .safariDefault)
    }

    @Test func narrowedAccessStaysOnTurnOn() async {
        let model = await registered(.guardian)
        model.continueFromInvite()
        box.status = .off(lastSeen: Date(), reason: .someSitesOnly)
        #expect(await model.refreshExtensionStatus()?.nextStep == .allowEveryWebsite)
        #expect(model.step == .turnOnExtension)
        box.status = .active(lastSeen: Date())
        await model.refreshExtensionStatus()
        #expect(model.step == .safariDefault)
    }

    /// Through ON-04 and Safari Default to the success screen.
    func reachSuccess(_ model: OnboardingModel) async {
        if model.mode == .guardian { model.continueFromInvite() } else { model.continueFromConnect() }
        box.status = .active(lastSeen: Date())
        await model.refreshExtensionStatus()
        model.continueFromSafariDefault()
    }

    @Test func guardianRelaunchGoesHome() async {
        let first = await registered(.guardian)
        #expect(first.step == .invite)
        #expect(model().step == .done)
    }

    @Test func guardianFinishesEvenWhenPermissionIsDenied() async {
        notifications.answer = .denied
        let model = await registered(.guardian)
        await reachSuccess(model)
        await model.requestNotifications()
        #expect(notifications.requestCount == 1)
        #expect(model.step == .done)
        #expect(settings.onboardingCompleted)
        #expect(NotificationReminder.isShown(status: .denied, mode: .guardian))
    }

    @Test func protectedIsAskedForNotificationsToo() async {
        let model = await registered(.protected)
        await reachSuccess(model)
        await model.requestNotifications()
        #expect(notifications.requestCount == 1)
        #expect(settings.onboardingCompleted)
    }

    @Test func notificationsAreOnlyAskedFromTheSuccessScreen() async {
        let model = await registered(.guardian)
        await model.requestNotifications()
        #expect(notifications.requestCount == 0)
        #expect(!settings.onboardingCompleted)
    }

    @Test func alreadyDecidedPermissionIsNotAskedAgain() async {
        notifications.current = .authorized
        let model = await registered(.guardian)
        await reachSuccess(model)
        await model.requestNotifications()
        #expect(notifications.requestCount == 0)
        #expect(settings.onboardingCompleted)
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
        (17, 5, [ExtensionSetup.Step.openSettingsLegacy, .switchOn, .allowEveryWebsite, .openAWebsite]),
        (18, 0, [.openSettingsModern, .switchOn, .allowEveryWebsite, .openAWebsite]),
        (26, 1, [.openSettingsModern, .switchOn, .allowEveryWebsite, .openAWebsite]),
        // iOS 26.2+ reads Safari's switch directly: no website visit needed to be detected.
        (26, 2, [.tapTurnOn, .switchOn, .allowEveryWebsite]),
        (27, 0, [.tapTurnOn, .switchOn, .allowEveryWebsite]),
    ])
    func stepsFollowIOSVersion(major: Int, minor: Int, expected: [ExtensionSetup.Step]) {
        #expect(ExtensionSetup.steps(for: OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)) == expected)
    }

    @Test func extensionIdentifierIsDerivedFromTheAppBundle() throws {
        let app = try #require(Bundle.main.bundleIdentifier)
        #expect(ExtensionSetup.extensionIdentifier == app + ".extension")
    }
}
