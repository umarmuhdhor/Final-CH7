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
        var arguments = ["-settings.language", "en", "-UITestNotifications", notifications]
        if extensionActive { arguments += ["-UITestExtensionActive", "YES"] }
        if let extensionStatus { arguments += ["-UITestExtensionStatus", extensionStatus] }
        return XCUIApplication.mock(arguments)
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
        let next = mode == "guardian" ? "invite.open" : "connect.tabs"
        XCTAssertTrue(app.descendants(matching: .any)[next].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    private func passSafariDefault(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["safariDefault.alreadyUsing"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["safariDefault.alreadyUsing"].tap()
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
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        // F3: a Back tap while the push still runs can be lost on a slow runner.
        app.tap(app.buttons["onboarding.back"], until: app.buttons["invite.open"])
    }

    @MainActor
    func testSplashHasTwoSlidesSkipAndBack() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Browse calmer, feeling safe."].waitForExistence(timeout: 10))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Looks real, may not be safe.\nLet Shoo check."].waitForExistence(timeout: 5), app.debugDescription)
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["Browse calmer, feeling safe."].waitForExistence(timeout: 5))
        app.buttons["splash.next"].tap()
        XCTAssertTrue(app.staticTexts["Looks real, may not be safe.\nLet Shoo check."].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["*Your name can be up to 20 characters"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["name.continue"].isEnabled)
    }

    @MainActor
    func testGuardianOnboardingEndsOnHomeWithReminderWhenNotificationsDenied() {
        let app = launch(notifications: "denied")
        register(app, name: "Rina", mode: "guardian")
        XCTAssertFalse(app.navigationBars.buttons.firstMatch.exists)
        XCTAssertTrue(app.buttons["invite.skip"].waitForExistence(timeout: 5))
        // Nothing is saved yet, so Back still reaches ON-03 (Figma).
        XCTAssertTrue(app.buttons["onboarding.back"].exists)
        app.buttons["invite.skip"].tap()
        // ON-04 passes on its own because the extension counts as on.
        passSafariDefault(app)
        // Next asks for notifications; the mock answers "denied".
        XCTAssertTrue(app.buttons["extensionOn.continue"].waitForExistence(timeout: 5))
        app.buttons["extensionOn.continue"].tap()
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 5))
        // ON-05 reminder as a popup on Home.
        let reminder = app.alerts["Notifications are off"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(reminder.buttons["Turn on"].firstMatch.exists)
        reminder.buttons["Not now"].firstMatch.tap()
        XCTAssertFalse(reminder.waitForExistence(timeout: 2))
    }

    @MainActor
    func testProtectedGoesThroughConnectToHome() {
        let app = launch(notifications: "granted")
        register(app, name: "Mom", mode: "protected")
        XCTAssertTrue(app.buttons["connect.skip"].waitForExistence(timeout: 5))
        app.buttons["connect.skip"].tap()
        passSafariDefault(app)
        XCTAssertTrue(app.buttons["extensionOn.continue"].waitForExistence(timeout: 5))
        app.buttons["extensionOn.continue"].tap()
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Notifications are off"].exists)
    }

    @MainActor
    func testExtensionOffStaysOnTurnOnScreenAndRelaunchGoesHome() {
        let app = launch(extensionActive: false)
        register(app, name: "Rina", mode: "guardian")
        skipInvite(app)
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["extension.offHint"].waitForExistence(timeout: 5))

        // Relaunch without reset: the saved mode goes to Home, never back to the mode choice.
        app.terminate()
        let again = XCUIApplication.mock(["-settings.language", "en", "-UITestNotifications", "denied"], reset: false)
        XCTAssertTrue(again.tabBars.buttons["Shield"].waitForExistence(timeout: 10), again.debugDescription)
        XCTAssertFalse(again.buttons["mode.continue"].exists)
    }

    @MainActor
    func testNarrowedAccessOffersSafariAndSettings() {
        let app = launch(extensionActive: false, extensionStatus: "someSitesOnly")
        register(app, name: "Rina", mode: "guardian")
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
        skipInvite(app)
        XCTAssertTrue(app.buttons["extension.skipCheck"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["extension.openSafari"].exists)
        app.buttons["extension.skipCheck"].tap()
        XCTAssertTrue(app.buttons["safariDefault.open"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSafariDefaultTurnsIntoKeepGoingAfterSettingsAndBackStays() {
        let app = launch()
        register(app, name: "Rina", mode: "guardian")
        skipInvite(app)
        XCTAssertTrue(app.buttons["safariDefault.open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["safariDefault.alreadyUsing"].exists)
        app.buttons["safariDefault.open"].tap()
        app.activate()
        XCTAssertTrue(app.buttons["safariDefault.continue"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["safariDefault.alreadyUsing"].exists)
        // Shoo is on, so ON-04 would pass again: Back stays there and offers Next.
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.buttons["extension.continue"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["extension.continue"].tap()
        XCTAssertTrue(app.buttons["safariDefault.open"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testVideoLinkOpensPlayer() {
        let app = launch(extensionActive: false)
        register(app, name: "Rina", mode: "guardian")
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
        skipInvite(app)
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5))
        app.buttons["extension.turnOn"].tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
    }
}
