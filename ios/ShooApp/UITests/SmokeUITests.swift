import XCTest

/// Placeholder so the ShooAppUITests target builds and runs; real flows arrive with the feature phases.
final class SmokeUITests: XCTestCase {
    @MainActor
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
