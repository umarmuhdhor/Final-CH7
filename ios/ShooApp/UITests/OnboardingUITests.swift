import XCTest

/// Fase 02: ON-01 … ON-05 on a fresh install. Launch arguments (DEBUG only) replace the parts the
/// simulator can't do: `-UITestExtensionActive YES` stands in for the Safari heartbeat, and
/// `-UITestNotifications granted|denied` answers the permission prompt without a system alert.
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(extensionActive: Bool = true, extensionStatus: String? = nil, notifications: String = "denied") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMock", "YES",
            "-UITestReset", "YES",
            "-settings.language", "en",
            "-UITestNotifications", notifications,
        ]
        if extensionActive { app.launchArguments += ["-UITestExtensionActive", "YES"] }
        if let extensionStatus { app.launchArguments += ["-UITestExtensionStatus", extensionStatus] }
        app.launch()
        return app
    }

    @MainActor
    private func register(_ app: XCUIApplication, name: String, mode: String) {
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 10))
        app.buttons["splash.skip"].tap()
        let field = app.textFields["name.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["name.continue"].isEnabled)
        field.tap()
        field.typeText(name)
        app.buttons["name.continue"].tap()
        XCTAssertTrue(app.buttons["mode.\(mode)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["mode.continue"].isEnabled)
        app.buttons["mode.\(mode)"].tap()
        app.buttons["mode.continue"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["greeting.avatar"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hi, \(name)!"].exists)
    }

    @MainActor
    private func skipInvite(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["invite.skip"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["invite.skip"].tap()
    }

    @MainActor
    func testGuardianInviteSheetShowsCodeThenGoesToExtension() {
        let app = launch(extensionActive: false)
        register(app, name: "Rina", mode: "guardian")
        app.buttons["greeting.continue"].tap()
        XCTAssertTrue(app.buttons["invite.open"].waitForExistence(timeout: 5))
        app.buttons["invite.open"].tap()
        XCTAssertTrue(app.images["invite.qr"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["invite.code"].exists)
        XCTAssertTrue(app.buttons["invite.copy"].isEnabled)
        // Close keeps the Guardian on the invite screen; Done moves on to ON-04.
        app.buttons["invite.close"].tap()
        XCTAssertTrue(app.buttons["invite.open"].waitForExistence(timeout: 5))
        app.buttons["invite.open"].tap()
        XCTAssertTrue(app.buttons["invite.done"].waitForExistence(timeout: 5))
        app.buttons["invite.done"].tap()
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.buttons["invite.open"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSplashHasTwoSlidesSkipAndBack() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Browse calmer, feeling safe."].waitForExistence(timeout: 10))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Scams look real.\nShoo looks closer."].waitForExistence(timeout: 5))
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["Browse calmer, feeling safe."].waitForExistence(timeout: 5))
        app.buttons["splash.next"].tap()
        XCTAssertTrue(app.staticTexts["Scams look real.\nShoo looks closer."].waitForExistence(timeout: 5))
        app.buttons["splash.skip"].tap()
        XCTAssertTrue(app.textFields["name.field"].waitForExistence(timeout: 5))
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testNameLongerThanTwentyCharactersIsRejected() {
        let app = launch()
        app.buttons["splash.skip"].tap()
        let field = app.textFields["name.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: "a", count: 21))
        XCTAssertTrue(app.staticTexts["Use 20 characters or fewer."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["name.continue"].isEnabled)
    }

    @MainActor
    func testGuardianOnboardingEndsOnHomeWithReminderWhenNotificationsDenied() {
        let app = launch(notifications: "denied")
        register(app, name: "Rina", mode: "guardian")
        // No way back to ON-03.
        XCTAssertFalse(app.navigationBars.buttons.firstMatch.exists)
        app.buttons["greeting.continue"].tap()
        XCTAssertTrue(app.buttons["invite.skip"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding.back"].exists)
        app.buttons["invite.skip"].tap()
        // ON-04 passes on its own because the extension counts as on.
        XCTAssertTrue(app.buttons["extensionOn.continue"].waitForExistence(timeout: 5))
        app.buttons["extensionOn.continue"].tap()
        XCTAssertTrue(app.buttons["notifications.allow"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["notifications.skip"].exists)
        app.buttons["notifications.allow"].tap()
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["notificationReminder"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testProtectedGoesThroughConnectAndMaySkipNotifications() {
        let app = launch(notifications: "granted")
        register(app, name: "Mom", mode: "protected")
        app.buttons["greeting.continue"].tap()
        XCTAssertTrue(app.buttons["connect.skip"].waitForExistence(timeout: 5))
        app.buttons["connect.skip"].tap()
        XCTAssertTrue(app.buttons["extensionOn.continue"].waitForExistence(timeout: 5))
        app.buttons["extensionOn.continue"].tap()
        XCTAssertTrue(app.buttons["notifications.skip"].waitForExistence(timeout: 5))
        app.buttons["notifications.skip"].tap()
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["notificationReminder"].firstMatch.exists)
    }

    @MainActor
    func testExtensionOffStaysOnTurnOnScreenAndRelaunchNeverReturnsToModeChoice() {
        let app = launch(extensionActive: false)
        register(app, name: "Rina", mode: "guardian")
        app.buttons["greeting.continue"].tap()
        skipInvite(app)
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["extension.offHint"].waitForExistence(timeout: 5))

        // Relaunch without reset: the saved mode skips straight back to ON-04.
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments += ["-UITestMock", "YES", "-settings.language", "en", "-UITestNotifications", "denied"]
        again.launch()
        XCTAssertTrue(again.buttons["extension.turnOn"].waitForExistence(timeout: 10))
        XCTAssertFalse(again.buttons["mode.continue"].exists)
    }

    @MainActor
    func testNarrowedAccessOffersSafariAndSettings() {
        let app = launch(extensionActive: false, extensionStatus: "someSitesOnly")
        register(app, name: "Rina", mode: "guardian")
        app.buttons["greeting.continue"].tap()
        skipInvite(app)
        XCTAssertTrue(app.buttons["extension.openSafari"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["extension.settings"].exists)
        XCTAssertFalse(app.buttons["extension.skipCheck"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "can't check every website")).firstMatch.exists)
    }

    @MainActor
    func testSwitchOnWithoutAPageCanContinueWithoutChecking() {
        let app = launch(extensionActive: false, extensionStatus: "unchecked")
        register(app, name: "Rina", mode: "guardian")
        app.buttons["greeting.continue"].tap()
        skipInvite(app)
        XCTAssertTrue(app.buttons["extension.skipCheck"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["extension.openSafari"].exists)
        app.buttons["extension.skipCheck"].tap()
        XCTAssertTrue(app.buttons["extensionOn.continue"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testVideoLinkOpensPlayer() {
        let app = launch(extensionActive: false)
        register(app, name: "Rina", mode: "guardian")
        app.buttons["greeting.continue"].tap()
        skipInvite(app)
        XCTAssertTrue(app.buttons["extension.video"].waitForExistence(timeout: 5))
        app.buttons["extension.video"].tap()
        XCTAssertTrue(app.buttons["video.close"].waitForExistence(timeout: 5))
        app.buttons["video.close"].tap()
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTurnOnOpensSettings() {
        let app = launch(extensionActive: false)
        register(app, name: "Rina", mode: "guardian")
        app.buttons["greeting.continue"].tap()
        skipInvite(app)
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5))
        app.buttons["extension.turnOn"].tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
    }
}
