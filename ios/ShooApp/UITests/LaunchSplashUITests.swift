import XCTest

/// ON-01: the brand splash on every cold launch, then the screen the app was routed to; never on a return
/// from the background. `-UITestSplashSeconds 8` holds it long enough to see after `launch()` (which waits for the
/// app to idle) returns, even on a busy runner.
/// A push tap that starts the app takes the same path as the link here (`Router.openDetail`); the real
/// push from a terminated app is `LivePushUITests` (`.terminated`).
final class LaunchSplashUITests: XCTestCase {
    private static let blocked = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"
    private static let hold = ["-UITestSplashSeconds", "8"]

    override func setUp() {
        continueAfterFailure = false
    }

    private static let guardian = [
        "-settings.onboardingCompleted", "YES",
        "-settings.onboardingConnectPassed", "YES",
        "-settings.mode", "guardian",
        "-settings.language", "en",
        "-settings.familyModeOn", "YES",
        "-UITestExtensionActive", "YES",
        "-UITestNotifications", "granted",
    ]

    @MainActor
    private func logo(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["splash.logo"]
    }

    @MainActor
    func testColdLaunchShowsTheSplashThenHome() {
        let app = XCUIApplication.mock(Self.guardian + Self.hold, splash: true)
        XCTAssertTrue(logo(app).waitForExistence(timeout: UITestTimeout.optional), app.debugDescription)
        // Home is already built under the splash, but taps wait for it to go.
        let profile = app.buttons["profileButton"]
        XCTAssertTrue(profile.exists, app.debugDescription)
        XCTAssertFalse(profile.isHittable, app.debugDescription)
        // GD-01's "Notifications are off" popup waits for the splash too. (The splash is modal for VoiceOver,
        // so XCUITest lists it as an alert as well: look for the popup's button.)
        let notNow = app.alerts.buttons["Not now"].firstMatch
        XCTAssertFalse(notNow.exists, app.debugDescription)
        XCTAssertTrue(logo(app).waitForNonExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertTrue(notNow.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        app.dismissNotificationsReminder()
        // Then Home takes taps.
        app.tap(profile, until: app.buttons["profile.back"].firstMatch)
    }

    @MainActor
    func testReturnFromTheBackgroundSkipsTheSplash() {
        let app = XCUIApplication.mock(Self.guardian + Self.hold, splash: true)
        XCTAssertTrue(logo(app).waitForNonExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackgroundSuspended, timeout: UITestTimeout.screen) || app.state == .runningBackground)
        app.activate()
        // With the 8 s hold a splash shown again would still be up here.
        XCTAssertTrue(app.buttons["profileButton"].waitForExistence(timeout: UITestTimeout.optional), app.debugDescription)
        XCTAssertFalse(logo(app).exists, app.debugDescription)
    }

    @MainActor
    func testLinkThatStartsTheAppShowsTheSplashThenDetail() {
        // `open(_:)` starts the app again with the same launch arguments, so the first launch has the splash too.
        let app = XCUIApplication.mock(Self.guardian + Self.hold, splash: true)
        XCTAssertTrue(logo(app).waitForNonExistence(timeout: UITestTimeout.screen), app.debugDescription)
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: UITestTimeout.screen))
        app.open(URL(string: "shoo://scan/\(Self.blocked)")!)
        // `open(_:)` returns once the app idles; iOS may first ask "Open in “Shoo”?".
        if !logo(app).waitForExistence(timeout: 1) {
            let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
            if open.waitForExistence(timeout: UITestTimeout.optional) { open.tap() }
            XCTAssertTrue(logo(app).waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        }
        // The route waits under the splash and is still there when it goes.
        let header = app.descendants(matching: .any)["detail.header"]
        XCTAssertTrue(header.waitForExistence(timeout: UITestTimeout.screen * 2), app.debugDescription)
        XCTAssertTrue(logo(app).waitForNonExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertTrue(app.buttons["detail.verdict.safe"].isHittable, app.debugDescription)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.tabBars.buttons["Activity"].waitForExistence(timeout: UITestTimeout.screen))
        XCTAssertTrue(app.tabBars.buttons["Activity"].isSelected)
    }
}
