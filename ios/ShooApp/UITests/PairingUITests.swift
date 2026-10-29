import XCTest

/// Fase 14: Connect (PR-01/02/03) and Family code (GD-04) against the mock.
/// Mock codes: `000000` code_invalid · `999999` code_expired · `888888` family_full; any other 6 digits join "Adhella".
final class PairingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(mode: String, onboarded: Bool = true, language: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMock", "YES",
            "-settings.language", language,
            "-UITestExtensionActive", "YES",
            "-UITestNotifications", "denied",
            "-settings.familyModeOn", "YES",
        ] + extra
        if onboarded {
            app.launchArguments += [
                "-settings.onboardingCompleted", "YES",
                "-settings.onboardingConnectPassed", "YES",
                "-settings.mode", mode,
            ]
        } else {
            app.launchArguments += ["-UITestReset", "YES"]
        }
        app.launch()
        return app
    }

    @MainActor
    private func enter(_ code: String, in app: XCUIApplication) {
        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        if let current = field.value as? String, !current.isEmpty, current != "6-digit code" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(code)
    }

    /// iOS asks "Open in “Shoo”?" for a custom scheme opened from outside the app.
    @MainActor
    private func openLink(_ link: String, in app: XCUIApplication) {
        app.open(URL(string: link)!)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
    }

    @MainActor
    func testOnboardingConnectShowsErrorsThenWhoProtectsMe() {
        let app = launch(mode: "protected", onboarded: false)
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 10))
        app.buttons["splash.skip"].tap()
        let name = app.textFields["name.field"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Mom")
        app.buttons["name.continue"].tap()
        // Same steps as OnboardingUITests: the CI runner is slow, so wait for each screen before tapping.
        let protected = app.buttons["mode.protected"]
        XCTAssertTrue(protected.waitForExistence(timeout: 10), app.debugDescription)
        protected.tap()
        let next = app.buttons["mode.continue"]
        let enabled = NSPredicate(format: "isEnabled == true")
        wait(for: [expectation(for: enabled, evaluatedWith: next)], timeout: 5)
        next.tap()
        XCTAssertTrue(app.descendants(matching: .any)["greeting.avatar"].firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["greeting.continue"].tap()

        let join = app.buttons["connect.join"]
        XCTAssertTrue(join.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(join.isEnabled)
        enter("000000", in: app)
        join.tap()
        let error = app.staticTexts["connect.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(error.label.contains("doesn't match"), error.label)

        enter("999999", in: app)
        XCTAssertFalse(error.exists, "Editing the code clears the error")
        join.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("expired"), error.label)

        enter("482193", in: app)
        join.tap()
        let title = app.staticTexts["protectedBy.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(title.label.contains("Adhella"), title.label)
        app.buttons["protectedBy.continue"].tap()
        XCTAssertTrue(app.buttons["extensionOn.continue"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["extensionOn.continue"].tap()
        XCTAssertTrue(app.buttons["notifications.skip"].waitForExistence(timeout: 10), app.debugDescription)
    }

    /// A new install opened from an invite link (WhatsApp): no mode choice, Connect has the code, one tap joins.
    @MainActor
    func testInviteLinkOnNewInstallSkipsModeChoice() {
        let app = launch(mode: "protected", onboarded: false)
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 10))
        openLink("shoo://join?code=482193", in: app)
        app.buttons["splash.skip"].tap()
        let name = app.textFields["name.field"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Mom")
        app.buttons["name.continue"].tap()
        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["mode.protected"].exists)
        XCTAssertEqual(field.value as? String, "482193")
        app.buttons["connect.join"].tap()
        XCTAssertTrue(app.staticTexts["protectedBy.title"].waitForExistence(timeout: 10), app.debugDescription)
    }

    /// T11: an invite link only fills the code; nothing joins until Connect is tapped.
    @MainActor
    func testInviteLinkOpensConnectWithTheCodeFilled() {
        let app = launch(mode: "protected")
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 10), app.debugDescription)
        openLink("shoo://join?code=482193", in: app)
        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(field.value as? String, "482193")
        XCTAssertFalse(app.staticTexts["protectedBy.title"].exists)
        // The mock Protected already has a guardian: the server answers already_connected.
        app.buttons["connect.join"].tap()
        let error = app.staticTexts["connect.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(error.label.contains("already connected"), error.label)
    }

    @MainActor
    func testScanTabExplainsWhenTheCameraCannotScan() {
        let app = launch(mode: "protected")
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 10))
        openLink("shoo://join?code=482193", in: app)
        XCTAssertTrue(app.textFields["connect.code"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["connect.tab.scan"].tap()
        // The simulator has no camera: a note and the Code tab stay, never a blank screen.
        XCTAssertTrue(app.descendants(matching: .any)["connect.scanner"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testFamilyCodeShowsQRCodeAndCountdown() {
        // "Invite your family" shows while no one is connected yet (GD-03).
        let app = launch(mode: "guardian", extra: ["-mock.scenario", "empty"])
        let invite = app.buttons["family.invite"]
        XCTAssertTrue(invite.waitForExistence(timeout: 10), app.debugDescription)
        invite.tap()
        let code = app.staticTexts["familyCode.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.images["familyCode.qr"].exists)
        let countdown = app.staticTexts["familyCode.countdown"]
        XCTAssertTrue(countdown.exists)
        let first = countdown.label
        let ticked = NSPredicate(format: "label != %@", first)
        wait(for: [expectation(for: ticked, evaluatedWith: countdown)], timeout: 5)
        app.buttons["familyCode.copy"].tap()
        XCTAssertTrue(app.buttons["familyCode.copy"].label.contains("Copied"), app.buttons["familyCode.copy"].label)
        XCTAssertTrue(app.descendants(matching: .any)["familyCode.members"].firstMatch.label.contains("0 of 3"))
        app.buttons["familyCode.done"].tap()
        XCTAssertTrue(invite.waitForExistence(timeout: 5))
    }

    @MainActor
    func testFullFamilyHasNoCodeButton() {
        let app = launch(mode: "guardian", extra: ["-mock.scenario", "threeMembers"])
        let profile = app.buttons["profileButton"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10), app.debugDescription)
        profile.tap()
        let invite = app.buttons["profile.invite"]
        XCTAssertTrue(invite.waitForExistence(timeout: 10), app.debugDescription)
        invite.tap()
        // Family full: the invite sheet hands out no code.
        let full = app.staticTexts["Your family is full (3 people). Remove someone to invite another person."]
        XCTAssertTrue(full.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["invite.code"].exists)
    }

    // Removing a member: Profile's member detail since PF-01 (ProfileUITests.testGuardianDisconnectsAMemberFromTheDetail).
}
