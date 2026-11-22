import XCTest

/// ON-01 … ON-05 on a fresh install (Figma "Flow" 1205:4696). Launch arguments (DEBUG only) replace the parts
/// the simulator can't do: `-UITestExtensionActive YES` stands in for the Safari heartbeat, and
/// `-UITestNotifications granted|denied` answers the permission prompt without a system alert.
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    /// `askConsent`: the mock answers the data question itself; this keeps the consent box unticked like a new install.
    private func launch(extensionActive: Bool = true, extensionStatus: String? = nil, notifications: String = "denied",
                        askConsent: Bool = false, scenario: String? = nil) -> XCUIApplication {
        var arguments = ["-settings.language", "en", "-UITestNotifications", notifications]
        if let scenario { arguments += ["-mock.scenario", scenario] }
        if askConsent { arguments += ["-debug.askDataConsent", "YES"] }
        if extensionActive { arguments += ["-UITestExtensionActive", "YES"] }
        if let extensionStatus { arguments += ["-UITestExtensionStatus", extensionStatus] }
        return XCUIApplication.mock(arguments)
    }

    @MainActor
    func testARegisteredDeviceAnswersBeforeTheApp() {
        let app = XCUIApplication.mock([
            "-settings.language", "en", "-UITestReset", "YES", "-debug.askDataConsent", "YES",
            "-settings.mode", "guardian", "-settings.onboardingCompleted", "YES",
        ])
        XCTAssertTrue(app.buttons["consent.allow"].waitForExistence(timeout: 10))
        app.buttons["consent.allow"].tap()
        XCTAssertFalse(app.buttons["consent.allow"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testSplashHasTwoSlidesSkipAndBack() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Browse calmer, feeling safe."].waitForExistence(timeout: 10))
        // Figma: no demo link on the splash.
        XCTAssertFalse(app.buttons["splash.demo"].exists)
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Looks real, may not be safe.\nLet Shoo check."].waitForExistence(timeout: 5), app.debugDescription)
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["Browse calmer, feeling safe."].waitForExistence(timeout: 5))
        app.buttons["splash.next"].tap()
        XCTAssertTrue(app.staticTexts["Looks real, may not be safe.\nLet Shoo check."].waitForExistence(timeout: 5))
        app.buttons["splash.skip"].tap()
        XCTAssertTrue(app.textFields["name.field"].waitForExistence(timeout: 5))
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testNameShowsTheLimitAndRejectsTwentyOneCharacters() {
        let app = launch()
        app.buttons["splash.skip"].tap()
        let field = app.textFields["name.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // Figma "Atur Profilmu": the note is there before typing.
        XCTAssertTrue(app.staticTexts["*Your name can be up to 20 characters"].exists)
        field.tap()
        field.typeText(String(repeating: "a", count: 21))
        XCTAssertTrue(app.staticTexts["*Your name can be up to 20 characters"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["name.continue"].isEnabled)
    }

    @MainActor
    func testTurnOnWaitsForTheConsentBoxAndShowsWhatIsSent() {
        let app = launch(extensionActive: false, askConsent: true)
        app.onboardName("Rina")
        let turnOn = app.buttons["extension.turnOn"]
        XCTAssertTrue(turnOn.waitForExistence(timeout: 5), app.debugDescription)
        // No status note before the user has been to Settings (Figma has none).
        XCTAssertFalse(app.descendants(matching: .any)["extension.offHint"].exists)
        let hint = app.descendants(matching: .any)["extension.consentHint"]
        XCTAssertFalse(hint.exists)
        if #available(iOS 26.2, *) {
            XCTAssertTrue(app.staticTexts["Tick the box below, then tap Turn on the extension."].exists, app.debugDescription)
        }
        // Figma 110:4505: grey until ticked. A tap says to tick the box first and does not leave for Settings.
        turnOn.tap()
        XCTAssertTrue(hint.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.state, .runningForeground)
        app.buttons["extension.dataSent"].tap()
        XCTAssertTrue(app.staticTexts["Without the online check"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["dataSent.done"].tap()
        XCTAssertTrue(app.staticTexts["Without the online check"].waitForNonExistence(timeout: 5))
        // 29g peek sheet: a drag down closes it too.
        app.buttons["extension.dataSent"].tapWhenHittable()
        let title = app.staticTexts["What is sent"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 450)))
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), app.debugDescription)
        app.buttons["extension.consent"].tap()
        XCTAssertTrue(hint.waitForNonExistence(timeout: 5), app.debugDescription)
        // Nothing saved yet: Back still reaches the name.
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.textFields["name.field"].waitForExistence(timeout: 5))
    }

    /// Before/after pictures for the PR: the grey button, then the hint after a tap. Runs only with `SHOO_SHOT_DIR`.
    @MainActor
    func testConsentHintScreenshotForPR() throws {
        guard let dir = ProcessInfo.processInfo.environment["SHOO_SHOT_DIR"] else { throw XCTSkip("Set SHOO_SHOT_DIR") }
        let app = XCUIApplication.mock([
            "-settings.language", "id", "-UITestNotifications", "denied", "-debug.askDataConsent", "YES",
            "-debug.onboardingStep", "turnOnExtension",
        ])
        let turnOn = app.buttons["extension.turnOn"]
        XCTAssertTrue(turnOn.waitForExistence(timeout: 5), app.debugDescription)
        func save(_ name: String) throws {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        try save("on04-consent-grey.png")
        turnOn.tap()
        XCTAssertTrue(app.descendants(matching: .any)["extension.consentHint"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        try save("on04-consent-hint.png")
        app.buttons["extension.consent"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        try save("on04-consent-ticked.png")
    }

    @MainActor
    func testPersonalOnboardingEndsOnHomeWithReminderWhenNotificationsDenied() {
        // Personal onboarding ends on Home Pribadi with the notifications reminder.
        let app = launch(notifications: "denied", scenario: "empty")
        app.onboardName("Rina")
        // Figma "Flow": no mode choice and no invite step.
        XCTAssertFalse(app.buttons["mode.continue"].exists)
        app.passTurnOnExtension()
        app.passSafariDefault()
        // Next shows Shoo's dialog first (F6); Turn on asks, and the mock answers "denied".
        XCTAssertTrue(app.buttons["extensionOn.continue"].waitForExistence(timeout: 5))
        app.buttons["extensionOn.continue"].tap()
        let ask = app.descendants(matching: .any)["notificationAsk"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Turn on notifications?"].exists, app.debugDescription)
        app.buttons["notificationAsk.allow"].tap()
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 5))
        let reminder = app.buttons["reminder.notNow"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5), app.debugDescription)
        reminder.tap()
        XCTAssertTrue(reminder.waitForNonExistence(timeout: 2))
        // Pribadi Home that has never been Guardian: no ⇆, the "Jadi Penjaga" card instead (Figma 1382:10567).
        XCTAssertTrue(app.descendants(matching: .any)["home.guardianCard"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["familyModeToggle"].exists)
    }

    @MainActor
    func testNotNowOnTheNotificationDialogEndsOnboardingWithoutAsking() {
        // F6: "Nanti saja" ends onboarding and leaves the one-time iOS prompt for later.
        let app = launch(notifications: "denied", scenario: "empty")
        app.onboardName("Rina")
        app.passTurnOnExtension()
        app.passSafariDefault()
        app.buttons["extensionOn.continue"].tapWhenHittable()
        let notNow = app.buttons["notificationAsk.notNow"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5), app.debugDescription)
        notNow.tap()
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["notificationAsk"].exists)
    }

    @MainActor
    func testExtensionOffKeepsTheFigmaScreenAfterSettingsAndRelaunchResumes() {
        let app = launch(extensionActive: false)
        app.onboardName("Rina")
        app.passTurnOnExtension()
        // Back from Settings, still off: the same Figma frame (steps + one button), no status note.
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["extension.step.3"].exists, app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["extension.offHint"].exists)
        XCTAssertFalse(app.buttons["extension.skipCheck"].exists)
        // Registered on the first tap: no way back to the name.
        XCTAssertFalse(app.buttons["onboarding.back"].exists)

        // F6 (goldfish 21 Nov 2026): iOS closed the app in Settings. The relaunch carries on at ON-04 while Shoo
        // is still off, not on Home (the Safari Default step would be lost).
        app.terminate()
        let again = XCUIApplication.mock(["-settings.language", "en", "-UITestNotifications", "denied"], reset: false)
        XCTAssertTrue(again.buttons["extension.turnOn"].waitForExistence(timeout: 10), again.debugDescription)
        XCTAssertFalse(again.tabBars.buttons["Shield"].exists)

        // Switched on in the meantime: straight on to Safari Default, then the success screen.
        again.terminate()
        let on = XCUIApplication.mock(
            ["-settings.language", "en", "-UITestNotifications", "denied", "-UITestExtensionActive", "YES"], reset: false
        )
        XCTAssertTrue(on.buttons["safariDefault.open"].waitForExistence(timeout: 10), on.debugDescription)
        on.passSafariDefault()
        XCTAssertTrue(on.buttons["extensionOn.continue"].waitForExistence(timeout: UITestTimeout.screen), on.debugDescription)

        // Past Safari Default (it can't be read, so a flag remembers it): the success screen again.
        on.terminate()
        let last = XCUIApplication.mock(["-settings.language", "en", "-UITestNotifications", "denied"], reset: false)
        XCTAssertTrue(last.buttons["extensionOn.continue"].waitForExistence(timeout: 10), last.debugDescription)
        last.finishOnboarding()
        XCTAssertTrue(last.tabBars.buttons["Shield"].waitForExistence(timeout: 10), last.debugDescription)
    }

    /// Usability test 20 Nov 2026: "All Websites → Allow" is a numbered step, and when
    /// the extension has reported that it may read only some sites, onboarding says so and does not move on.
    @MainActor
    func testAllWebsitesStepAndWarningWhenShooCanReadOnlySomeSites() {
        let app = launch(extensionActive: false, extensionStatus: "someSitesOnly")
        app.onboardName("Rina")
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5), app.debugDescription)
        // The mock answered the data question, so there is no box and step 01 keeps "Tap the button below".
        if #available(iOS 26.2, *) {
            XCTAssertTrue(app.staticTexts["Tap the button below to open Safari settings."].exists, app.debugDescription)
        }
        XCTAssertTrue(app.staticTexts["Tap All Websites and choose Allow, not Ask."].exists, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["extension.step.4"].exists, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["extension.offHint"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["extension.continue"].exists)
    }

    /// Figma 110:4440 (Alief, 20 Nov 2026): on a 402 × 874 iPhone all four steps show above the consent box
    /// without scrolling. `SHOO_SHOT_DIR` keeps the screen, in Indonesian, for the PR.
    @MainActor
    func testAllFourStepsFitAboveTheConsentBoxWithoutScrolling() throws {
        let app = XCUIApplication.mock([
            "-settings.language", "id", "-UITestNotifications", "denied", "-debug.askDataConsent", "YES",
            "-debug.onboardingStep", "turnOnExtension",
        ])
        let consent = app.buttons["extension.consent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5), app.debugDescription)
        guard app.windows.firstMatch.frame.height >= 874 else { throw XCTSkip("Figma's page is 874 pt; smaller iPhones scroll") }
        let step4 = app.descendants(matching: .any)["extension.step.4"]
        XCTAssertTrue(step4.exists, app.debugDescription)
        XCTAssertLessThanOrEqual(step4.frame.maxY, consent.frame.minY, "step 04 \(step4.frame) vs box \(consent.frame)")
        if let directory = ProcessInfo.processInfo.environment["SHOO_SHOT_DIR"] {
            try XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("on04-all-steps-fit.png"))
        }
    }

    /// QA 2026-11-11 #7: back from Settings with Shoo still off, the note above the steps pushes step 03 down
    /// behind the consent box. The footer hides what is under it (no text through text), and the step scrolls
    /// up clear of the box. `SHOO_SHOT_DIR` keeps the screen for the PR.
    @MainActor
    func testStepsScrollClearOfTheConsentAfterSettings() throws {
        // The box shows only while the question is unanswered (fase 27d).
        let app = launch(extensionActive: false, askConsent: true)
        app.onboardName("Rina")
        app.passTurnOnExtension()
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5), app.debugDescription)
        let consent = app.buttons["extension.consent"]
        let last = app.descendants(matching: .any)["extension.step.3"]
        XCTAssertTrue(last.waitForExistence(timeout: 5), app.debugDescription)
        let screenshot = XCUIScreen.main.screenshot()
        if let directory = ProcessInfo.processInfo.environment["SHOO_SHOT_DIR"] {
            try screenshot.pngRepresentation
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("on04-back-from-settings.png"))
        }
        // Right of "See what is sent" the footer draws nothing: step 03's text must not show through there
        // (main: ~5000 dark pixels here; the fix: a few edge pixels of the link).
        let link = app.buttons["extension.dataSent"]
        XCTAssertTrue(link.exists, app.debugDescription)
        let empty = CGRect(x: link.frame.maxX + 12, y: link.frame.minY + 4,
                           width: app.frame.width - 24 - (link.frame.maxX + 12), height: link.frame.height - 8)
        let marks = Self.inkPixels(in: empty, of: screenshot.image)
        XCTAssertLessThan(marks, 300, "\(marks) dark pixels in \(empty): the steps show through the footer")
        XCTAssertTrue(consent.isHittable)
        for _ in 0..<3 where last.frame.maxY > consent.frame.minY { app.swipeUp() }
        XCTAssertLessThanOrEqual(last.frame.maxY, consent.frame.minY, "step \(last.frame) under consent \(consent.frame)")
        XCTAssertTrue(consent.isHittable)
    }

    /// Pixels in `rect` (points) clearly darker than the page background (text, even faded text).
    private static func inkPixels(in rect: CGRect, of image: UIImage) -> Int {
        guard let cgImage = image.cgImage, rect.width > 0, rect.height > 0 else { return 0 }
        let scale = CGFloat(cgImage.width) / image.size.width
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let crop = cgImage.cropping(to: pixels) else { return 0 }
        let width = crop.width, height = crop.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for index in stride(from: 0, to: data.count, by: 4) {
            let luminance = 0.299 * Double(data[index]) + 0.587 * Double(data[index + 1]) + 0.114 * Double(data[index + 2])
            if luminance < 215 { count += 1 }
        }
        return count
    }

    @MainActor
    func testNarrowedAccessKeepsOneTurnOnButtonOnceBack() {
        let app = launch(extensionActive: false, extensionStatus: "someSitesOnly")
        app.onboardName("Rina")
        // Straight to Settings and back (see `testBackFromSettingsStillOffSaysSo`): the toast lasts 6 s.
        let consent = app.buttons["extension.consent"]
        if consent.waitForExistence(timeout: UITestTimeout.screen), !consent.isSelected { consent.tapWhenHittable() }
        app.buttons["extension.turnOn"].tapWhenHittable()
        app.comeBackFromSettings()
        // F3 B: Shoo says which step is missing.
        let toast = app.descendants(matching: .any)["extension.returnToast.text"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(toast.label.contains("Shoo is on for some sites only"), toast.label)
        XCTAssertTrue(toast.label.contains("step 03"), toast.label)
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["extension.openSafari"].exists)
        XCTAssertFalse(app.buttons["extension.settings"].exists)
        XCTAssertFalse(app.buttons["extension.skipCheck"].exists)
    }

    /// F3 A (goldfish 21 Nov 2026): back from Settings with Shoo still off, a toast says so with the step to redo.
    /// It is said once per return, and only after a trip to Settings (not when the screen first opens).
    @MainActor
    func testBackFromSettingsStillOffSaysSo() {
        let app = launch(extensionActive: false, extensionStatus: "switchedOff")
        app.onboardName("Rina")
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["extension.returnToast"].exists)
        // Straight to Settings and back: `passTurnOnExtension` waits for a Next that never comes here, and on a
        // slow runner that wait used up the toast's 6 s.
        let consent = app.buttons["extension.consent"]
        if consent.waitForExistence(timeout: UITestTimeout.screen), !consent.isSelected { consent.tapWhenHittable() }
        app.buttons["extension.turnOn"].tapWhenHittable()
        app.comeBackFromSettings()
        let toast = app.descendants(matching: .any)["extension.returnToast.text"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(toast.label.contains("Shoo isn't on yet"), toast.label)
        XCTAssertTrue(toast.label.contains("step 02"), toast.label)
        // A tap closes it; the screen under it is unchanged.
        app.descendants(matching: .any)["extension.returnToast"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["extension.returnToast"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["extension.turnOn"].exists)
    }

    @MainActor
    func testSwitchOnWithoutAPageMovesOnToSafariDefault() {
        let app = launch(extensionActive: false, extensionStatus: "unchecked")
        app.onboardName("Rina")
        app.passTurnOnExtension()
        XCTAssertTrue(app.buttons["safariDefault.open"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["extension.skipCheck"].exists)
    }

    @MainActor
    func testSafariDefaultTurnsIntoKeepGoingAfterSettingsAndBackStays() {
        let app = launch()
        app.onboardName("Rina")
        app.passTurnOnExtension()
        XCTAssertTrue(app.buttons["safariDefault.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["safariDefault.alreadyUsing"].exists)
        app.buttons["safariDefault.open"].tap()
        app.activate()
        XCTAssertTrue(app.buttons["safariDefault.check"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["safariDefault.openAgain"].exists)
        // Shoo is on, so ON-04 would pass again: Back stays there and offers Next.
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.buttons["extension.continue"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["extension.continue"].tap()
        XCTAssertTrue(app.buttons["safariDefault.open"].waitForExistence(timeout: 5))
    }

    /// "Cek & lanjutkan" (Figma 2497:4919, screens 7–9): a heartbeat newer than the tap with every site allowed goes
    /// straight to the success screen.
    @MainActor
    func testSafariCheckPassesToSuccess() {
        let app = launch()
        app.onboardName("Rina")
        app.passTurnOnExtension()
        app.buttons["safariDefault.open"].tapWhenHittable()
        app.comeBackFromSettings()
        XCTAssertTrue(app.staticTexts["Tap Check & continue. Shoo opens one page to check, then you come back to Shoo."]
            .waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["safariDefault.check"].tapWhenHittable()
        app.comeBackFromSettings()
        XCTAssertTrue(app.buttons["extensionOn.continue"].waitForExistence(timeout: 15), app.debugDescription)
    }

    /// Branch 8a: the heartbeat says Safari asks per site. Toast B, "Open Safari settings", "Check again".
    @MainActor
    func testSafariCheckSomeSitesOnlyShowsToastB() {
        // ON-04 never offers Next while Safari asks per site, so this starts on Safari Default itself.
        let app = XCUIApplication.mock([
            "-settings.language", "en", "-UITestNotifications", "denied",
            "-UITestExtensionStatus", "someSitesOnly", "-debug.onboardingStep", "safariDefault",
        ])
        app.buttons["safariDefault.open"].tapWhenHittable()
        app.comeBackFromSettings()
        app.buttons["safariDefault.check"].tapWhenHittable()
        app.comeBackFromSettings()
        let toast = app.descendants(matching: .any)["safariDefault.toast.text"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(toast.label.contains("All Websites"), toast.label)
        XCTAssertTrue(app.buttons["safariDefault.openSafariSettings"].exists)
        XCTAssertTrue(app.buttons["safariDefault.checkAgain"].exists)
    }

    /// Branch 8b: nothing came back (another default browser, or Safari still asks). "Try again" or "Continue anyway".
    @MainActor
    func testSafariCheckWithoutHeartbeatOffersRetryAndSkip() {
        let app = launch(extensionActive: false, extensionStatus: "unchecked")
        app.onboardName("Rina")
        app.passTurnOnExtension()
        app.buttons["safariDefault.open"].tapWhenHittable()
        app.comeBackFromSettings()
        app.buttons["safariDefault.check"].tapWhenHittable()
        app.comeBackFromSettings()
        let toast = app.descendants(matching: .any)["safariDefault.toast.text"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(toast.label.contains("couldn't be checked"), toast.label)
        XCTAssertTrue(app.buttons["safariDefault.retry"].exists)
        app.buttons["safariDefault.skip"].tap()
        XCTAssertTrue(app.buttons["extensionOn.continue"].waitForExistence(timeout: 5), app.debugDescription)
    }

    /// On a device the link opens PiP. iPhone simulators report no PiP support, so the link falls back to
    /// the full-screen player, which this test closes.
    @MainActor
    func testVideoLinkOpensPlayer() {
        let app = launch(extensionActive: false)
        app.onboardName("Rina")
        XCTAssertTrue(app.buttons["extension.video"].waitForExistence(timeout: 5))
        app.buttons["extension.video"].tap()
        XCTAssertTrue(app.buttons["video.close"].waitForExistence(timeout: 5))
        app.buttons["video.close"].tap()
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTurnOnOpensSettings() {
        let app = launch(extensionActive: false, askConsent: true)
        app.onboardName("Rina")
        app.buttons["extension.consent"].tapWhenHittable()
        app.buttons["extension.turnOn"].tapWhenHittable()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
    }

    @MainActor
    func testGuardianIntroShowsOnceBeforeFamilyMode() {
        let app = XCUIApplication.mock(["-settings.language", "en", "-settings.mode", "guardian", "-settings.onboardingCompleted", "YES",
                                        "-settings.familyModeOn", "NO", "-UITestNotifications", "granted",
                                        "-mock.scenario", "empty"])
        // Never Guardian: no ⇆ yet, the "Jadi Penjaga" card is the way in.
        let toggle = app.descendants(matching: .any)["familyModeToggle"].firstMatch
        let card = app.buttons["home.guardianCard.action"]
        card.tapWhenHittable()
        XCTAssertFalse(toggle.exists)
        let start = app.buttons["guardianIntro.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), app.debugDescription)
        // Back keeps Pribadi.
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(start.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["home.guardianCard"].exists)
        card.tapWhenHittable()
        app.buttons["guardianIntro.start"].tapWhenHittable()
        XCTAssertTrue(start.waitForNonExistence(timeout: 5))
        // ⇆ appears, with the one-time tip; the toast waits until a tap closes it.
        let tip = app.descendants(matching: .any)["home.switchTip"].firstMatch
        XCTAssertTrue(tip.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(toggle.exists)
        XCTAssertFalse(app.descendants(matching: .any)["home.notice"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        XCTAssertTrue(tip.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["home.notice"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["home.guardianCard"].exists)
    }
}
