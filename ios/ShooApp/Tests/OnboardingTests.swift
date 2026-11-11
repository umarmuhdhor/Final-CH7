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
        #expect(model.canGoBackFromConnect)
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

/// Fase 27d (K6): the invite link path. Consent comes before the device registers, a failed join can be
/// undone honestly (the device is deleted on the server), and ON-04 never asks or overwrites an answer twice.
extension OnboardingModelTests {
    @MainActor
    struct Invite {
        let settings: AppSettings
        let repository: InviteRepository
        let env: AppEnvironment
        let box = StatusBox()
        let linked: LinkedAccountSettings

        init() throws {
            let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
            settings = AppSettings(defaults: defaults, preferredLanguages: ["en"])
            // A real fresh install: the question is not answered yet.
            settings.dataConsent = nil
            repository = InviteRepository()
            let box = box
            env = AppEnvironment(
                repository: repository, settings: settings,
                notifications: FakeNotificationPermission(), extensionStatus: { box.status }
            )
            linked = LinkedAccountSettings(defaults: try #require(UserDefaults(suiteName: "linked.\(UUID().uuidString)")))
        }

        func model() -> OnboardingModel { OnboardingModel(environment: env, linked: linked) }

        /// Opened from an invite link, name typed, Next.
        func named(code: String = "482193") -> OnboardingModel {
            env.router.pendingJoinCode = code
            let model = model()
            model.skipSplash()
            model.name = "Rina"
            model.submitName()
            return model
        }

        /// Invite link, consent answered, on Connect with `code` (not joined yet).
        func onConnect(code: String = "482193", consent: DataConsent = .granted) -> OnboardingModel {
            let model = named(code: code)
            model.answerConsent(consent)
            return model
        }

        // MARK: Consent before registration (F-A1)

        @Test func consentComesBeforeConnectAndTheCodeSurvivesTheBackground() async {
            let model = named()
            #expect(model.step == .consent)
            #expect(await repository.registerCount == 0)
            // RootView empties the router's code when the app goes to the background.
            env.router.pendingJoinCode = nil
            model.answerConsent(.granted)
            #expect(settings.dataConsent == .granted)
            #expect(model.step == .connect)
            #expect(model.connect().code == "482193")
            #expect(await repository.registerCount == 0, "nothing registers before the Connect tap")
        }

        @Test func backFromConsentKeepsTheCode() {
            let model = named()
            model.goBack()
            #expect(model.step == .name)
            env.router.pendingJoinCode = nil
            model.submitName()
            #expect(model.step == .consent)
            model.answerConsent(.declined)
            #expect(model.connect().code == "482193")
        }

        @Test func anAnswerGivenEarlierSkipsTheConsentStep() {
            settings.dataConsent = .declined
            let model = named()
            #expect(model.step == .connect)
        }

        @Test func joinKeepsOnboardingOnScreen() async {
            let model = onConnect()
            await model.connect().join()
            #expect(settings.mode == .protected)
            #expect(!env.needsDataConsent, "the consent screen must not replace onboarding mid-flow")
            #expect(await repository.registerCount == 1)
            #expect(!settings.inviteRegistrationPending)
        }

        @Test func aWrongCodeThenTheRightOneRegistersOnce() async {
            let model = onConnect(code: "000000")
            let connect = model.connect()
            await connect.join()
            #expect(connect.problem == .invalid)
            connect.code = "482193"
            await connect.join()
            guard case .joined = connect.state else {
                Issue.record("expected joined, got \(connect.state)")
                return
            }
            #expect(await repository.registerCount == 1)
        }

        @Test func protectedRelaunchContinuesAtTurnOnWithoutBack() async {
            let model = onConnect()
            await model.connect().join()
            model.continueFromConnect()
            let relaunched = self.model()
            #expect(relaunched.step == .turnOnExtension, "invite join skipped ON-04 (step = \(relaunched.step))")
            // A new Connect would only answer `already_connected`.
            #expect(!relaunched.canGoBackFromExtension)
        }

        @Test func guardianRelaunchStillGoesHome() async {
            settings.dataConsent = .granted
            let model = model()
            model.skipSplash()
            model.name = "Rina"
            model.submitName()
            _ = await model.activateExtension()
            #expect(self.model().step == .done)
        }

        @Test func consentGivenOnTheStepLeavesNoBoxOnTurnOn() async {
            let model = onConnect(consent: .granted)
            await model.connect().join()
            model.continueFromConnect()
            #expect(model.step == .turnOnExtension)
            #expect(!model.showsConsentCheckbox)
            #expect(model.canTurnOn)
            #expect(await model.activateExtension())
            box.status = .active(lastSeen: Date())
            await model.refreshExtensionStatus()
            #expect(model.step == .safariDefault)
        }

        @Test func declinedConsentIsNeverOverwritten() async {
            let model = onConnect(consent: .declined)
            await model.connect().join()
            model.continueFromConnect()
            #expect(!model.showsConsentCheckbox)
            #expect(model.canTurnOn)
            await model.skipExtensionCheck()
            #expect(model.step == .safariDefault)
            #expect(settings.dataConsent == .declined)
        }

        @Test func declinedThenFailedJoinThenNotNowTurnsOnAsPersonal() async {
            let model = onConnect(code: "999999", consent: .declined)
            await model.connect().join()
            await model.skipConnect()
            #expect(model.step == .turnOnExtension)
            #expect(settings.mode == nil)
            #expect(await repository.deleteCount == 1)
            #expect(model.canTurnOn)
            #expect(await model.activateExtension())
            #expect(settings.mode == .guardian)
            #expect(settings.dataConsent == .declined)
        }

        // MARK: Failed join (F-A2)

        @Test(arguments: ["999999", "000000", "888888"])
        func failedJoinKeepsTheRegistrationAndBackDeletesIt(code: String) async {
            let model = onConnect(code: code)
            await model.connect().join()
            // Kept, so Connect can be tried again with the same device.
            #expect(settings.mode == .protected)
            #expect(settings.inviteRegistrationPending)
            #expect(model.canGoBackFromConnect)
            await model.backFromConnect()
            #expect(await repository.deleteCount == 1)
            #expect(settings.mode == nil)
            #expect(!settings.inviteRegistrationPending)
            #expect(!settings.onboardingConnectPassed)
            #expect(settings.dataConsent == .granted, "the answer stays")
            #expect(model.step == .name)
            // The code is forgotten: Next now continues as Pribadi.
            model.submitName()
            #expect(model.step == .turnOnExtension)
        }

        @Test func notNowAfterAFailedJoinContinuesAsPersonal() async {
            let model = onConnect(code: "999999")
            await model.connect().join()
            await model.skipConnect()
            #expect(await repository.deleteCount == 1)
            #expect(settings.mode == nil)
            #expect(model.step == .turnOnExtension)
            #expect(model.selectedMode == .guardian)
        }

        @Test func alreadyDeletedOnTheServerCountsAsDeleted() async {
            let model = onConnect(code: "999999")
            await model.connect().join()
            await repository.failDelete(with: RepositoryError.api(.notFound, message: "gone"))
            await model.backFromConnect()
            #expect(settings.mode == nil)
            #expect(model.step == .name)
        }

        @Test func offlineDeleteStaysOnConnect() async {
            let model = onConnect(code: "999999")
            await model.connect().join()
            await repository.failDelete(with: RepositoryError.network)
            await model.backFromConnect()
            #expect(settings.mode == .protected)
            #expect(settings.inviteRegistrationPending)
            #expect(model.step == .connect)
            #expect(model.connect().problem == .offline)
        }

        @Test func noProfileAnswerDeletesNothing() async {
            let model = onConnect(code: "999999")
            await model.connect().join()
            await repository.failMe(with: RepositoryError.network)
            await model.backFromConnect()
            #expect(await repository.deleteCount == 0)
            #expect(settings.mode == .protected)
            #expect(model.step == .connect)
            #expect(model.connect().problem == .offline)
        }

        @Test func aJoinThatCommittedAfterAllIsKept() async {
            let model = onConnect()
            // The server joined, the answer got lost.
            await repository.loseNextJoinAnswer()
            await model.connect().join()
            #expect(model.connect().problem == .offline)
            await model.backFromConnect()
            #expect(await repository.deleteCount == 0)
            guard case .joined(let guardian) = model.connect().state else {
                Issue.record("expected joined, got \(model.connect().state)")
                return
            }
            #expect(guardian == MockRepository.fixtureGuardian)
            #expect(settings.onboardingConnectPassed)
            #expect(!settings.inviteRegistrationPending)
        }

        @Test func alreadyConnectedAfterALostAnswerMeansJoined() async {
            let model = onConnect()
            await repository.loseNextJoinAnswer()
            let connect = model.connect()
            await connect.join()
            await connect.join()
            guard case .joined = connect.state else {
                Issue.record("expected joined, got \(connect.state) / \(String(describing: connect.problem))")
                return
            }
            #expect(connect.problem == nil)
            #expect(!settings.inviteRegistrationPending)
        }

        @Test func cancelWaitsWhileJoining() async {
            let model = onConnect()
            await repository.holdNextJoin()
            async let join: Void = model.connect().join()
            await repository.waitUntilHeld()
            #expect(model.connect().state == .joining)
            #expect(model.isConnectBusy)
            await model.backFromConnect()
            await model.skipConnect()
            #expect(model.step == .connect)
            await repository.release()
            await join
            #expect(await repository.deleteCount == 0)
            guard case .joined = model.connect().state else {
                Issue.record("expected joined, got \(model.connect().state)")
                return
            }
        }

        @Test func connectCannotJoinWhileCancelling() async {
            let model = onConnect(code: "999999")
            let connect = model.connect()
            await connect.join()
            connect.code = "482193"
            #expect(connect.canJoin)
            await repository.holdNextMe()
            async let back: Void = model.backFromConnect()
            await repository.waitUntilHeld()
            #expect(model.isConnectBusy)
            #expect(!connect.canJoin)
            await connect.join()
            await repository.release()
            await back
            #expect(await repository.joinCount == 1)
            #expect(model.step == .name)
        }

        @Test func aRelaunchOnConnectCanStillCancel() async {
            let first = onConnect(code: "999999")
            await first.connect().join()
            let relaunched = model()
            #expect(relaunched.step == .connect)
            #expect(relaunched.canGoBackFromConnect)
            await relaunched.backFromConnect()
            #expect(settings.mode == nil)
            #expect(relaunched.step == .name)
        }

        @Test func aFlagWithoutARegistrationIsDroppedAtLaunch() {
            // The app died during `POST /devices`.
            settings.inviteRegistrationPending = true
            _ = model()
            #expect(!settings.inviteRegistrationPending)
        }

        @Test func registrationFailureClearsTheFlag() async throws {
            let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
            let settings = AppSettings(defaults: defaults, preferredLanguages: ["en"])
            settings.dataConsent = .granted
            let env = AppEnvironment(repository: FailingRepository(), settings: settings, notifications: FakeNotificationPermission())
            env.router.pendingJoinCode = "482193"
            let model = OnboardingModel(environment: env, linked: linked)
            model.skipSplash()
            model.name = "Rina"
            model.submitName()
            await model.connect().join()
            #expect(settings.mode == nil)
            #expect(!settings.inviteRegistrationPending)
        }

        @Test func needsDataConsentOnlyAfterOnboarding() {
            #expect(settings.chooseMode(.protected))
            #expect(!env.needsDataConsent)
            settings.onboardingCompleted = true
            #expect(env.needsDataConsent)
        }
    }
}

/// `MockRepository` with counters, a lost join answer, injected failures and one call that can be held.
actor InviteRepository: ShooRepository {
    private let base = MockRepository(mode: .guardian, latency: .zero)
    private(set) var registerCount = 0
    private(set) var joinCount = 0
    private(set) var deleteCount = 0
    private var meFailure: (any Error)?
    private var deleteFailure: (any Error)?
    private var losesJoinAnswer = false
    private var holdsJoin = false
    private var holdsMe = false
    private var held: CheckedContinuation<Void, Never>?
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []

    func failMe(with error: any Error) { meFailure = error }
    func failDelete(with error: any Error) { deleteFailure = error }
    func loseNextJoinAnswer() { losesJoinAnswer = true }
    func holdNextJoin() { holdsJoin = true }
    func holdNextMe() { holdsMe = true }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }
    func release() {
        held?.resume()
        held = nil
    }

