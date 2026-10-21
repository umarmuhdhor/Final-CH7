import XCTest

/// Fase 05: Guardian Shield (GD-01), Family mode toggle (GD-02), family cards (GD-03), Family Activity (GD-05).
final class GuardianUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(familyMode: Bool?, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", "guardian",
            "-settings.language", "en",
            "-UITestExtensionActive", "YES",
        ] + extra
        if let familyMode {
            app.launchArguments += ["-settings.familyModeOn", familyMode ? "YES" : "NO"]
        }
        app.launch()
        return app
    }

    @MainActor
    func testFamilyModeIsRememberedAfterRelaunch() {
        var app = launch(familyMode: false)
        XCTAssertTrue(app.descendants(matching: .any)["shield.status.active"].waitForExistence(timeout: 10), app.debugDescription)
        // Guardian's own Shield has no "Protected by" row.
        XCTAssertFalse(app.descendants(matching: .any)["shield.guardian"].exists)
        app.buttons["familyModeToggle"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["family.header"].waitForExistence(timeout: 5), app.debugDescription)

        app.terminate()
        app = launch(familyMode: nil)
        XCTAssertTrue(app.descendants(matching: .any)["family.header"].waitForExistence(timeout: 10), app.debugDescription)
        // Leave it off for the next run.
        app.buttons["familyModeToggle"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["shield.status.active"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFamilyCardOpensDetailWithVerdictButtons() {
        let app = launch(familyMode: true)
        let mom = app.buttons["family.member.dev_mom"]
        XCTAssertTrue(mom.waitForExistence(timeout: 10), app.debugDescription)
        let dad = app.descendants(matching: .any)["family.member.dev_dad"]
        XCTAssertTrue(dad.exists)
        XCTAssertTrue(dad.label.contains("Not connected"), dad.debugDescription)
        XCTAssertFalse(mom.label.contains("Not connected"), mom.debugDescription)

        mom.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.header"].waitForExistence(timeout: 5))
        // Guardian validates family items from Detail (GD-07, fase 03).
        XCTAssertTrue(app.buttons["detail.verdict.notSafe"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEmptyFamilyOffersInvite() {
        let app = launch(familyMode: true, extra: ["-mock.scenario", "empty"])
        let invite = app.buttons["family.invite"]
        XCTAssertTrue(invite.waitForExistence(timeout: 10), app.debugDescription)
        invite.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testFamilyActivityFiltersByPerson() {
        let app = launch(familyMode: true, extra: ["-debug.tab", "activity"])
        let mom = app.buttons["person.dev_mom"]
        XCTAssertTrue(mom.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["person.everyone"].isSelected)
        mom.tap()
        XCTAssertTrue(mom.isSelected)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        for index in 0..<rows.count {
            XCTAssertTrue(rows.element(boundBy: index).label.contains("Mom"), rows.element(boundBy: index).debugDescription)
        }
    }

    @MainActor
    func testFamilyModeOffShowsOwnActivityOnly() {
        let app = launch(familyMode: false, extra: ["-debug.tab", "activity"])
        XCTAssertTrue(app.buttons["filter.all"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["person.everyone"].exists)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(rows.count, 1)
    }
}
