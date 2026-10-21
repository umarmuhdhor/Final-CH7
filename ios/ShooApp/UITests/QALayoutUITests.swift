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

    /// P2-4: an empty family shows Invite above the tab bar without scrolling (fails on iPhone SE before the fix).
    @MainActor
    func testInviteButtonIsAboveTabBar() {
        let app = launch([
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", "guardian",
            "-settings.familyModeOn", "YES",
            "-mock.scenario", "empty",
            "-UITestNotifications", "denied",
            "-UITestExtensionActive", "YES",
        ], textSize: "UICTContentSizeCategoryL")
        let invite = app.buttons["family.invite"]
        XCTAssertTrue(invite.waitForExistence(timeout: 10), app.debugDescription)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, app.debugDescription)
        XCTAssertLessThanOrEqual(invite.frame.maxY, tabBar.frame.minY + 1, "invite \(invite.frame) tab bar \(tabBar.frame)")
        XCTAssertTrue(invite.isHittable)
    }

    /// P2-4 / P2-7: at accessibility sizes Invite scrolls with the content, and the notification banner scrolls too
    /// (pinned, it left almost no room to scroll on an iPhone SE).
    @MainActor
    func testInviteButtonIsReachableAtAccessibilitySizes() {
        let app = launch([
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", "guardian",
            "-settings.familyModeOn", "YES",
            "-mock.scenario", "empty",
            "-UITestNotifications", "denied",
            "-UITestExtensionActive", "YES",
        ])
        let invite = app.buttons["family.invite"]
        XCTAssertTrue(invite.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<4 where !invite.isHittable || invite.frame.maxY > app.tabBars.firstMatch.frame.minY {
            app.swipeUp()
        }
        XCTAssertTrue(invite.isHittable, app.debugDescription)
        XCTAssertLessThanOrEqual(invite.frame.maxY, app.tabBars.firstMatch.frame.minY + 1)
    }
}
