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
        let app = XCUIApplication.mock([
            "-settings.onboardingCompleted", "YES",
            "-settings.onboardingConnectPassed", "YES",
            "-settings.mode", mode,
            "-settings.language", "en",
            "-settings.familyModeOn", "YES",
            "-UITestExtensionActive", "YES",
            "-UITestNotifications", "granted",
        ])
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
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
        // F4: tapped as soon as Shield exists, the tap could land before the mock had loaded.
        app.tap(app.buttons["profileButton"], until: app.buttons["profile.back"].firstMatch)
        // Profile is pushed on Shield: the link still lands on Detail.
        openLink("shoo://scan/\(Self.blocked)", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["detail.header"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["detail.verdict.safe"].exists, app.debugDescription)
        // Detail hides the tab bar (Figma); back lands on the Activity tab.
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.tabBars.buttons["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Activity"].isSelected)
    }

    /// QA 2026-11-10 #1 and #9: a push tap (same `Router.openDetail` as this link) from Home, with motion on,
    /// froze the app at 100 % CPU (DetailFooter's safe-area state fed the tab bar's hide transition) and left
    /// the tab bar over Aman / Bahaya. The tab bar must be gone and the buttons hittable, twice in a row.
    @MainActor
    func testScanLinkFromHomeWithMotionShowsHittableVerdictButtons() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMock", "YES", "-UITestReset", "YES",
            "-settings.onboardingCompleted", "YES", "-settings.onboardingConnectPassed", "YES",
            "-settings.mode", "guardian", "-settings.language", "en", "-settings.familyModeOn", "YES",
            "-UITestExtensionActive", "YES", "-UITestNotifications", "granted",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["profileButton"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        for round in 0..<2 {
            openLink("shoo://scan/\(Self.blocked)", in: app)
            XCTAssertTrue(app.descendants(matching: .any)["detail.header"].waitForExistence(timeout: 10), "round \(round)\n\(app.debugDescription)")
            let safe = app.buttons["detail.verdict.safe"]
            XCTAssertTrue(safe.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(app.tabBars.firstMatch.waitForNonExistence(timeout: 5), "tab bar still shown, round \(round)")
            XCTAssertTrue(safe.isHittable, "Aman covered, round \(round)")
            // Figma: the buttons end 34 pt above the screen's bottom edge.
            XCTAssertEqual(app.windows.firstMatch.frame.maxY - safe.frame.maxY, 34, accuracy: 1.5, "round \(round)")
            app.buttons["detail.back"].tap()
            XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 5), app.debugDescription)
            app.tabBars.buttons["Shield"].tap()
            XCTAssertTrue(app.buttons["profileButton"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        }
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
