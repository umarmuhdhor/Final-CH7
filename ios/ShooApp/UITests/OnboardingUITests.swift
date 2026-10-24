import XCTest

/// Fase 02: ON-01 … ON-05 on a fresh install. Launch arguments (DEBUG only) replace the parts the
/// simulator can't do: `-UITestExtensionActive YES` stands in for the Safari heartbeat, and
/// `-UITestNotifications granted|denied` answers the permission prompt without a system alert.
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(extensionActive: Bool = true, notifications: String = "denied") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMock", "YES",
            "-UITestReset", "YES",
            "-settings.language", "en",
            "-UITestNotifications", notifications,
        ]
        if extensionActive { app.launchArguments += ["-UITestExtensionActive", "YES"] }
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
        // ON-04 passes on its own because the extension counts as on.
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
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Shoo is off."].exists)

        // Relaunch without reset: the saved mode skips straight back to ON-04.
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments += ["-UITestMock", "YES", "-settings.language", "en", "-UITestNotifications", "denied"]
        again.launch()
        XCTAssertTrue(again.buttons["extension.turnOn"].waitForExistence(timeout: 10))
        XCTAssertFalse(again.buttons["mode.continue"].exists)
    }

    @MainActor
    func testVideoLinkOpensPlayer() {
        let app = launch(extensionActive: false)
        register(app, name: "Rina", mode: "guardian")
        app.buttons["greeting.continue"].tap()
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
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5))
        app.buttons["extension.turnOn"].tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
    }
}
