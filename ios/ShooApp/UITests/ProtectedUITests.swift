import XCTest

/// Fase 04: Protected Shield (PR-04) and Activity (PR-05), on fixtures.
final class ProtectedUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(extensionActive: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMock", "YES",
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", "protected",
            "-settings.language", "en",
        ] + extra
        if extensionActive {
            app.launchArguments += ["-UITestExtensionActive", "YES"]
        }
        app.launch()
        return app
    }

    @MainActor
    func testShieldShowsGuardianAndOpensLastBlocked() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["shield.status.active"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["shield.turnOn"].exists)
        let guardian = app.descendants(matching: .any)["shield.guardian"]
        XCTAssertTrue(guardian.waitForExistence(timeout: 5))
        XCTAssertTrue(guardian.label.contains("Adhella"), guardian.debugDescription)

        let card = app.buttons["shield.lastBlocked"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), app.debugDescription)
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.header"].waitForExistence(timeout: 5))
        // Protected users never see the guardian's verdict buttons (GD-07).
        XCTAssertFalse(app.buttons["detail.verdict.safe"].exists)
        XCTAssertFalse(app.buttons["detail.verdict.notSafe"].exists)
    }

    @MainActor
    func testShieldOffOffersTurnOn() {
        let app = launch(extensionActive: false)
        XCTAssertTrue(app.descendants(matching: .any)["shield.status.off"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["shield.turnOn"].exists)

        // Turn on opens ON-04's guide as a sheet; Close brings Shield back.
        app.buttons["shield.turnOn"].tap()
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["turnOn.close"].tap()
        XCTAssertTrue(app.buttons["shield.turnOn"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testShieldEmptyShowsNothingBlocked() {
        let app = launch(extra: ["-mock.scenario", "empty"])
        XCTAssertTrue(app.descendants(matching: .any)["shield.nothingBlocked"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor
    func testActivityFiltersAndOpensDetail() {
        let app = launch(extra: ["-debug.tab", "activity"])
        let all = app.buttons["filter.all"]
        XCTAssertTrue(all.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(all.isSelected)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), app.debugDescription)

        app.buttons["filter.blocked"].tap()
        XCTAssertTrue(app.buttons["filter.blocked"].isSelected)
        let first = rows.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(first.label.contains("Blocked"), first.debugDescription)
        XCTAssertFalse(first.label.contains("Warning"), first.debugDescription)

        first.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.header"].waitForExistence(timeout: 5))
    }
}
