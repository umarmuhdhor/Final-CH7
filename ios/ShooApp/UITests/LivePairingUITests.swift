import XCTest

/// Fase 14 step 4: two simulators pair through a local backend (`pnpm -C backend/api dev`).
/// The Guardian run (on `GUARD_UDID`) and the Protected run (on `PROT_UDID`) go at the same time and
/// talk through files in `SHOO_PAIR_DIR`: the Guardian writes the code on screen to `code.txt`;
/// the Protected run joins once by typing it, once by a link the host opens with
/// `xcrun simctl openurl $PROT_UDID shoo://join?code=…` after it sees `link-ready`.
/// Skipped unless the runner gets `SHOO_LIVE_BACKEND=1` and `SHOO_PAIR_DIR`.
final class LivePairingUITests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var pairDir: URL { URL(fileURLWithPath: environment["SHOO_PAIR_DIR"] ?? "/nonexistent") }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(environment["SHOO_LIVE_BACKEND"] == "1", "needs wrangler dev on localhost:8787")
        try XCTSkipUnless(environment["SHOO_PAIR_DIR"] != nil, "needs SHOO_PAIR_DIR shared by both runs")
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-settings.dataConsent", "granted",
            "-UITestReset", "YES",
            "-UITestSkipSplash", "YES",
            "-settings.language", "en",
            "-UITestNotifications", "denied",
            "-UITestExtensionActive", "YES",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let directory = environment["SHOO_SHOT_DIR"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }

    /// ON (Figma 1205:4696): onboarding always ends as Pribadi; ticking the consent box is the real POST /devices.
    @MainActor
    private func registerPersonal(_ app: XCUIApplication, name: String) {
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 10))
        app.onboardPersonal(name)
        XCTAssertTrue(app.buttons["profileButton"].waitForExistence(timeout: 15), app.debugDescription)
        // GD-01: notifications are not allowed on this simulator, so Home opens with the reminder popup.
        app.dismissNotificationsReminder()
    }

    private func read(_ name: String) -> String? {
        (try? String(contentsOf: pairDir.appendingPathComponent(name), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func write(_ name: String, _ text: String) {
        try? text.write(to: pairDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func waitFor(_ name: String, timeout: TimeInterval) -> String? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let text = read(name), !text.isEmpty { return text }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    /// Guardian: shows the family code until both Protected joins are done, then checks 2/3.
    @MainActor
    func testGuardianShowsTheFamilyCode() {
        let app = launch()
        registerPersonal(app, name: "Rina")
        // GD-02: Family mode on (with the "To be guardian" intro) makes the Guardian.
        app.becomeGuardian()
        app.buttons["profileButton"].tap()
        let open = app.buttons["profile.invite"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
        open.tap()
        let code = app.descendants(matching: .any)["invite.code"].firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 15), app.debugDescription)
        shot(app, "pair-guardian-1-code")

        var written = ""
        let end = Date().addingTimeInterval(240)
        while Date() < end, read("done") == nil {
            if code.exists {
                let digits = code.label.filter(\.isNumber)
                if digits.count == 6, digits != written {
                    write("code.txt", digits)
                    written = digits
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertNotNil(read("done"), "Protected run never finished")
        // The invite sheet has no member list (FamilyCodeView is gone). Members show on the Family Shield
        // (GD-03); Family mode is already on.
        let done = app.buttons["invite.done"].exists ? app.buttons["invite.done"] : app.buttons["invite.close"]
        done.tap()
        app.buttons["profile.back"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Mom"].firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Dad"].firstMatch.exists, app.debugDescription)
        shot(app, "pair-guardian-2-two-connected")
    }

    /// Protected: joins by typing the code, then (fresh install) by an invite link.
    @MainActor
    func testProtectedJoinsByCodeThenByLink() throws {
        var app = launch()
        registerPersonal(app, name: "Mom")
        // Terawasi from Home: the "Mode Terawasi" card opens Connect (Figma 1205:4696).
        app.openSupervisedConnect()
        let field = app.textFields["connect.code"]
        let typed = try XCTUnwrap(waitFor("code.txt", timeout: 120), "Guardian never showed a code")
        field.tap()
        field.typeText(typed)
        app.buttons["connect.join"].tap()
        let title = app.staticTexts["protectedBy.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(title.label.contains("Rina"), title.label)
        shot(app, "pair-protected-1-joined-by-code")
        app.buttons["protectedBy.continue"].tap()
        app.terminate()

        app = launch()
        // An invite link before onboarding: after the name, onboarding goes to Connect (Figma 1205:4696).
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 10))
        write("link-ready", "1")
        // The host opens shoo://join?code=… now; iOS asks "Open in “Shoo”?" first.
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        // The prompt shows only the first time on a simulator; iOS remembers the answer after that.
        if open.waitForExistence(timeout: 20) { open.tap() }
        app.onboardName("Dad")
        let linkField = app.textFields["connect.code"]
        XCTAssertTrue(linkField.waitForExistence(timeout: 10), app.debugDescription)
        // T11: the code is filled, nothing joins on its own.
        let filled = NSPredicate(format: "value MATCHES '[0-9]{6}'")
        wait(for: [expectation(for: filled, evaluatedWith: linkField)], timeout: 60)
        shot(app, "pair-protected-2-link-filled")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(app.staticTexts["protectedBy.title"].exists, "A link must never join without a tap")
        app.buttons["connect.join"].tap()
        let linkTitle = app.staticTexts["protectedBy.title"]
        XCTAssertTrue(linkTitle.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(linkTitle.label.contains("Rina"), linkTitle.label)
        shot(app, "pair-protected-3-joined-by-link")
        write("done", "1")
    }
}
