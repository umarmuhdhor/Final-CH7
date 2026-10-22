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
        await model.register()
        return model
    }

    @Test func freshInstallStartsAtSplash() {
        #expect(model().step == .splash)
    }

    @Test func skipGoesToName() {
        let model = model()
        model.skipSplash()
        #expect(model.step == .name)
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
        #expect(model.step == .mode)
    }

    @Test func guardianPath() async {
        let model = await registered(.guardian)
        #expect(model.step == .greeting)
        #expect(model.avatarId.map(AvatarCatalog.ids.contains) == true)
        #expect(settings.mode == .guardian)
        #expect(!settings.onboardingCompleted)
        model.continueFromGreeting()
        #expect(model.step == .turnOnExtension)
    }

    @Test func protectedPathGoesThroughConnect() async {
        let model = await registered(.protected)
        model.continueFromGreeting()
        #expect(model.step == .connect)
        model.continueFromConnect()
        #expect(model.step == .turnOnExtension)
    }

    @Test func registrationNeedsAMode() async {
        let model = model()
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        await model.register()
        #expect(model.step == .mode)
        #expect(settings.mode == nil)
    }

    @Test func registrationErrorStaysOnModeStep() async throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults, preferredLanguages: ["en"])
        let env = AppEnvironment(
            repository: FailingRepository(), settings: settings, notifications: notifications, extensionStatus: { .off(lastSeen: nil) }
        )
        let model = OnboardingModel(environment: env)
        model.skipSplash()
        model.name = "Rina"
        model.submitName()
        model.selectedMode = .guardian
        await model.register()
        #expect(model.step == .mode)
        #expect(model.registrationFailed)
        #expect(settings.mode == nil)
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
        first.continueFromGreeting()
        first.continueFromConnect()
        #expect(model().step == .turnOnExtension)
    }

    @Test func extensionOffStaysActiveContinues() async {
        let model = await registered(.guardian)
        model.continueFromGreeting()
        model.refreshExtensionStatus()
        #expect(model.step == .turnOnExtension)
        box.status = .active(lastSeen: Date())
        model.refreshExtensionStatus()
        #expect(model.step == .notifications)
    }

    @Test func guardianFinishesEvenWhenPermissionIsDenied() async {
        notifications.answer = .denied
        let model = await registered(.guardian)
        model.continueFromGreeting()
        box.status = .active(lastSeen: Date())
        model.refreshExtensionStatus()
        await model.requestNotifications()
        #expect(notifications.requestCount == 1)
        #expect(model.step == .done)
        #expect(settings.onboardingCompleted)
        #expect(NotificationReminder.isShown(status: .denied, mode: .guardian))
    }

    @Test func protectedMaySkipNotifications() async {
        let model = await registered(.protected)
        model.continueFromGreeting()
        model.continueFromConnect()
        box.status = .active(lastSeen: Date())
        model.refreshExtensionStatus()
        #expect(model.canSkipNotifications)
        model.skipNotifications()
        #expect(notifications.requestCount == 0)
        #expect(settings.onboardingCompleted)
    }

    @Test func guardianCannotSkipNotifications() async {
        let model = await registered(.guardian)
        #expect(!model.canSkipNotifications)
        model.skipNotifications()
        #expect(!settings.onboardingCompleted)
    }

    @Test func alreadyDecidedPermissionIsNotAskedAgain() async {
        notifications.current = .authorized
        let model = await registered(.guardian)
        model.continueFromGreeting()
        box.status = .active(lastSeen: Date())
        model.refreshExtensionStatus()
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

struct ExtensionSetupTests {
    @Test(arguments: [
        (17, 5, ExtensionSetup.Step.openSettingsLegacy),
        (18, 0, .openSettingsModern),
        (26, 1, .openSettingsModern),
        (26, 2, .tapTurnOn),
        (27, 0, .tapTurnOn),
    ])
    func firstStepFollowsIOSVersion(major: Int, minor: Int, first: ExtensionSetup.Step) {
        let steps = ExtensionSetup.steps(for: OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0))
        #expect(steps.first == first)
        #expect(steps.last == .openAWebsite)
        #expect(steps.count == 4)
    }

    @Test func extensionIdentifierIsDerivedFromTheAppBundle() throws {
        let app = try #require(Bundle.main.bundleIdentifier)
        #expect(ExtensionSetup.extensionIdentifier == app + ".extension")
    }
}
