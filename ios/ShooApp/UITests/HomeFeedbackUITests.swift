import XCTest

/// GD-02 Option A (plan/alief/proposal/pairing-feedback.md, Figma 2364:3633): every role or pairing change ends on
/// Home with a toast that says what changed. `ProfileUITests` covers Guardian from Account mode, joining another
/// family and disconnecting a member; these cover ⇆ with "Invite", Personal, and someone joining.
final class HomeFeedbackUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launch(familyMode: Bool, scenario: String = "standard") -> XCUIApplication {
        XCUIApplication.mock([
            "-settings.onboardingCompleted", "YES", "-settings.onboardingConnectPassed", "YES",
            "-settings.mode", "guardian", "-settings.language", "en", "-settings.guardianIntroSeen", "YES",
            "-settings.familyModeOn", familyMode ? "YES" : "NO", "-mock.scenario", scenario,
            "-UITestNotifications", "granted", "-UITestExtensionActive", "YES",
        ])
    }

    /// The toast's title and line, read as one element.
    @MainActor
    private func noticeText(_ app: XCUIApplication, timeout: TimeInterval = UITestTimeout.screen,
                            file: StaticString = #filePath, line: UInt = #line) -> String {
        let text = app.descendants(matching: .any)["home.notice.text"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: timeout), app.debugDescription, file: file, line: line)
        return text.label
    }

    /// ⇆ to Guardian: "Guardian mode on", and its "Invite" opens the share sheet (no invite sheet of our own).
    @MainActor
    func testSwitchToGuardianSaysSoAndInviteShares() {
        let app = launch(familyMode: false, scenario: "empty")
        let toggle = app.descendants(matching: .any)["familyModeToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        toggle.tap()
        XCTAssertTrue(noticeText(app).contains("Guardian mode on"))
        let invite = app.buttons["home.notice.invite"]
        XCTAssertTrue(invite.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        invite.tap()
        XCTAssertFalse(app.descendants(matching: .any)["home.notice"].exists, "Invite closes the toast")
        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["invite.code"].exists)
    }

    /// Profile › Account mode › Personal: back on Home with "Personal mode on".
    @MainActor
    func testModePageToPersonalEndsOnHome() {
        let app = launch(familyMode: true)
        app.buttons["profileButton"].tapWhenHittable()
        let mode = app.buttons["profile.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        for _ in 0..<6 where !mode.isHittable { app.swipeUp() }
        mode.tap()
        let personal = app.buttons["mode.personal"]
        XCTAssertTrue(personal.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        personal.tap()
        app.buttons["mode.switch"].tapWhenHittable()
        XCTAssertTrue(noticeText(app).contains("Personal mode on"))
        XCTAssertTrue(app.descendants(matching: .any)["home.status.active"].exists, app.debugDescription)
    }

    /// Someone joins while Home shows the invite code: "Grandma is connected", and her cell is marked new.
    @MainActor
    func testMemberJoiningEndsOnHomeAndMarksThem() {
        let app = launch(familyMode: true, scenario: "joinsLater")
        XCTAssertTrue(app.buttons["family.invite"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        // Grandma joins 8 s after launch; the invite card asks for members every 5 s.
        XCTAssertTrue(noticeText(app, timeout: 25).contains("Grandma is connected"))
        let grandma = app.descendants(matching: .any)["family.member.dev_grandma"].firstMatch
        XCTAssertTrue(grandma.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        // The cell reads as one button, so "Just connected" is part of its label.
        XCTAssertTrue(grandma.label.contains("Just connected"), grandma.label)
    }
}
