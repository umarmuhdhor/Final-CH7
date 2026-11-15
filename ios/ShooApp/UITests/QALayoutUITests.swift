import XCTest

/// QA-A (fase 06Q): layout at accessibility text sizes, where the floating tab bar and pinned
/// footers can cover content (report `plan/alief/qa/QA-A-2026-10-22.md`).
final class QALayoutUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(
        _ arguments: [String], textSize: String = "UICTContentSizeCategoryAccessibilityXL", language: String = "en"
    ) -> XCUIApplication {
        XCUIApplication.mock(["-UIPreferredContentSizeCategoryName", textSize, "-settings.language", language] + arguments)
    }

    /// U-12 (fase 28n, GD-05): at AX3 each Activity filter word stays on one line. Family Activity, scenario
    /// `figma`, ID. Red on main 9e5403ba (28n): three equal segments, so on SE "Waspa / da" and "Bahay / a" were
    /// h 70.5 beside "Semua" h 35.5 (segments 105 pt wide), on iPhone 17 "Waspa / da" h 71 beside h 35.7 (114 pt).
    @MainActor
    func testActivityFiltersStayOnOneLineAtAX3() throws {
        try XCTSkipUnless([375, 402].contains(UIScreen.main.bounds.width), "measured on iPhone SE and iPhone 17 only")
        assertActivityFiltersStayOnOneLine(textSize: "UICTContentSizeCategoryAccessibilityXL", language: "id", lineHeight: 36)
    }

    /// U-12 guard at the default size: iPhone 17 ID (A) and SE EN (E), green on main (28n): `filter.all`,
    /// `filter.warning`, `filter.blocked` all h 28, side by side (114 / 105 pt each).
    @MainActor
    func testActivityFiltersStayOnOneLineAtDefaultSize() throws {
        let width = UIScreen.main.bounds.width
        try XCTSkipUnless([375, 402].contains(width), "measured on iPhone SE and iPhone 17 only")
        assertActivityFiltersStayOnOneLine(textSize: "UICTContentSizeCategoryL", language: width == 375 ? "en" : "id", lineHeight: 28)
    }

    /// `lineHeight`: one filter line at `textSize` (28n trees: 28 pt default, 35.5 to 35.7 pt at AX3). Each filter
    /// is a single word, so a label taller than 1.5 lines is a word split in the middle.
    @MainActor
    private func assertActivityFiltersStayOnOneLine(textSize: String, language: String, lineHeight: CGFloat) {
        let app = launch([
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", "guardian",
            "-settings.familyModeOn", "YES",
            "-mock.scenario", "figma",
            "-UITestNotifications", "granted",
            "-UITestExtensionActive", "YES",
            "-debug.tab", "activity",
        ], textSize: textSize, language: language)
        let screenWidth = app.windows.firstMatch.frame.width
        for id in ["all", "warning", "blocked"] {
            let filter = app.buttons["filter.\(id)"]
            XCTAssertTrue(filter.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
            let frame = filter.frame
            XCTAssertLessThan(frame.height, lineHeight * 1.5, "\(filter.label) wraps: \(frame)")
            XCTAssertTrue(frame.minX >= 0 && frame.maxX <= screenWidth, "\(filter.label) leaves the screen: \(frame)")
        }
    }

    /// P2-1: at large text the slide text scrolls above Skip / Next instead of running under them.
    @MainActor
    func testSplashControlsStayReachableAtLargeText() {
        let app = launch([])
        let next = app.buttons["splash.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), app.debugDescription)
        let title = app.staticTexts["Browse calmer, feeling safe."]
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(next.isHittable)
        XCTAssertTrue(app.buttons["splash.skip"].isHittable)
        XCTAssertLessThanOrEqual(title.frame.maxY, next.frame.minY, "title \(title.frame) under controls \(next.frame)")
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
        // GD-01: with notifications denied the "Notifications are off" popup covers Home; close it before measuring.
        app.dismissNotificationsReminder(timeout: UITestTimeout.screen)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, app.debugDescription)
        XCTAssertLessThanOrEqual(invite.frame.maxY, tabBar.frame.minY + 1, "invite \(invite.frame) tab bar \(tabBar.frame)")
        XCTAssertTrue(invite.isHittable)
    }

    /// P2-4: at accessibility sizes Invite scrolls with the content. (P2-7's pinned notification banner is a popup now.)
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
        // GD-01: with notifications denied the "Notifications are off" popup covers Home; close it before measuring.
        app.dismissNotificationsReminder(timeout: UITestTimeout.screen)
        for _ in 0..<4 where !invite.isHittable || invite.frame.maxY > app.tabBars.firstMatch.frame.minY {
            app.swipeUp()
        }
        XCTAssertTrue(invite.isHittable, app.debugDescription)
        XCTAssertLessThanOrEqual(invite.frame.maxY, app.tabBars.firstMatch.frame.minY + 1)
    }
}
