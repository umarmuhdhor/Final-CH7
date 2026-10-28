import XCTest

/// Fase 13 step 5: the real app (`ApiRepository`) against a local backend (`pnpm -C backend/api dev`).
/// Skipped unless the runner gets `SHOO_LIVE_BACKEND=1`:
/// `TEST_RUNNER_SHOO_LIVE_BACKEND=1 TEST_RUNNER_SHOO_SHOT_DIR=<dir> xcodebuild test … -only-testing:ShooAppUITests/LiveBackendUITests`.
/// Screenshots go to `SHOO_SHOT_DIR` when it is set.
final class LiveBackendUITests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(environment["SHOO_LIVE_BACKEND"] == "1", "needs wrangler dev on localhost:8787")
    }

    @MainActor
    private func launch(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        // No -UITestMock: this is ApiRepository. The extension heartbeat is faked (no Safari in the test).
        app.launchArguments += [
            "-UITestReset", "YES",
            "-settings.language", language,
            "-UITestNotifications", "granted",
            "-UITestExtensionActive", "YES",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let directory = environment["SHOO_SHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? app.screenshot().pngRepresentation.write(to: url)
    }

    @MainActor
    private func register(_ app: XCUIApplication, name: String, mode: String) {
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 10))
        app.buttons["splash.skip"].tap()
        let field = app.textFields["name.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["name.continue"].tap()
        app.buttons["mode.\(mode)"].tap()
        app.buttons["mode.continue"].tap()
        // A real POST /devices: the greeting only shows after the server answered.
        XCTAssertTrue(app.staticTexts["Hi, \(name)!"].waitForExistence(timeout: 15), app.debugDescription)
        shot(app, "\(mode)-1-greeting")
        app.buttons["greeting.continue"].tap()
        if mode == "guardian" {
            XCTAssertTrue(app.buttons["invite.skip"].waitForExistence(timeout: 5), app.debugDescription)
            app.buttons["invite.skip"].tap()
        }
    }

    @MainActor
    func testGuardianOnboardingActivityAndProfile() {
        let app = launch()
        register(app, name: "Rina", mode: "guardian")
        XCTAssertTrue(app.buttons["extensionOn.continue"].waitForExistence(timeout: 5))
        app.buttons["extensionOn.continue"].tap()
        XCTAssertTrue(app.buttons["notifications.allow"].waitForExistence(timeout: 5))
        app.buttons["notifications.allow"].tap()
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 10))
        shot(app, "guardian-2-shield")

        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["activity.empty"].firstMatch.waitForExistence(timeout: 10),
                      app.debugDescription)
        shot(app, "guardian-3-activity-empty")

        app.buttons["profileButton"].tap()
        let manage = app.buttons["profile.manage"]
        XCTAssertTrue(manage.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<6 where !manage.isHittable { app.swipeUp() }
        manage.tap()
        let field = app.textFields["profile.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "Rina")
        // Cursor at the end of "Rina".
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(" B")
        app.buttons["profile.saveName"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["profile.error"].waitForExistence(timeout: 3), app.debugDescription)
        app.buttons["profile.back"].firstMatch.tap()
        let language = app.buttons["profile.language"]
        for _ in 0..<6 where !language.isHittable { app.swipeUp() }
        language.tap()
        app.buttons["language.id"].tap()
        XCTAssertTrue(app.staticTexts["Bahasa"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["profile.back"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Profil"].firstMatch.waitForExistence(timeout: 5))
        shot(app, "guardian-4-profile-renamed-id")
        app.buttons["profile.back"].firstMatch.tap()
    }

    @MainActor
    func testProtectedOnboardingInIndonesian() {
        let app = launch(language: "id")
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 10))
        app.buttons["splash.skip"].tap()
        let field = app.textFields["name.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Mom")
        app.buttons["name.continue"].tap()
        app.buttons["mode.protected"].tap()
        app.buttons["mode.continue"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["greeting.avatar"].firstMatch.waitForExistence(timeout: 15),
                      app.debugDescription)
        app.buttons["greeting.continue"].tap()
        XCTAssertTrue(app.buttons["connect.skip"].waitForExistence(timeout: 5))
        app.buttons["connect.skip"].tap()
        XCTAssertTrue(app.buttons["extensionOn.continue"].waitForExistence(timeout: 5))
        app.buttons["extensionOn.continue"].tap()
        XCTAssertTrue(app.buttons["notifications.skip"].waitForExistence(timeout: 5))
        app.buttons["notifications.skip"].tap()
        XCTAssertTrue(app.tabBars.buttons["Perisai"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["shield.nothingBlocked"].firstMatch.waitForExistence(timeout: 10),
                      app.debugDescription)
        shot(app, "protected-1-shield-id")

        // Back to the foreground: PATCH extensionLastSeenAt + GET /devices/me (D-alief-C06).
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.tabBars.buttons["Perisai"].waitForExistence(timeout: 10))
        sleep(2)
    }
}
