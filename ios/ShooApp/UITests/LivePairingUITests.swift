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
            "-UITestReset", "YES",
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
        XCTAssertTrue(app.staticTexts["Hi, \(name)!"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["greeting.continue"].tap()
        if mode == "guardian" {
            XCTAssertTrue(app.buttons["invite.skip"].waitForExistence(timeout: 5), app.debugDescription)
            app.buttons["invite.skip"].tap()
        }
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
        register(app, name: "Rina", mode: "guardian")
        if app.buttons["extensionOn.continue"].waitForExistence(timeout: 5) { app.buttons["extensionOn.continue"].tap() }
        // ON-05: a Guardian only has "Allow" (`-UITestNotifications denied` answers it).
        if app.buttons["notifications.allow"].waitForExistence(timeout: 5) { app.buttons["notifications.allow"].tap() }
        XCTAssertTrue(app.buttons["profileButton"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["profileButton"].tap()
        let open = app.buttons["profile.familyCode"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
        if !open.isHittable { app.swipeUp() }
        open.tap()
        let code = app.staticTexts["familyCode.code"]
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
        // Members are re-read every 5 s while the code is on screen.
        let members = app.descendants(matching: .any)["familyCode.members"].firstMatch
        let predicate = NSPredicate(format: "label CONTAINS '2 of 3'")
        let found = expectation(for: predicate, evaluatedWith: members)
        wait(for: [found], timeout: 15)
        XCTAssertTrue(app.staticTexts["Mom"].exists && app.staticTexts["Dad"].exists, app.debugDescription)
        shot(app, "pair-guardian-2-two-connected")
    }

    /// Protected: joins by typing the code, then (fresh install) by an invite link.
    @MainActor
    func testProtectedJoinsByCodeThenByLink() throws {
        var app = launch()
        register(app, name: "Mom", mode: "protected")
        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
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
        register(app, name: "Dad", mode: "protected")
        let linkField = app.textFields["connect.code"]
        XCTAssertTrue(linkField.waitForExistence(timeout: 5), app.debugDescription)
        write("link-ready", "1")
        // The host opens shoo://join?code=… now; iOS asks "Open in “Shoo”?" first.
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        XCTAssertTrue(open.waitForExistence(timeout: 60), "Host never opened the link")
        open.tap()
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
