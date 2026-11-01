import UIKit
import XCTest

/// Fase 26 (PR-03): an invite link copied on the invite page before installing, pasted with the Paste
/// card. The runner writes the simulator pasteboard and taps the real system Paste button (K6 a, spike S2:
/// no "Allow Paste" prompt). The pasteboard is emptied after each test so other suites never see the card.
/// Mock codes: `999999` code_expired, any other 6 digits join "Adhella" (PairingUITests).
final class InvitePasteUITests: XCTestCase {
    private static let link = "https://shoo-api.afindo-mi01.workers.dev/j/482193"

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        UIPasteboard.general.items = []
    }

    @MainActor
    private func newInstall(pasteboard: String) -> XCUIApplication {
        UIPasteboard.general.string = pasteboard
        return XCUIApplication.mock([
            "-settings.language", "en",
            "-UITestExtensionActive", "YES",
            "-UITestNotifications", "denied",
        ])
    }

    /// U1 → U3: one tap on the splash, the name, then Connect has the code; one tap joins.
    @MainActor
    func testPastedInviteOnNewInstallFillsConnect() {
        let app = newInstall(pasteboard: Self.link)
        XCTAssertTrue(app.descendants(matching: .any)["invite.paste.card"].firstMatch.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        let name = app.textFields["name.field"]
        app.tap(app.buttons["invite.paste.button"], until: name)
        name.tap()
        name.typeText("Mom")
        app.buttons["name.continue"].tapWhenHittable()
        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertFalse(app.buttons["mode.protected"].exists)
        XCTAssertEqual(field.value as? String, "482193")
        // Six digits in: the Connect paste row is gone.
        XCTAssertFalse(app.buttons["invite.paste.button"].exists)
        app.buttons["connect.join"].tapWhenHittable()
        XCTAssertTrue(app.staticTexts["protectedBy.title"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
    }

    /// U0: no web address on the pasteboard, no card (detection knows only the kind, never the text).
    @MainActor
    func testNoCardWithoutURL() {
        let app = newInstall(pasteboard: "halo")
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["invite.paste.card"].firstMatch.waitForExistence(timeout: UITestTimeout.optional))
    }

    /// U4: someone else's link is refused on the splash, nothing moves on.
    @MainActor
    func testForeignLinkShowsError() {
        let app = newInstall(pasteboard: "https://evil.example/j/482193")
        let paste = app.buttons["invite.paste.button"]
        paste.tapWhenHittable()
        // The label's icon carries the id too: the text is the static text.
        let error = app.staticTexts["invite.paste.error"]
        XCTAssertTrue(error.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertTrue(error.label.contains("isn't a Shoo invite link"), error.label)
        XCTAssertTrue(app.buttons["splash.skip"].exists)
        XCTAssertFalse(app.textFields["name.field"].exists)
    }

    /// U5: a pasted code the server says expired reads "invite expired", not "check the 6 digits".
    @MainActor
    func testExpiredPastedInvite() {
        let app = newInstall(pasteboard: "https://shoo-api.afindo-mi01.workers.dev/j/999999")
        let name = app.textFields["name.field"]
        app.tap(app.buttons["invite.paste.button"], until: name)
        name.tap()
        name.typeText("Mom")
        app.buttons["name.continue"].tapWhenHittable()
        app.buttons["connect.join"].tapWhenHittable()
        let error = app.staticTexts["connect.error"]
        XCTAssertTrue(error.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertTrue(error.label.contains("This invite has expired"), error.label)
    }

    /// U2 + T11: Connect from Profile "Have an invite code?" (K9); paste fills the code, nothing joins before the tap.
    @MainActor
    func testConnectSheetPaste() {
        UIPasteboard.general.string = Self.link
        let app = XCUIApplication.mock([
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", "guardian",
            "-settings.language", "en",
            "-UITestExtensionActive", "YES",
            "-UITestNotifications", "granted",
            "-mock.scenario", "empty",
        ])
        app.tap(app.buttons["profileButton"], until: app.buttons["profile.manage"])
        let mode = app.buttons["profile.mode"]
        for _ in 0..<6 where !mode.exists || !mode.isHittable { app.swipeUp() }
        let join = app.buttons["mode.joinFamily"]
        app.tap(mode, until: join)
        for _ in 0..<6 where !join.isHittable { app.swipeUp() }
        let field = app.textFields["connect.code"]
        app.tap(join, until: field)
        app.buttons["invite.paste.button"].tapWhenHittable()
        let filled = NSPredicate(format: "value == %@", "482193")
        wait(for: [expectation(for: filled, evaluatedWith: field)], timeout: UITestTimeout.screen)
        XCTAssertFalse(app.staticTexts["protectedBy.title"].exists)
        XCTAssertTrue(app.buttons["connect.join"].isEnabled)
    }
}
