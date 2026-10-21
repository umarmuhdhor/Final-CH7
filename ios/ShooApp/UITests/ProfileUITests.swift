import XCTest

/// Fase 06: Profile (PF-01) for both modes.
final class ProfileUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func openProfile(mode: String, language: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-settings.onboardingCompleted", "YES",
            "-settings.onboardingConnectPassed", "YES",
            "-settings.mode", mode,
            "-settings.language", language,
            "-settings.familyModeOn", "NO",
            "-UITestExtensionActive", "YES",
        ] + extra
        app.launch()
        let button = app.buttons["profileButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
        button.tap()
        XCTAssertTrue(app.textFields["profile.name"].waitForExistence(timeout: 5), app.debugDescription)
        return app
    }

    @MainActor
    func testGuardianSeesFamilyCodeNotDisconnect() {
        let app = openProfile(mode: "guardian")
        XCTAssertEqual(app.textFields["profile.name"].value as? String, "Adhella")
        XCTAssertTrue(app.descendants(matching: .any)["profile.extension.active"].exists)
        XCTAssertFalse(app.buttons["profile.disconnect"].exists)
        let familyCode = app.buttons["profile.familyCode"]
        if !familyCode.exists { app.swipeUp() }
        XCTAssertTrue(familyCode.waitForExistence(timeout: 5), app.debugDescription)
        // "Delete my data" waits for the contract (C19).
        XCTAssertFalse(app.buttons["profile.delete"].exists)
    }

    @MainActor
    func testLanguageSwitchesTheWholeAppAtOnce() {
        let app = openProfile(mode: "guardian")
        app.buttons["languagePicker"].tap()
        let indonesian = app.buttons["Bahasa Indonesia"]
        XCTAssertTrue(indonesian.waitForExistence(timeout: 5), app.debugDescription)
        indonesian.tap()
        XCTAssertTrue(app.navigationBars["Profil"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["profile.done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Aktivitas"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Kamu terlindungi"].exists, app.debugDescription)

        // Back to English for the next run.
        app.buttons["profileButton"].tap()
        app.buttons["languagePicker"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testNameEditFollowsTheOnboardingRule() {
        let app = openProfile(mode: "guardian")
        let field = app.textFields["profile.name"]
        field.tap()
        field.typeText(String(repeating: "x", count: 15))
        XCTAssertTrue(app.staticTexts["Use 20 characters or fewer."].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["profile.saveName"].isEnabled)
    }

    @MainActor
    func testProtectedDisconnectGoesBackToConnect() {
        let app = openProfile(mode: "protected")
        let guardian = app.descendants(matching: .any)["profile.guardian"]
        XCTAssertTrue(guardian.waitForExistence(timeout: 5))
        XCTAssertTrue(guardian.label.contains("Adhella"), guardian.debugDescription)
        XCTAssertFalse(app.buttons["profile.familyCode"].exists)
        let disconnect = app.buttons["profile.disconnect"]
        if !disconnect.isHittable { app.swipeUp() }
        disconnect.tap()
        // Standard iOS confirmation (allowed here: not a GD-07 verdict).
        let confirm = app.buttons["profile.disconnect.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Connect to your guardian"].waitForExistence(timeout: 10), app.debugDescription)
    }
}
