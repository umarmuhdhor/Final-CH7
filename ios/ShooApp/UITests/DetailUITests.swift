import XCTest

/// Fase 03: Detail (DT-01..06) and the guardian's verdict buttons (GD-07), on fixtures.
final class DetailUITests: XCTestCase {
    static let blocked92 = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"
    static let warning41 = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e01"
    static let markedSafe = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e05"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func openDetail(
        _ scanId: String, mode: String = "guardian", language: String = "en", pageCopy: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        if pageCopy { app.launchArguments += ["-debug.replicaFixture", "YES"] }
        app.launchArguments += [
            "-UITestMock", "YES",
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", mode,
            "-settings.language", language,
            "-debug.detail", scanId,
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["detail.header"].waitForExistence(timeout: 10), app.debugDescription)
        return app
    }

    /// fase 18b: the page copy is drawn into the cards, with its line above them.
    @MainActor
    func testPageCopyShowsWithItsLine() {
        let app = openDetail(Self.blocked92, pageCopy: true)
        let line = app.descendants(matching: .any)["detail.pageCopy"].firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(line.label.contains("Copy of the page"), line.label)
        XCTAssertTrue(line.label.contains("Copied from bca-verifikasi.site/login/pin"), line.label)
        XCTAssertTrue(app.buttons["detail.screenshot"].firstMatch.isEnabled)
        XCTAssertFalse(app.webViews.firstMatch.exists, "no live web view on screen")
    }

    @MainActor
    func testGuardianMarksNotSafeAtOnce() {
        let app = openDetail(Self.blocked92)
        let header = app.descendants(matching: .any)["detail.header"]
        XCTAssertTrue((header.value as? String ?? "").contains("Blocked"))
        XCTAssertTrue(app.descendants(matching: .any)["detail.link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["detail.owner"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["detail.evidence.2"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["detail.evidence.3"].exists)

        app.buttons["detail.verdict.notSafe"].tap()

        // No confirmation dialog: the label changes right away.
        XCTAssertEqual(app.alerts.count, 0)
        let note = app.descendants(matching: .any)["detail.verdictNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue((header.value as? String ?? "").contains("Verified scam by you"), header.debugDescription)
        // The card replaces the buttons; "Change" is only offered on a safe verdict (Figma 480:5768).
        XCTAssertFalse(app.buttons["detail.verdict.notSafe"].exists)
        XCTAssertFalse(app.buttons["detail.verdictChange"].exists)
    }

    @MainActor
    func testChangeBringsTheButtonsBackOnASafeVerdict() {
        let app = openDetail(Self.markedSafe)
        XCTAssertFalse(app.buttons["detail.verdict.safe"].exists)
        let change = app.buttons["detail.verdictChange"]
        XCTAssertTrue(change.waitForExistence(timeout: 5), app.debugDescription)
        change.tap()
        XCTAssertTrue(app.buttons["detail.verdict.notSafe"].waitForExistence(timeout: 5))
        app.buttons["detail.verdict.notSafe"].tap()
        let header = app.descendants(matching: .any)["detail.header"]
        let expectation = expectation(for: NSPredicate(format: "value CONTAINS 'Verified scam by you'"), evaluatedWith: header)
        wait(for: [expectation], timeout: 5)
    }

    @MainActor
    func testScreenshotZoomHasNoShareOrSave() {
        let app = openDetail(Self.blocked92)
        let screenshot = app.buttons["detail.screenshot"].firstMatch
        // The first photo sits under the verdict footer until scrolled.
        app.swipeUp()
        XCTAssertTrue(screenshot.waitForExistence(timeout: 5), app.debugDescription)
        screenshot.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.screenshotZoomed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Share"].exists)
        XCTAssertFalse(app.buttons["Save Image"].exists)
        app.buttons["detail.screenshotClose"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.header"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWarningTakesAVerdictAndHasNoPhotoWithoutAScreenshot() {
        let app = openDetail(Self.warning41)
        XCTAssertTrue((app.descendants(matching: .any)["detail.header"].value as? String ?? "").contains("Warning"))
        // GD-07: warnings take a verdict too (Figma 416:9469, #190).
        XCTAssertTrue(app.buttons["detail.verdict.safe"].exists)
        XCTAssertFalse(app.buttons["detail.screenshot"].exists)
    }

    @MainActor
    func testProtectedSeesSimpleWordsAndNoButtons() {
        let app = openDetail(Self.blocked92, mode: "protected")
        XCTAssertFalse(app.buttons["detail.verdict.safe"].exists)
        XCTAssertFalse(app.buttons["detail.verdict.notSafe"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["detail.owner"].exists)
        let first = app.descendants(matching: .any)["detail.evidence.0"]
        XCTAssertEqual(first.label, "This site was made 3 days ago, adds 30 percent to the risk score")
    }

    @MainActor
    func testProtectedIndonesianVerdictNote() {
        let app = openDetail(Self.markedSafe, mode: "protected", language: "id")
        let header = app.descendants(matching: .any)["detail.header"]
        XCTAssertTrue((header.value as? String ?? "").contains("Ditandai aman oleh Adhella"), header.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["detail.verdictNote"].exists)
        XCTAssertFalse(app.buttons["detail.verdictChange"].exists)
    }

    /// Screens below the fold for the UI gate (attached to the result bundle, `keepAlways`).
    @MainActor
    func testBelowTheFoldScreens() {
        let app = openDetail(Self.blocked92)
        attach(app, "blocked-92-guardian-en-top")
        app.swipeUp()
        XCTAssertTrue(app.buttons["detail.screenshot"].firstMatch.waitForExistence(timeout: 5))
        attach(app, "blocked-92-guardian-en-bottom")
        app.buttons["detail.screenshot"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.screenshotZoomed"].waitForExistence(timeout: 5))
        attach(app, "blocked-92-guardian-en-zoom")
        app.buttons["detail.screenshotClose"].tap()
        app.buttons["detail.verdict.notSafe"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.verdictNote"].waitForExistence(timeout: 5))
        app.swipeDown()
        attach(app, "blocked-92-guardian-en-after-not-safe")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
