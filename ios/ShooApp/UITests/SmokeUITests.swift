import XCTest

/// Fase 01: tabs + profile button exist and the in-app language reaches the tab bar.
final class SmokeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(language: String, mode: String = "guardian") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMock", "YES",
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", mode,
            "-settings.language", language,
        ]
        app.launch()
        return app
    }

    @MainActor
    func testTabsAndProfileInEnglish() {
        let app = launch(language: "en")
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Activity"].exists)
        XCTAssertTrue(app.buttons["profileButton"].exists)
    }

    @MainActor
    func testTabsInIndonesian() {
        let app = launch(language: "id", mode: "protected")
        XCTAssertTrue(app.tabBars.buttons["Perisai"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Aktivitas"].tap()
        XCTAssertTrue(app.navigationBars["Aktivitas"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLanguageSwitchesLiveFromProfile() {
        let app = launch(language: "en")
        app.buttons["profileButton"].tap()
        let picker = app.descendants(matching: .any)["languagePicker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), app.debugDescription)
        picker.tap()
        let option = app.buttons["Bahasa Indonesia"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), app.debugDescription)
        option.tap()
        XCTAssertTrue(app.navigationBars["Profil"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Selesai"].tap()
        XCTAssertTrue(app.tabBars.buttons["Aktivitas"].waitForExistence(timeout: 5))
    }
}
