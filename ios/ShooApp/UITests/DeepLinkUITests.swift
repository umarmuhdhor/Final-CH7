import XCTest

/// Fase 15: `shoo://scan/{id}` (the extension's block screen, and the same target as a push tap) and
/// `shoo://activity`, against the mock. Push taps themselves are tested with `xcrun simctl push` (log fase 15).
final class DeepLinkUITests: XCTestCase {
    private static let blocked = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMock", "YES",
            "-settings.onboardingCompleted", "YES",
            "-settings.onboardingConnectPassed", "YES",
            "-settings.mode", mode,
            "-settings.language", "en",
            "-settings.familyModeOn", "YES",
            "-UITestExtensionActive", "YES",
            "-UITestNotifications", "granted",
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 10), app.debugDescription)
        return app
    }

    /// iOS asks "Open in “Shoo”?" for a custom scheme opened from outside the app.
    @MainActor
    private func openLink(_ link: String, in app: XCUIApplication) {
        app.open(URL(string: link)!)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
    }

    @MainActor
    func testScanLinkOpensDetailWithVerdictButtonsForTheGuardian() {
        let app = launch(mode: "guardian")
        app.buttons["profileButton"].tap()
        XCTAssertTrue(app.buttons["profile.back"].firstMatch.waitForExistence(timeout: 5))
        // Profile is pushed on Shield: the link still lands on Detail.
        openLink("shoo://scan/\(Self.blocked)", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["detail.header"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["detail.verdict.safe"].exists, app.debugDescription)
        // Detail hides the tab bar (Figma); back lands on the Activity tab.
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.tabBars.buttons["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Activity"].isSelected)
    }

    @MainActor
    func testScanLinkOpensDetailWithoutVerdictButtonsForProtected() {
        let app = launch(mode: "protected")
        openLink("shoo://scan/\(Self.blocked)", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["detail.header"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["detail.verdict.safe"].exists)
    }

    @MainActor
    func testActivityLinkOpensTheList() {
        let app = launch(mode: "guardian")
        openLink("shoo://activity", in: app)
        XCTAssertTrue(app.buttons["activity.row.\(Self.blocked)"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["Activity"].isSelected)
    }
}
