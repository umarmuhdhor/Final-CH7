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
        XCTAssertFalse(turnOn.isEnabled)
        // No status note before the user has been to Settings (Figma has none).
        XCTAssertFalse(app.descendants(matching: .any)["extension.offHint"].exists)
        app.buttons["extension.dataSent"].tap()
        XCTAssertTrue(app.staticTexts["AI check by DeepSeek"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["dataSent.done"].tap()
        XCTAssertTrue(app.staticTexts["AI check by DeepSeek"].waitForNonExistence(timeout: 5))
        app.buttons["extension.consent"].tap()
        XCTAssertTrue(turnOn.isEnabled)
        // Nothing saved yet: Back still reaches the name.
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.textFields["name.field"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPersonalOnboardingEndsOnHomeWithReminderWhenNotificationsDenied() {
        // Nobody to look after yet: Home Pribadi shows the "Mode Terawasi" card only then (#364).
        let app = launch(notifications: "denied", scenario: "empty")
        app.onboardName("Rina")
        // Figma "Flow": no mode choice and no invite step.
        XCTAssertFalse(app.buttons["mode.continue"].exists)
        app.passTurnOnExtension()
        app.passSafariDefault()
        // Next asks for notifications; the mock answers "denied".
        XCTAssertTrue(app.buttons["extensionOn.continue"].waitForExistence(timeout: 5))
        app.buttons["extensionOn.continue"].tap()
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: 5))
        let reminder = app.alerts["Notifications are off"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5), app.debugDescription)
        reminder.buttons["Not now"].firstMatch.tap()
        XCTAssertFalse(reminder.waitForExistence(timeout: 2))
        // Pribadi Home offers to connect to a guardian (Figma 1253:8630).
        XCTAssertTrue(app.descendants(matching: .any)["home.supervised"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testExtensionOffShowsTheNoteAfterSettingsAndRelaunchGoesHome() {
        let app = launch(extensionActive: false)
        app.onboardName("Rina")
        app.passTurnOnExtension()
        XCTAssertTrue(app.buttons["extension.turnOn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["extension.offHint"].waitForExistence(timeout: 5), app.debugDescription)
        // Registered on the first tap: no way back to the name.
        XCTAssertFalse(app.buttons["onboarding.back"].exists)

        // Relaunch without reset: Home shows that Shoo is still off (Figma note 141:6085).
        app.terminate()
        let again = XCUIApplication.mock(["-settings.language", "en", "-UITestNotifications", "denied"], reset: false)
        XCTAssertTrue(again.tabBars.buttons["Shield"].waitForExistence(timeout: 10), again.debugDescription)
    }

    /// QA 2026-11-11 #7: back from Settings with Shoo still off, the note above the steps pushes step 03 down
    /// behind the consent box. The footer hides what is under it (no text through text), and the step scrolls
    /// up clear of the box. `SHOO_SHOT_DIR` keeps the screen for the PR.
    @MainActor
    func testStepsScrollClearOfTheConsentAfterSettings() throws {
        let app = launch(extensionActive: false)
        app.onboardName("Rina")
        app.passTurnOnExtension()
        XCTAssertTrue(app.descendants(matching: .any)["extension.offHint"].waitForExistence(timeout: 5), app.debugDescription)
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
    func testNarrowedAccessOffersSafariAndSettingsOnceBack() {
        let app = launch(extensionActive: false, extensionStatus: "someSitesOnly")
        app.onboardName("Rina")
        app.passTurnOnExtension()
        XCTAssertTrue(app.buttons["extension.openSafari"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["extension.settings"].exists)
        XCTAssertFalse(app.buttons["extension.skipCheck"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "can't check every website")).firstMatch.exists)
    }

    @MainActor
    func testSwitchOnWithoutAPageCanContinueWithoutChecking() {
        let app = launch(extensionActive: false, extensionStatus: "unchecked")
        app.onboardName("Rina")
        app.passTurnOnExtension()
        XCTAssertTrue(app.buttons["extension.skipCheck"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["extension.openSafari"].exists)
        app.buttons["extension.skipCheck"].tap()
        XCTAssertTrue(app.buttons["safariDefault.open"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["safariDefault.continue"].waitForExistence(timeout: 10), app.debugDescription)
        // Shoo is on, so ON-04 would pass again: Back stays there and offers Next.
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.buttons["extension.continue"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["extension.continue"].tap()
        XCTAssertTrue(app.buttons["safariDefault.open"].waitForExistence(timeout: 5))
    }

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
        let toggle = app.descendants(matching: .any)["familyModeToggle"].firstMatch
        toggle.tapWhenHittable()
        let start = app.buttons["guardianIntro.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), app.debugDescription)
        // Back keeps Pribadi.
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(start.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["home.supervised"].exists)
        toggle.tapWhenHittable()
        app.buttons["guardianIntro.start"].tapWhenHittable()
        XCTAssertTrue(start.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["home.supervised"].exists)
    }
}
