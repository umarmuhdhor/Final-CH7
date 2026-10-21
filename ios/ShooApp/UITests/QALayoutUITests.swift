import XCTest

/// QA-A (fase 06Q): layout at accessibility text sizes, where the floating tab bar and pinned
/// footers can cover content (report `plan/alief/qa/QA-A-2026-10-22.md`).
final class QALayoutUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ arguments: [String], textSize: String = "UICTContentSizeCategoryAccessibilityXL") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", textSize, "-settings.language", "en"] + arguments
        app.launch()
        return app
    }

    /// P2-1: the slide text never scrolls under the page dots.
    @MainActor
    func testSplashDotsDoNotCoverText() {
        let app = launch(["-UITestReset", "YES"])
        let dots = app.pageIndicators.firstMatch
        XCTAssertTrue(dots.waitForExistence(timeout: 10), app.debugDescription)
        let slide = app.scrollViews["splash.slide.0"]
        XCTAssertTrue(slide.exists, app.debugDescription)
        XCTAssertFalse(slide.frame.intersects(dots.frame), "slide \(slide.frame) under dots \(dots.frame)")
    }
}
