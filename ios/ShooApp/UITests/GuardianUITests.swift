import XCTest

/// Fase 05: Guardian Home (GD-01), Family mode pill (GD-02), family cards (GD-03), Family Activity (GD-05).
final class GuardianUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(familyMode: Bool?, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMock", "YES",
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
        // Guardian Home (GD-01): hero status, security strip, no "Protected by" row.
        XCTAssertTrue(app.descendants(matching: .any)["home.status.active"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["home.securityStatus"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["shield.guardian"].exists)
        app.descendants(matching: .any)["familyModeToggle"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["family.header"].waitForExistence(timeout: 5), app.debugDescription)

        app.terminate()
        app = launch(familyMode: nil)
        XCTAssertTrue(app.descendants(matching: .any)["family.header"].waitForExistence(timeout: 10), app.debugDescription)
        // Leave it off for the next run.
        app.descendants(matching: .any)["familyModeToggle"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.status.active"].waitForExistence(timeout: 5))
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
        // GD-04 (fase 14): the family code sheet.
        XCTAssertTrue(app.staticTexts["familyCode.code"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testFamilyActivityFiltersByPerson() {
        let app = launch(familyMode: true, extra: ["-debug.tab", "activity"])
        let picker = app.buttons["activity.personPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), app.debugDescription)
        // Everyone: members only, the guardian's own rows are left out (GD-05).
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        for index in 0..<rows.count {
            let label = rows.element(boundBy: index).label
            XCTAssertTrue(label.contains("Mom") || label.contains("Dad"), label)
        }
        XCTAssertTrue(app.buttons["filter.blocked"].label.contains("Danger"))

        picker.tap()
        XCTAssertTrue(app.buttons["person.everyone"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["person.everyone"].isSelected)
        app.buttons["person.dev_mom"].tap()
        XCTAssertEqual(picker.value as? String, "Mom")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        for index in 0..<rows.count {
            XCTAssertTrue(rows.element(boundBy: index).label.contains("Mom"), rows.element(boundBy: index).debugDescription)
        }

        // Back to everyone from the menu.
        picker.tap()
        app.buttons["person.everyone"].tap()
        XCTAssertEqual(picker.value as? String, "Everyone")
    }

    @MainActor
    func testHomeDisconnectShowsTheSwitchOffGuide() {
        let app = launch(familyMode: false)
        let disconnect = app.buttons["home.disconnect"]
        XCTAssertTrue(disconnect.waitForExistence(timeout: 10), app.debugDescription)
        disconnect.tap()
        XCTAssertTrue(app.buttons["turnOff.openSettings"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["turnOff.close"].tap()
        XCTAssertTrue(disconnect.waitForExistence(timeout: 5))
    }

    @MainActor
    func testHomeOffersTurnOnWhenTheExtensionIsOff() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMock", "YES",
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", "guardian",
            "-settings.language", "en",
            "-settings.familyModeOn", "NO",
            "-UITestExtensionStatus", "switchedOff",
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["home.status.off"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["home.turnOn"].exists)
    }

    @MainActor
    func testFamilyModeOffShowsOwnActivityOnly() {
        let app = launch(familyMode: false, extra: ["-debug.tab", "activity"])
        XCTAssertTrue(app.buttons["filter.all"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["activity.personPicker"].exists)
        XCTAssertTrue(app.buttons["filter.blocked"].label.contains("Blocked"))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(rows.count, 1)
    }
}
