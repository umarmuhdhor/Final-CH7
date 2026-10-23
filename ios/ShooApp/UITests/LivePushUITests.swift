import XCTest

/// Fase 15 step 4: GD-06 / GD-07 end to end against a local backend (`pnpm -C backend/api dev`).
/// A real Guardian allows notifications, then for each app state the host script
/// (`plan/alief/qa/push-e2e.sh`) posts a scan as a Protected device, checks `push_log` and sends the same
/// payload with `xcrun simctl push`; this run taps the banner, lands on Detail and taps It's safe; the host
/// reads `GET /verdicts` as the Protected device. The two sides talk through files in `SHOO_PUSH_DIR`.
/// Skipped unless the runner gets `SHOO_LIVE_BACKEND=1` and `SHOO_PUSH_DIR`.
final class LivePushUITests: XCTestCase {
    /// How Shoo is running when the push arrives.
    enum AppState: String, CaseIterable {
        case foreground
        case background
        case terminated
    }

    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var pushDir: URL { URL(fileURLWithPath: environment["SHOO_PUSH_DIR"] ?? "/nonexistent") }

    @MainActor
    private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(environment["SHOO_LIVE_BACKEND"] == "1", "needs wrangler dev on localhost:8787")
        try XCTSkipUnless(environment["SHOO_PUSH_DIR"] != nil, "needs SHOO_PUSH_DIR shared with the host script")
    }

    @MainActor
    private func shot(_ name: String) throws {
        guard let directory = environment["SHOO_SHOT_DIR"] else { return }
        try XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }

    private func read(_ name: String) -> String? {
        (try? String(contentsOf: pushDir.appendingPathComponent(name), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func write(_ name: String, _ text: String) throws {
        try text.write(to: pushDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// The host answers through files: polled, it can't post to this process.
    private func waitFor(_ name: String, timeout: TimeInterval) -> String? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let text = read(name), !text.isEmpty { return text }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    private static func millis() -> String { String(Int(Date().timeIntervalSince1970 * 1000)) }

    @MainActor
    func testPushTapOpensDetailInEveryAppState() throws {
        let app = XCUIApplication()
        // No `-UITestNotifications`: the real permission and the real APNs registration.
        app.launchArguments += ["-UITestReset", "YES", "-settings.language", "en", "-UITestExtensionActive", "YES"]
        app.launch()
        onboardAsGuardian(app)
        try pairWithTheHost(app)
        for state in AppState.allCases {
            try tapPushAndMarkSafe(app, in: state)
        }
    }

    @MainActor
    private func onboardAsGuardian(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 10))
        app.buttons["splash.skip"].tap()
        let field = app.textFields["name.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Rina")
        app.buttons["name.continue"].tap()
        app.buttons["mode.guardian"].tap()
        app.buttons["mode.continue"].tap()
        XCTAssertTrue(app.staticTexts["Hi, Rina!"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["greeting.continue"].tap()
        // ON-05, then the system alert.
        let allow = app.buttons["notifications.allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10), app.debugDescription)
        allow.tap()
        let systemAllow = springboard.alerts.buttons["Allow"]
        if systemAllow.waitForExistence(timeout: 5) { systemAllow.tap() }
        XCTAssertTrue(app.buttons["profileButton"].waitForExistence(timeout: 10), app.debugDescription)
    }

    /// Shows a family code; the host joins it with a Protected device made by curl.
    @MainActor
    private func pairWithTheHost(_ app: XCUIApplication) throws {
        app.buttons["profileButton"].tap()
        let open = app.buttons["profile.familyCode"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
        if !open.isHittable { app.swipeUp() }
        open.tap()
        let code = app.staticTexts["familyCode.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 15), app.debugDescription)
        try write("code.txt", code.label.filter(\.isNumber))
        XCTAssertNotNil(waitFor("joined", timeout: 60), "Host never joined")
        app.buttons["familyCode.done"].firstMatch.tap()
        app.buttons["profile.done"].tap()
    }

    @MainActor
    private func tapPushAndMarkSafe(_ app: XCUIApplication, in state: AppState) throws {
        let name = state.rawValue
        switch state {
        case .foreground:
            XCTAssertTrue(app.buttons["profileButton"].waitForExistence(timeout: 5))
        case .background:
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackgroundSuspended, timeout: 10) || app.state == .runningBackground)
        case .terminated:
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        }
        try write("ready-\(name)", Self.millis())
        let scanId = try XCTUnwrap(waitFor("pushed-\(name)", timeout: 60), "Host never pushed (\(name))")
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'hit a blocked site'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "No banner (\(name))\n\(springboard.debugDescription)")
        try shot("push-\(name)-1-banner")
        banner.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "App did not open (\(name))")
        XCTAssertTrue(app.descendants(matching: .any)["detail.header"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["Activity"].isSelected, name)
        try write("detail-\(name)", "\(Self.millis()) \(scanId)")
        try shot("push-\(name)-2-detail")
        let safe = app.buttons["detail.verdict.safe"]
        XCTAssertTrue(safe.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<4 where !safe.isHittable { app.swipeUp() }
        safe.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.verdictNote"].waitForExistence(timeout: 10), app.debugDescription)
        try write("safe-\(name)", Self.millis())
        try shot("push-\(name)-3-safe")
        XCTAssertNotNil(waitFor("checked-\(name)", timeout: 30), "Host never checked the verdict (\(name))")
        // Back to the Shield tab for the next state.
        app.tabBars.buttons["Shield"].tap()
    }
}
