import XCTest

/// Fase 14: Connect (PR-01/02/03) and Family code (GD-04) against the mock.
/// Mock codes: `000000` code_invalid · `999999` code_expired · `888888` family_full; any other 6 digits join "Adhella".
final class PairingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(mode: String, onboarded: Bool = true, language: String = "en", extra: [String] = []) -> XCUIApplication {
        var arguments = [
            "-settings.language", language,
            "-UITestExtensionActive", "YES",
            "-UITestNotifications", "denied",
            "-settings.familyModeOn", "YES",
        ] + extra
        if onboarded {
            arguments += [
                "-settings.onboardingCompleted", "YES",
                "-settings.onboardingConnectPassed", "YES",
                "-settings.mode", mode,
            ]
        }
        return XCUIApplication.mock(arguments)
    }

    @MainActor
    private func enter(_ code: String, in app: XCUIApplication) {
        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        if let current = field.value as? String, !current.isEmpty, current != "6-digit code" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(code)
    }

    /// Connect puts the keyboard away, so the next `enter` brings it back and the button rides up with it.
    /// On a slow runner a tap can land mid-move; wait until the button stops.
    @MainActor
    private func tapWhenSettled(_ button: XCUIElement) {
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        var last = button.frame
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.15)
            let now = button.frame
            if now == last, button.isHittable { break }
            last = now
        }
        button.tap()
    }

    /// iOS asks "Open in “Shoo”?" for a custom scheme opened from outside the app.
    @MainActor
    private func openLink(_ link: String, in app: XCUIApplication) {
        app.open(URL(string: link)!)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
    }

    /// PR-03: a new install opened from an invite link onboards as Pribadi like everyone else (no Connect step,
    /// no consent screen first). Once onboarding is done the join sheet has the code; nothing joins until the tap.
    /// `empty`: the new Pribadi protects nobody, so the mock lets the join through.
    @MainActor
    func testInviteLinkOnNewInstallFillsTheJoinSheetAfterOnboarding() {
        let app = launch(mode: "guardian", onboarded: false, extra: ["-mock.scenario", "empty"])
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: UITestTimeout.screen))
        openLink("shoo://join?code=482193", in: app)
        app.onboardName("Mom")
        XCTAssertFalse(app.textFields["connect.code"].exists, "Connect inside onboarding")
        XCTAssertFalse(app.buttons["consent.allow"].exists, "Consent screen before ON-04")
        app.passTurnOnExtension()
        app.passSafariDefault()
        app.buttons["extensionOn.continue"].tapWhenHittable()

        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertEqual(field.value as? String, "482193")
        XCTAssertTrue(app.buttons["connect.skip"].exists, "Came from a link: Not now")
        XCTAssertFalse(app.staticTexts["protectedBy.title"].exists)
        // K17: told about the page copy before joining.
        let copyNote = app.descendants(matching: .any)["connect.copyNote"].firstMatch
        XCTAssertTrue(copyNote.exists, app.debugDescription)
        XCTAssertTrue(copyNote.label.contains("14 days"), copyNote.label)

        let join = app.buttons["connect.join"]
        enter("000000", in: app)
        tapWhenSettled(join)
        let error = app.staticTexts["connect.error"]
        XCTAssertTrue(error.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertTrue(error.label.contains("doesn't match"), error.label)

        enter("999999", in: app)
        XCTAssertFalse(error.exists, "Editing the code clears the error")
        tapWhenSettled(join)
        XCTAssertTrue(error.waitForExistence(timeout: UITestTimeout.screen))
        XCTAssertTrue(error.label.contains("expired"), error.label)

        enter("482193", in: app)
        tapWhenSettled(join)
        let title = app.staticTexts["protectedBy.title"]
        XCTAssertTrue(title.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertTrue(title.label.contains("Budi"), title.label)
    }

    /// PR-03: a real new install (`-debug.askDataConsent YES`) answers the online check question on ON-04, not on
    /// a screen before it, and still gets the join sheet with the code at the end.
    @MainActor
    func testInviteNewInstallAsksConsentOnTurnOn() {
        let app = XCUIApplication.mock([
            "-settings.language", "en", "-UITestNotifications", "denied", "-debug.askDataConsent", "YES",
            "-UITestExtensionActive", "YES", "-mock.scenario", "empty",
        ])
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: UITestTimeout.screen))
        openLink("shoo://join?code=482193", in: app)
        app.onboardName("Mom")
        XCTAssertTrue(app.buttons["extension.consent"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertFalse(app.buttons["consent.allow"].exists, app.debugDescription)
        app.passTurnOnExtension()
        app.passSafariDefault()
        app.buttons["extensionOn.continue"].tapWhenHittable()

        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertEqual(field.value as? String, "482193")
    }

    /// PR-03: an onboarded Pribadi gets a card on Home. Not now drops the invite; View opens the filled sheet.
    @MainActor
    func testInviteLinkOnPribadiShowsTheHomeNotice() {
        let app = launch(mode: "guardian", extra: ["-settings.familyModeOn", "NO", "-mock.scenario", "empty"])
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        app.dismissNotificationsReminder()

        openLink("shoo://join?code=482193", in: app)
        let notice = app.descendants(matching: .any)["invite.notice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertFalse(app.textFields["connect.code"].exists, "Nothing opens before View")
        app.buttons["invite.notice.later"].tapWhenHittable()
        XCTAssertTrue(notice.waitForNonExistence(timeout: UITestTimeout.screen), app.debugDescription)

        openLink("shoo://join?code=482193", in: app)
        XCTAssertTrue(notice.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        app.buttons["invite.notice.view"].tapWhenHittable()
        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertEqual(field.value as? String, "482193")
        XCTAssertFalse(app.staticTexts["protectedBy.title"].exists)
    }

    /// PR-03: a guardian who still protects someone can't join; the card says so and points to Profile.
    @MainActor
    func testInviteLinkOnGuardianWithMembersPointsToProfile() {
        let app = launch(mode: "guardian")
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        app.dismissNotificationsReminder()
        openLink("shoo://join?code=482193", in: app)
        let profile = app.buttons["invite.notice.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertFalse(app.textFields["connect.code"].exists)
        profile.tapWhenHittable()
        XCTAssertFalse(app.descendants(matching: .any)["invite.notice"].firstMatch.exists)
    }

    /// PR-03 (T11): a Protected that already has a guardian is told so; the invite is not used.
    @MainActor
    func testInviteLinkOnProtectedWithGuardianShowsTheNotice() {
        let app = launch(mode: "protected")
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        openLink("shoo://join?code=482193", in: app)
        let ok = app.buttons["invite.notice.ok"]
        XCTAssertTrue(ok.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertFalse(app.textFields["connect.code"].exists)
        XCTAssertTrue(app.staticTexts["You're already protected by Adhella"].exists, app.debugDescription)
        ok.tapWhenHittable()
        XCTAssertTrue(ok.waitForNonExistence(timeout: UITestTimeout.screen), app.debugDescription)
    }

    /// PR-03: a Protected without a guardian yet gets Connect with the code straight away.
    @MainActor
    func testInviteLinkOnUnpairedProtectedOpensConnect() {
        let app = launch(mode: "protected", extra: ["-mock.scenario", "unpaired"])
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        openLink("shoo://join?code=482193", in: app)
        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertEqual(field.value as? String, "482193")
        XCTAssertFalse(app.staticTexts["protectedBy.title"].exists)
    }

    /// QA 1110 #8, #16 (Bahasa, the longer copy): with the keyboard up the whole headline still shows. Connect
    /// puts the keyboard away, so a two-line error sits clear of the button and the 14-day note.
    @MainActor
    func testConnectErrorWithKeyboardUpOverlapsNothing() {
        // `unpaired`: a Protected with a guardian gets the Home card instead of Connect (PR-03).
        let app = launch(mode: "protected", language: "id", extra: ["-mock.scenario", "unpaired"])
        XCTAssertTrue(app.tabBars.buttons.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        openLink("shoo://join?code=777777", in: app)
        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // Let the scroll to the field finish.
        sleep(1)
        let back = app.buttons["onboarding.back"].firstMatch
        let title = app.staticTexts["Hubungkan Akun"]
        XCTAssertTrue(back.exists && title.exists, app.debugDescription)
        XCTAssertGreaterThanOrEqual(title.frame.minY, back.frame.minY, "Headline pushed under the top: \(title.frame) \(back.frame)")

        let join = app.buttons["connect.join"]
        tapWhenSettled(join)
        let error = app.staticTexts["connect.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(error.label.contains("Terlalu banyak percobaan"), error.label)
        // The 429 carried `Retry-After`: the button now counts down instead of "Hubungkan".
        let wait = app.buttons["connect.wait"]
        XCTAssertTrue(wait.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(wait.label.hasPrefix("Coba lagi dalam 04:"), wait.label)
        XCTAssertFalse(wait.isEnabled)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "Connect puts the keyboard away")
        sleep(1)
        XCTAssertGreaterThan(error.frame.height, 30, "Two lines in Bahasa: \(error.frame)")
        XCTAssertLessThanOrEqual(error.frame.maxY, wait.frame.minY, "Error under the button: \(error.frame) \(wait.frame)")
        let note = app.descendants(matching: .any)["connect.copyNote"].firstMatch
        XCTAssertTrue(note.exists, app.debugDescription)
        XCTAssertFalse(error.frame.intersects(note.frame), "Error on the 14-day note: \(error.frame) \(note.frame)")
        XCTAssertLessThanOrEqual(note.frame.maxY, wait.frame.minY, "Note under the button: \(note.frame) \(wait.frame)")
        XCTAssertGreaterThanOrEqual(title.frame.minY, back.frame.minY, "Headline cut after the error: \(title.frame)")
    }

    @MainActor
    func testScanTabExplainsWhenTheCameraCannotScan() {
        let app = launch(mode: "protected", extra: ["-mock.scenario", "unpaired"])
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 10))
        openLink("shoo://join?code=482193", in: app)
        XCTAssertTrue(app.textFields["connect.code"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["connect.tab.scan"].tap()
        // The simulator has no camera: a note and the Code tab stay, never a blank screen.
        XCTAssertTrue(app.descendants(matching: .any)["connect.scanner"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testFamilyCodeShowsQRCodeAndCountdown() {
        // Nobody connected yet: Family Home shows the code inline (Figma 435:20630, GD-03/04).
        let app = launch(mode: "guardian", extra: ["-mock.scenario", "empty"])
        let code = app.staticTexts["familyCode.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 10), app.debugDescription)
        app.dismissNotificationsReminder(timeout: UITestTimeout.screen)
        XCTAssertTrue(app.images["familyCode.qr"].exists)
        XCTAssertTrue(app.buttons["family.invite"].exists)
        let countdown = app.staticTexts["familyCode.countdown"]
        XCTAssertTrue(countdown.exists)
        let first = countdown.label
        let ticked = NSPredicate(format: "label != %@", first)
        wait(for: [expectation(for: ticked, evaluatedWith: countdown)], timeout: 5)
        app.buttons["familyCode.copy"].tap()
        XCTAssertTrue(app.buttons["familyCode.copy"].label.contains("Copied"), app.buttons["familyCode.copy"].label)
        XCTAssertTrue(app.descendants(matching: .any)["home.howItWorks"].exists)
    }

    @MainActor
    func testFullFamilyHasNoCodeButton() {
        let app = launch(mode: "guardian", extra: ["-mock.scenario", "threeMembers"])
        let profile = app.buttons["profileButton"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10), app.debugDescription)
        profile.tap()
        let invite = app.buttons["profile.invite"]
        XCTAssertTrue(invite.waitForExistence(timeout: 10), app.debugDescription)
        invite.tap()
        // Family full: the invite sheet hands out no code.
        let full = app.descendants(matching: .any)["invite.full"].firstMatch
        XCTAssertTrue(full.waitForExistence(timeout: 10), app.debugDescription)
        // Figma "Keluarga penuh": "Kelola Keluarga" closes the sheet onto Profile's family list.
        let manage = app.buttons["invite.manageFamily"]
        XCTAssertTrue(manage.exists, app.debugDescription)
        manage.tap()
        XCTAssertTrue(full.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["invite.code"].exists)
    }

    // Removing a member: Profile's member detail since PF-01 (ProfileUITests.testGuardianDisconnectsAMemberFromTheDetail).
}
