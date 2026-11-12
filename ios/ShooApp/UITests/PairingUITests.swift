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

    /// Connect inside onboarding only comes from an invite link (Figma "Flow" has no mode choice).
    @MainActor
    func testOnboardingConnectShowsErrorsThenWhoProtectsMe() {
        let app = launch(mode: "protected", onboarded: false)
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 10))
        openLink("shoo://join?code=482193", in: app)
        app.onboardName("Mom")

        let join = app.buttons["connect.join"]
        XCTAssertTrue(join.waitForExistence(timeout: 10), app.debugDescription)
        // K17: told about the page copy before joining.
        let copyNote = app.descendants(matching: .any)["connect.copyNote"].firstMatch
        XCTAssertTrue(copyNote.exists, app.debugDescription)
        XCTAssertTrue(copyNote.label.contains("14 days"), copyNote.label)
        enter("000000", in: app)
        tapWhenSettled(join)
        let error = app.staticTexts["connect.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(error.label.contains("doesn't match"), error.label)

        enter("999999", in: app)
        XCTAssertFalse(error.exists, "Editing the code clears the error")
        tapWhenSettled(join)
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("expired"), error.label)

        enter("482193", in: app)
        tapWhenSettled(join)
        let title = app.staticTexts["protectedBy.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(title.label.contains("Adhella"), title.label)
        app.buttons["protectedBy.continue"].tap()
        // Registered by the join, consent already given (mock) and Shoo on: Aktifkan Ekstensi passes by itself.
        app.passSafariDefault()
        XCTAssertTrue(app.buttons["extensionOn.continue"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["extensionOn.continue"].tap()
    }

    /// A new install opened from an invite link (WhatsApp): no mode choice, Connect has the code, one tap joins.
    @MainActor
    func testInviteLinkOnNewInstallSkipsModeChoice() {
        let app = launch(mode: "protected", onboarded: false)
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 10))
        openLink("shoo://join?code=482193", in: app)
        app.onboardName("Mom")
        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["mode.protected"].exists)
        XCTAssertEqual(field.value as? String, "482193")
        app.buttons["connect.join"].tap()
        XCTAssertTrue(app.staticTexts["protectedBy.title"].waitForExistence(timeout: 10), app.debugDescription)
    }

    /// Fase 27d (F-A1): a real new install (the mock answers nothing, `-debug.askDataConsent YES`) opened from
    /// an invite link answers the online check question before Connect registers the device, then goes on
    /// past ON-04: no checkbox there any more, and Turn on works.
    @MainActor
    func testInviteNewInstallAsksConsentFirstAndPassesTurnOn() {
        let app = XCUIApplication.mock([
            "-settings.language", "en", "-UITestNotifications", "denied", "-debug.askDataConsent", "YES",
            // Shoo on but no page seen yet: ON-04 waits for a tap instead of moving on by itself.
            "-UITestExtensionStatus", "unchecked",
        ])
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: UITestTimeout.screen))
        openLink("shoo://join?code=482193", in: app)
        app.onboardName("Mom")
        let allow = app.buttons["consent.allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertFalse(app.buttons["connect.join"].exists, "Connect before the answer")
        allow.tapWhenHittable()

        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertEqual(field.value as? String, "482193")
        app.buttons["connect.join"].tapWhenHittable()
        XCTAssertTrue(app.staticTexts["protectedBy.title"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        // Before the fix the consent screen replaced onboarding here.
        XCTAssertFalse(app.buttons["consent.allow"].exists, app.debugDescription)
        app.buttons["protectedBy.continue"].tapWhenHittable()

        // ON-04: answered already, so no checkbox and the button is on.
        let turnOn = app.buttons["extension.turnOn"]
        XCTAssertTrue(turnOn.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertFalse(app.buttons["extension.consent"].exists, app.debugDescription)
        XCTAssertTrue(turnOn.isEnabled)
        turnOn.tapWhenHittable()
        app.comeBackFromSettings()
        app.buttons["extension.skipCheck"].tapWhenHittable()
        XCTAssertTrue(app.buttons["safariDefault.open"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
    }

    /// Fase 27d (F-A2): a failed invite join keeps the registration for another try; Back deletes it again
    /// and reaches the name, and Next then continues as Pribadi.
    @MainActor
    func testFailedInviteJoinBackReachesTheName() {
        let app = XCUIApplication.mock([
            "-settings.language", "en", "-UITestNotifications", "denied", "-debug.askDataConsent", "YES",
            "-UITestExtensionStatus", "unchecked",
        ])
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: UITestTimeout.screen))
        openLink("shoo://join?code=999999", in: app)
        app.onboardName("Mom")
        app.buttons["consent.decline"].tapWhenHittable()
        let join = app.buttons["connect.join"]
        XCTAssertTrue(join.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        tapWhenSettled(join)
        let error = app.staticTexts["connect.error"]
        XCTAssertTrue(error.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertTrue(error.label.contains("expired"), error.label)

        app.tap(app.buttons["onboarding.back"].firstMatch, until: app.textFields["name.field"])
        app.buttons["name.continue"].tapWhenHittable()
        // The code went with the deleted device; the answer ("no") stays, so no checkbox either.
        let turnOn = app.buttons["extension.turnOn"]
        XCTAssertTrue(turnOn.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertFalse(app.buttons["extension.consent"].exists, app.debugDescription)
        XCTAssertTrue(turnOn.isEnabled)
    }

    /// T11: an invite link only fills the code; nothing joins until Connect is tapped.
    @MainActor
    func testInviteLinkOpensConnectWithTheCodeFilled() {
        let app = launch(mode: "protected")
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 10), app.debugDescription)
        openLink("shoo://join?code=482193", in: app)
        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(field.value as? String, "482193")
        XCTAssertFalse(app.staticTexts["protectedBy.title"].exists)
        // The mock Protected already has a guardian: the server answers already_connected.
        app.buttons["connect.join"].tap()
        let error = app.staticTexts["connect.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(error.label.contains("already connected"), error.label)
    }

    /// QA 1110 #8, #16 (Bahasa, the longer copy): with the keyboard up the whole headline still shows. Connect
    /// puts the keyboard away, so a two-line error sits clear of the button and the 14-day note.
    @MainActor
    func testConnectErrorWithKeyboardUpOverlapsNothing() {
        let app = launch(mode: "protected", language: "id")
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
        let app = launch(mode: "protected")
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
        let full = app.staticTexts["Your family is full (3 people). Remove someone to invite another person."]
        XCTAssertTrue(full.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["invite.code"].exists)
    }

    // Removing a member: Profile's member detail since PF-01 (ProfileUITests.testGuardianDisconnectsAMemberFromTheDetail).
}
