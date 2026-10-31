import XCTest

/// Figma parity QA, test 2b (plan/alief/qa/figma-parity-2026-10-31.md): a Guardian and a Protected iPhone pair
/// through the local stack built like prod (`wrangler dev` backend on :8787 + local Supabase, AI worker on :8788),
/// in Bahasa Indonesia, answering the real notification prompt so APNs sandbox pushes reach the simulator.
/// Run both at once, one per simulator, with the same `QA_PAIR_DIR`:
///
///   TEST_RUNNER_QA_LIVE=1 TEST_RUNNER_QA_PAIR_DIR=<dir> xcodebuild test … -destination id=<guardian>
///       -only-testing:ShooAppUITests/LiveQAUITests/testGuardianPairs
///   TEST_RUNNER_QA_LIVE=1 TEST_RUNNER_QA_PAIR_DIR=<dir> xcodebuild test … -destination id=<protected>
///       -only-testing:ShooAppUITests/LiveQAUITests/testProtectedJoins
///
/// The app stays onboarded afterwards; the host then opens the corpus URLs in the Protected Safari.
final class LiveQAUITests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var pairDir: URL { URL(fileURLWithPath: environment["QA_PAIR_DIR"] ?? "/nonexistent") }
    static let aiBaseURL = "http://localhost:8788"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(environment["QA_LIVE"] == "1", "needs the local stack (wrangler dev :8787 + :8788)")
        try XCTSkipUnless(environment["QA_PAIR_DIR"] != nil, "needs QA_PAIR_DIR shared by both runs")
    }

    @MainActor
    func testGuardianPairs() {
        // The Guardian simulator never browses here, so its Safari extension counts as on; the Protected one is real.
        let app = launch(extensionActive: true)
        register(app, name: "Adhella", mode: "guardian")
        finishOnboarding(app)
        app.buttons["profileButton"].tap()
        let open = app.buttons["profile.invite"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
        open.tap()
        let code = app.descendants(matching: .any)["invite.code"].firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 15), app.debugDescription)
        let end = Date().addingTimeInterval(240)
        var written = ""
        while Date() < end, read("done") == nil {
            let digits = code.exists ? code.label.filter(\.isNumber) : ""
            if digits.count == 6, digits != written {
                write("code.txt", digits)
                written = digits
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertNotNil(read("done"), "Protected run never finished")
    }

    @MainActor
    func testProtectedJoins() throws {
        let app = launch()
        register(app, name: "Maria", mode: "protected")
        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        let code = try XCTUnwrap(waitFor("code.txt", timeout: 180), "Guardian never showed a code")
        field.tap()
        field.typeText(code)
        app.buttons["connect.join"].tap()
        XCTAssertTrue(app.staticTexts["protectedBy.title"].waitForExistence(timeout: 15), app.debugDescription)
        finishOnboarding(app)
        write("done", "1")
    }

    // MARK: Helpers

    @MainActor
    private func launch(extensionActive: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestReset", "YES", "-settings.language", "id", "-debug.aiBaseURL", Self.aiBaseURL]
        if extensionActive { app.launchArguments += ["-UITestExtensionActive", "YES"] }
        app.launch()
        return app
    }

    @MainActor
    private func register(_ app: XCUIApplication, name: String, mode: String) {
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["splash.skip"].tap()
        let field = app.textFields["name.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["name.continue"].tap()
        app.buttons["mode.\(mode)"].tap()
        app.buttons["mode.continue"].tap()
        XCTAssertTrue(app.buttons["greeting.continue"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["greeting.continue"].tap()
    }

    /// Taps through the remaining onboarding steps, whichever come, and allows notifications for real.
    @MainActor
    private func finishOnboarding(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let steps = [
            "invite.skip", "protectedBy.continue", "extension.skipCheck", "extensionOn.continue", "notifications.allow",
            "reminder.notNow",
        ]
        let end = Date().addingTimeInterval(90)
        while Date() < end, !app.buttons["profileButton"].exists {
            for label in ["Allow", "Izinkan"] where springboard.alerts.buttons[label].exists {
                springboard.alerts.buttons[label].tap()
            }
            for id in steps where app.buttons[id].exists && app.buttons[id].isHittable {
                app.buttons[id].tap()
                break
            }
            Thread.sleep(forTimeInterval: 0.7)
        }
        XCTAssertTrue(app.buttons["profileButton"].waitForExistence(timeout: 10), app.debugDescription)
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
}
