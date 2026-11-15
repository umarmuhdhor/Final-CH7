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

    /// U-03 + U-04 (fase 28n, GD-01 / PR-04): at AX3 the Home rows keep the page inside the screen and the site
    /// name breaks only at its hyphen. Protected Home, scenario `edge`, ID. Red on main 9e5403ba (28n): on SE the
    /// "Penipuan terverifikasi" chip could not shrink, so the page ran from x -29 to 404.5; on iPhone 17
    /// `home.seeAll` ended at x 405.7; `bca-verifikasi.site` beside "Waspada" took 3 lines (h 144) on both.
    @MainActor
    func testHomeRowsFitTheScreenAtAX3() throws {
        try XCTSkipUnless([375, 402].contains(UIScreen.main.bounds.width), "measured on iPhone SE and iPhone 17 only")
        try assertHomeRowsFitTheScreen(textSize: "UICTContentSizeCategoryAccessibilityXL", language: "id", lineHeight: 48, maxLines: 2)
    }

    /// U-03 + U-04 guard at the default size: iPhone 17 ID (A) and SE EN (E), green on main (28n): every row
    /// x 24 to 378 / 351, `home.seeAll` ends x 390 / 363, `bca-verifikasi.site` on one line (h 22).
    @MainActor
    func testHomeRowsFitTheScreenAtDefaultSize() throws {
        let width = UIScreen.main.bounds.width
        try XCTSkipUnless([375, 402].contains(width), "measured on iPhone SE and iPhone 17 only")
        try assertHomeRowsFitTheScreen(textSize: "UICTContentSizeCategoryL", language: width == 375 ? "en" : "id", lineHeight: 22, maxLines: 1)
    }

    /// `lineHeight`: one line of the row's site name at `textSize` (28n trees: 22 pt default, 48 pt at AX3).
    /// `maxLines`: one at the default size; two ("bca-" / "verifikasi.site") at AX3.
    @MainActor
    private func assertHomeRowsFitTheScreen(textSize: String, language: String, lineHeight: CGFloat, maxLines: CGFloat) throws {
        let app = launch([
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", "protected",
            "-mock.scenario", "edge",
            "-UITestExtensionActive", "YES",
        ], textSize: textSize, language: language)
        let row = app.buttons["home.recent.maria-2"]
        XCTAssertTrue(row.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        let width = app.windows.firstMatch.frame.width
        // Both checks below only measure: report each one.
        continueAfterFailure = true
        // U-03: no control or text runs past either side of the screen.
        var outside: [String] = []
        func walk(_ element: XCUIElementSnapshot) {
            let frame = element.frame
            if [.button, .staticText].contains(element.elementType), !frame.isEmpty, frame.minX < -0.5 || frame.maxX > width + 0.5 {
                outside.append("\(element.identifier) \"\(element.label)\" \(frame)")
            }
            element.children.forEach(walk)
        }
        walk(try app.snapshot())
        XCTAssertEqual(outside, [], "outside 0...\(width)")
        // U-04: never split inside a word: one line, or "bca-" / "verifikasi.site" at AX3.
        let site = row.staticTexts["bca-verifikasi.site"]
        XCTAssertTrue(site.exists, row.debugDescription)
        XCTAssertLessThanOrEqual(site.frame.height, maxLines * lineHeight + 1, "site name \(site.frame)")
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

    /// U-07 (fase 28n, DT-01): at AX3 the Detail title is whole above the Safe / Danger footer when the page opens.
    /// iPhone SE, ID, AX3. Red on main 9e5403ba (28n): "Situs Mencurigakan!" ran from y 329 to 441.5 and the
    /// question started at y 397 (44.5 pt covered). iPhone 17 at AX3 was fine (smallest gap 34 pt).
    @MainActor
    func testDetailTitleIsAboveTheFooterAtAX3OnSE() throws {
        try XCTSkipUnless(UIScreen.main.bounds.width == 375, "measured on iPhone SE only")
        assertDetailTitleIsAboveTheFooter(textSize: "UICTContentSizeCategoryAccessibilityXL", language: "id")
    }

    /// U-07 guard at the default size: iPhone 17 ID (A) and SE EN (E), green on main (28n): title y 316 to 349.7 /
    /// 349.5, question from y 748.3 / 541.
    @MainActor
    func testDetailTitleIsAboveTheFooterAtDefaultSize() throws {
        let width = UIScreen.main.bounds.width
        try XCTSkipUnless([375, 402].contains(width), "measured on iPhone SE and iPhone 17 only")
        assertDetailTitleIsAboveTheFooter(textSize: "UICTContentSizeCategoryL", language: width == 375 ? "en" : "id")
    }

    /// The guardian's Detail of a warning (Figma scenario, Bayu's `bca-verifikasi.site`), before any scroll.
    @MainActor
    private func assertDetailTitleIsAboveTheFooter(textSize: String, language: String) {
        let app = launch([
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", "guardian",
            "-settings.familyModeOn", "YES",
            "-mock.scenario", "figma",
            "-UITestNotifications", "granted",
            "-UITestExtensionActive", "YES",
            "-debug.detail", "figma-warning-72",
        ], textSize: textSize, language: language)
        let title = app.staticTexts["detail.title"]
        let question = app.staticTexts["detail.verdictQuestion"]
        XCTAssertTrue(question.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertTrue(title.exists, app.debugDescription)
        // The footer settles where it fits after the first layout pass: wait for that, never for a fixed time.
        let above = NSPredicate { _, _ in title.frame.maxY <= question.frame.minY }
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: above, object: nil)], timeout: UITestTimeout.optional)
        XCTAssertLessThanOrEqual(title.frame.maxY, question.frame.minY, "title \(title.frame) question \(question.frame)")
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
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: above, object: nil)], timeout: UITestTimeout.screen)
        XCTAssertLessThanOrEqual(notice.frame.maxY, tabBar.frame.minY + 1, "notice \(notice.frame) tab bar \(tabBar.frame)")
        // Not scrolled past either: still on screen.
        XCTAssertGreaterThanOrEqual(notice.frame.minY, 0, "notice \(notice.frame)")
    }
}
