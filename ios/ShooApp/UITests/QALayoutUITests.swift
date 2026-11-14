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

    /// U-02 (fase 28e, K7): "Couldn't save" under Aman / Bahaya on the pending card ends above the tab bar.
    /// iPhone 17, ID, default size. Red on main: the notice ran from y 817.3 to 881.3, the tab bar starts at y 791.
    @MainActor
    func testVerdictFailedNoticeIsAboveTabBarOnIPhone17() throws {
        try assertVerdictFailedNoticeIsAboveTabBar(windowWidth: 402, language: "id")
    }

    /// U-02 guard: iPhone SE, EN, default size. Green on main and stays green (the notice ends at y 312.5 < tab bar y 584).
    @MainActor
    func testVerdictFailedNoticeIsAboveTabBarOnSE() throws {
        try assertVerdictFailedNoticeIsAboveTabBar(windowWidth: 375, language: "en")
    }

    @MainActor
    private func assertVerdictFailedNoticeIsAboveTabBar(windowWidth: CGFloat, language: String) throws {
        let app = launch([
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", "guardian",
            "-settings.familyModeOn", "YES",
            "-mock.scenario", "figma",
            "-mock.fail", "setVerdict",
            "-UITestNotifications", "denied",
            "-UITestExtensionActive", "YES",
        ], textSize: "UICTContentSizeCategoryL", language: language)
        try XCTSkipUnless(app.windows.firstMatch.frame.width == windowWidth, "only meaningful at \(windowWidth) pt wide")
        let danger = app.buttons["home.verdict.notSafe"]
        XCTAssertTrue(danger.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        // GD-01: the "Notifications are off" popup covers Home; its button is "Nanti saja" in Bahasa Indonesia.
        let notNow = app.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Not now", "Nanti saja"])).firstMatch
        if notNow.waitForExistence(timeout: UITestTimeout.optional) { notNow.tap() }
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: UITestTimeout.screen), app.debugDescription)
        for _ in 0..<2 where !danger.isHittable { app.swipeUp(velocity: .slow) }
        danger.tapWhenHittable()
        let notice = app.descendants(matching: .any)["home.verdictError"]
        XCTAssertTrue(notice.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, app.debugDescription)
        // The page may still be scrolling to the notice: give it a moment before measuring.
        let above = NSPredicate { _, _ in notice.frame.maxY <= tabBar.frame.minY + 1 }
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: above, object: nil)], timeout: UITestTimeout.optional)
        XCTAssertLessThanOrEqual(notice.frame.maxY, tabBar.frame.minY + 1, "notice \(notice.frame) tab bar \(tabBar.frame)")
    }
}