    private func hold() async {
        await withCheckedContinuation { continuation in
            held = continuation
            heldWaiters.forEach { $0.resume() }
            heldWaiters = []
        }
    }

    func registerDevice(name: String, mode: UserMode, avatarId: String?, apnsToken: String?) async throws -> DeviceRegistration {
        registerCount += 1
        return try await base.registerDevice(name: name, mode: mode, avatarId: avatarId, apnsToken: apnsToken)
    }
    func me() async throws -> DeviceProfile {
        if holdsMe {
            holdsMe = false
            await hold()
        }
        if let meFailure { throw meFailure }
        return try await base.me()
    }
    func joinFamily(code: String) async throws -> GuardianInfo {
        joinCount += 1
        if holdsJoin {
            holdsJoin = false
            await hold()
        }
        let guardian = try await base.joinFamily(code: code)
        if losesJoinAnswer {
            losesJoinAnswer = false
            throw RepositoryError.network
        }
        return guardian
    }
    func deleteMe() async throws {
        deleteCount += 1
        if let deleteFailure { throw deleteFailure }
        try await base.deleteMe()
    }
    func updateMe(_ update: DeviceUpdate) async throws { try await base.updateMe(update) }
    func createFamilyCode(refresh: Bool) async throws -> FamilyCode { try await base.createFamilyCode(refresh: refresh) }
    func familyMembers() async throws -> [FamilyMember] { try await base.familyMembers() }
    func removeMember(deviceId: String) async throws { try await base.removeMember(deviceId: deviceId) }
    func leaveGuardian() async throws { try await base.leaveGuardian() }
    func setMemberNotify(deviceId: String, notify: Bool) async throws { try await base.setMemberNotify(deviceId: deviceId, notify: notify) }
    func remindMember(deviceId: String) async throws { try await base.remindMember(deviceId: deviceId) }
    func becomeProtected(code: String) async throws -> ProtectedSwitch { try await base.becomeProtected(code: code) }
    func scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?) async throws -> ScanPage {
        try await base.scans(owner: owner, status: status, cursor: cursor)
    }
    func scan(id: String) async throws -> ScanResult { try await base.scan(id: id) }
    func setVerdict(scanId: String, value: Verdict.Value) async throws -> Verdict {
        try await base.setVerdict(scanId: scanId, value: value)
    }
}
