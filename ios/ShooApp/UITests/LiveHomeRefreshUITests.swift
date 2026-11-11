import XCTest

/// QA 2026-11-11 #4: a scan push that arrives while Guardian Home is open reloads Home, without a
/// pull-to-refresh. Against a local backend (`pnpm -C backend/api dev`): the host script posts a scan as
/// a Protected device and sends the push with `xcrun simctl push`. The two sides talk through files in
/// `SHOO_PUSH_DIR`, like `LivePushUITests`. Skipped unless the runner gets `SHOO_LIVE_BACKEND=1` and
/// `SHOO_PUSH_DIR`.
final class LiveHomeRefreshUITests: XCTestCase {
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

    private func write(_ name: String, _ text: String) throws {
        try text.write(to: pushDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func waitFor(_ name: String, timeout: TimeInterval) -> String? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let text = try? String(contentsOf: pushDir.appendingPathComponent(name), encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    @MainActor
    func testForegroundPushReloadsGuardianHome() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestReset", "YES", "-settings.language", "id", "-UITestExtensionActive", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 10))
        app.onboardPersonal("Rina")
        let systemAllow = springboard.alerts.buttons.element(boundBy: 1)
        if springboard.alerts.firstMatch.waitForExistence(timeout: 5) { systemAllow.tap() }
        XCTAssertTrue(app.buttons["profileButton"].waitForExistence(timeout: 10), app.debugDescription)
        app.becomeGuardian()

        // The empty family's Home shows the code; the host joins it with a Protected device made by curl.
        let code = app.descendants(matching: .any)["familyCode.code"].firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 15), app.debugDescription)
        try write("code.txt", code.label.filter(\.isNumber))
        XCTAssertNotNil(waitFor("joined", timeout: 60), "Host never joined")

        // Home with nothing waiting: "Keluarga Terlindungi!" (pull once, so the new member is on it).
        let protected = app.descendants(matching: .any)["home.family.protected"].firstMatch
        for _ in 0..<3 where !protected.waitForExistence(timeout: 5) {
            app.swipeDown()
        }
        XCTAssertTrue(protected.waitForExistence(timeout: 15), app.debugDescription)
        try shot("home-1-before-push")

        try write("ready", "1")
        XCTAssertNotNil(waitFor("pushed", timeout: 60), "Host never pushed")
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Sari'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "No banner\n\(springboard.debugDescription)")
        try shot("home-2-banner")

        // No touch on the app: Home has to follow the push by itself.
        let pending = app.descendants(matching: .any)["home.family.pending"].firstMatch
        let reloaded = pending.waitForExistence(timeout: 10)
        try shot("home-3-10s-after-push")
        XCTAssertTrue(reloaded, "Home still says the family is protected 10 s after the push\n\(app.debugDescription)")
    }
}
