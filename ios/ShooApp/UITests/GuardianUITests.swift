import XCTest

/// Fase 05: Guardian Home (GD-01), Family mode pill (GD-02), family cards (GD-03), Family Activity (GD-05).
final class GuardianUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(familyMode: Bool?, extra: [String] = []) -> XCUIApplication {
        var arguments = [
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", "guardian",
            "-settings.language", "en",
            "-UITestExtensionActive", "YES",
        ] + extra
        if let familyMode {
            arguments += ["-settings.familyModeOn", familyMode ? "YES" : "NO"]
        }
        // `nil` = the relaunch that checks the saved Family mode: keep the settings.
        return XCUIApplication.mock(arguments, reset: familyMode != nil)
    }

    @MainActor
    func testFamilyModeIsRememberedAfterRelaunch() {
        var app = launch(familyMode: false)
        // Guardian Home (GD-01): hero status, no "Protected by" row.
        XCTAssertTrue(app.descendants(matching: .any)["home.status.active"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["shield.guardian"].exists)
        app.descendants(matching: .any)["familyModeToggle"].firstMatch.tap()
        // Family Home (Figma 435:20373): the fixture's sites are older than a day, so no card waits.
        XCTAssertTrue(app.descendants(matching: .any)["home.family.protected"].waitForExistence(timeout: 5), app.debugDescription)

        app.terminate()
        app = launch(familyMode: nil)
        XCTAssertTrue(app.descendants(matching: .any)["home.family.protected"].waitForExistence(timeout: 10), app.debugDescription)
        // Leave it off for the next run.
        app.descendants(matching: .any)["familyModeToggle"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.status.active"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPendingCardOpensDetailWithVerdictButtons() {
        // A member's site from today still waits for a verdict (Figma 435:20899).
        let app = launch(familyMode: true, extra: ["-mock.scenario", "mixedVerdicts"])
        let card = app.buttons["home.pending"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), app.debugDescription)
        app.dismissNotificationsReminder()
        XCTAssertTrue(app.buttons["home.verdict.notSafe"].exists)
        XCTAssertTrue(app.buttons["home.verdict.safe"].exists)
        app.tap(card, until: app.descendants(matching: .any)["detail.header"])
        // Guardian validates family items from Detail (GD-07, fase 03).
        XCTAssertTrue(app.buttons["detail.verdict.notSafe"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFamilyRowShowsWhoIsConnected() {
        // Every site decided: no card, so the people row shows (Figma 435:20373).
        let app = launch(familyMode: true, extra: ["-mock.scenario", "allSafe"])
        XCTAssertTrue(app.descendants(matching: .any)["home.family.protected"].waitForExistence(timeout: 10), app.debugDescription)
        app.dismissNotificationsReminder()
        let row = app.descendants(matching: .any)["family.header"]
        XCTAssertTrue(row.exists, app.debugDescription)
        let people = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'family.member.'"))
        XCTAssertGreaterThan(people.count, 0, app.debugDescription)
        XCTAssertTrue(people.firstMatch.label.contains("Active") || people.firstMatch.label.contains("Not connected"), people.firstMatch.label)
    }

    @MainActor
    func testEmptyFamilyOffersInvite() {
        let app = launch(familyMode: true, extra: ["-mock.scenario", "empty"])
        // GD-04 inline on Home (Figma 435:20630): code, QR, Share / Copy, how it works.
        XCTAssertTrue(app.staticTexts["familyCode.code"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["family.invite"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.family.empty"].exists)
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
    func testHomeOffersTurnOnWhenTheExtensionIsOff() {
        let app = XCUIApplication.mock([
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", "guardian",
            "-settings.language", "en",
            "-settings.familyModeOn", "NO",
            "-UITestExtensionStatus", "switchedOff",
        ])
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
