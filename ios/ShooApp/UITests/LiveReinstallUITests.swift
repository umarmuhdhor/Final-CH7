import XCTest

/// QA 2026-11-11 #6: a reinstalled Protected phone can join its full family again. Against a local backend
/// (`pnpm -C backend/api dev`). The host makes a Guardian with two members by curl (3 places, 2 taken) and
/// runs this test twice with `xcrun simctl uninstall` + `install` in between. The first run joins as the
/// third member; the second, on a fresh install, has to join again. Without the fix the old device still
/// holds the third place and the join fails with "family full". `SHOO_REINSTALL_CODE` is the Guardian's code,
/// `SHOO_REINSTALL_SHOT` names the screenshot. Skipped unless the runner gets `SHOO_LIVE_BACKEND=1`.
final class LiveReinstallUITests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(environment["SHOO_LIVE_BACKEND"] == "1", "needs wrangler dev on localhost:8787")
        try XCTSkipUnless(environment["SHOO_REINSTALL_CODE"] != nil, "needs the Guardian's code from the host")
    }

    @MainActor
    func testProtectedJoinsTheFamily() throws {
        let code = try XCTUnwrap(environment["SHOO_REINSTALL_CODE"])
        let app = XCUIApplication()
        app.launchArguments += [
            "-settings.dataConsent", "granted",
            "-settings.language", "en",
            "-UITestNotifications", "denied",
            "-UITestExtensionActive", "YES",
        ]
        app.launch()
        // Already set up (a second join after a failed one): straight to Connect.
        let splash = app.buttons["splash.skip"], home = app.buttons["profileButton"]
        let end = Date().addingTimeInterval(15)
        while Date() < end, !splash.exists, !home.exists { Thread.sleep(forTimeInterval: 0.5) }
        if home.exists {
            try joinAndCheck(app, code: code)
            return
        }
        XCTAssertTrue(splash.exists, app.debugDescription)
        // `onboardPersonal`, with Shoo brought back to the front once more before Safari Default: after a
        // reinstall Settings can stay in front a moment longer.
        app.onboardName("Bu Sari")
        app.passTurnOnExtension()
        let skip = app.buttons["extension.skipCheck"]
        if skip.waitForExistence(timeout: UITestTimeout.optional) { skip.tapWhenHittable() }
        if !app.buttons["safariDefault.open"].waitForExistence(timeout: 10) { app.activate() }
        app.passSafariDefault()
        app.buttons["extensionOn.continue"].tapWhenHittable()
        XCTAssertTrue(app.buttons["profileButton"].waitForExistence(timeout: 15), app.debugDescription)
        try joinAndCheck(app, code: code)
    }

    @MainActor
    private func joinAndCheck(_ app: XCUIApplication, code: String) throws {
        app.dismissNotificationsReminder()
        app.openSupervisedConnect()
        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        field.tap()
        field.typeText(code)
        app.buttons["connect.join"].tap()

        let joined = app.staticTexts["protectedBy.title"]
        let failed = app.descendants(matching: .any)["connect.error"]
        let end = Date().addingTimeInterval(20)
        while Date() < end, !joined.exists, !failed.exists { Thread.sleep(forTimeInterval: 0.5) }
        if let directory = environment["SHOO_SHOT_DIR"] {
            let name = environment["SHOO_REINSTALL_SHOT"] ?? "reinstall"
            try app.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
        XCTAssertTrue(joined.exists, "Join failed: \(failed.exists ? failed.label : "no answer")")
    }
}
