import XCTest

/// Fase 13: the server no longer knows this iPhone → "Session expired" → onboarding from the start.
final class SessionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSessionExpiredStartsOnboardingOver() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMock", "YES",
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", "guardian",
            "-settings.language", "en",
            "-debug.sessionExpired", "YES",
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["Session expired"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["sessionExpired.restart"].tap()
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 5), app.debugDescription)
    }
}
