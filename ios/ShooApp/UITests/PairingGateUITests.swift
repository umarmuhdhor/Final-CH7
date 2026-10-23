import XCTest

/// Fase 14 UI gate: Connect, its error, "You're protected by …" and Family code in EN/ID, against the mock.
/// Skipped unless the runner gets `SHOO_SHOT_DIR`. The host sets the appearance first
/// (`xcrun simctl ui <udid> appearance light|dark`) and names it in `SHOO_GATE_APPEARANCE`;
/// `SHOO_GATE_AXXL=1` adds Dynamic Type AX-XL.
final class PairingGateUITests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(environment["SHOO_SHOT_DIR"] != nil, "UI gate screenshots only")
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let directory = URL(fileURLWithPath: environment["SHOO_SHOT_DIR"]!)
        try? app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }

    @MainActor
    private func launch(_ arguments: [String], language: String, size: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestMock", "YES",
            "-settings.language", language,
            "-UIPreferredContentSizeCategoryName", size,
            "-UITestNotifications", "denied",
            "-UITestExtensionActive", "YES",
        ] + arguments
        app.launch()
        return app
    }

    /// At AX-XL most buttons start below the keyboard or the fold.
    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        element.tap()
    }

    @MainActor
    func testScreenshots() {
        let appearance = environment["SHOO_GATE_APPEARANCE"] ?? "light"
        var sizes = [("UICTContentSizeCategoryL", "")]
        if environment["SHOO_GATE_AXXL"] == "1" { sizes.append(("UICTContentSizeCategoryAccessibilityXL", "-axxl")) }
        for language in ["en", "id"] {
            for (size, suffix) in sizes {
                let tag = "\(language)-\(appearance)\(suffix)"
                var app = launch(["-UITestReset", "YES"], language: language, size: size)
                // Registered through ON-03 so the mock Protected has no guardian yet.
                XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 10), app.debugDescription)
                app.buttons["splash.skip"].tap()
                let name = app.textFields["name.field"]
                XCTAssertTrue(name.waitForExistence(timeout: 5))
                name.tap()
                name.typeText("Mom")
                tap(app.buttons["name.continue"], in: app)
                tap(app.buttons["mode.protected"], in: app)
                tap(app.buttons["mode.continue"], in: app)
                tap(app.buttons["greeting.continue"], in: app)
                let field = app.textFields["connect.code"]
                XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
                field.tap()
                field.typeText("0000")
                shot(app, "connect-\(tag)")
                let join = app.buttons["connect.join"]
                if !join.isHittable { app.swipeUp() }
                join.tap()
                XCTAssertTrue(app.staticTexts["connect.error"].waitForExistence(timeout: 5), app.debugDescription)
                shot(app, "connect-error-\(tag)")
                field.tap()
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "4821")
                if !join.isHittable { app.swipeUp() }
                join.tap()
                XCTAssertTrue(app.staticTexts["protectedBy.title"].waitForExistence(timeout: 5), app.debugDescription)
                shot(app, "protected-by-\(tag)")
                app.terminate()

                app = launch(
                    ["-settings.onboardingCompleted", "YES", "-settings.onboardingConnectPassed", "YES",
                     "-settings.mode", "guardian", "-settings.familyModeOn", "NO"],
                    language: language, size: size
                )
                let profile = app.buttons["profileButton"]
                XCTAssertTrue(profile.waitForExistence(timeout: 10), app.debugDescription)
                profile.tap()
                XCTAssertTrue(app.textFields["profile.name"].waitForExistence(timeout: 10), app.debugDescription)
                // A List only builds rows near the screen: scroll until the button is there.
                let familyCode = app.buttons["profile.familyCode"]
                for _ in 0..<8 where !familyCode.exists || !familyCode.isHittable { app.swipeUp() }
                XCTAssertTrue(familyCode.isHittable, app.debugDescription)
                familyCode.tap()
                XCTAssertTrue(app.staticTexts["familyCode.code"].waitForExistence(timeout: 5), app.debugDescription)
                shot(app, "family-code-\(tag)")
                app.terminate()
            }
        }
    }
}
