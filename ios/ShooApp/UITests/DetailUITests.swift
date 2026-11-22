import XCTest

/// Fase 03: Detail (DT-01..06) and the guardian's verdict buttons (GD-07), on fixtures.
final class DetailUITests: XCTestCase {
    static let blocked92 = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"
    static let warning41 = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e01"
    static let markedSafe = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e05"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func openDetail(
        _ scanId: String, mode: String = "guardian", language: String = "en", pageCopy: Bool = false,
        extra: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication.mock((pageCopy ? ["-debug.replicaFixture", "YES"] : []) + [
            "-settings.onboardingCompleted", "YES",
            "-settings.mode", mode,
            "-settings.language", language,
            "-debug.detail", scanId,
        ] + extra)
        XCTAssertTrue(app.descendants(matching: .any)["detail.header"].waitForExistence(timeout: 10), app.debugDescription)
        return app
    }

    /// fase 18b: the page copy is drawn into the cards, with its line above them.
    @MainActor
    func testPageCopyShowsWithItsLine() {
        var app = openDetail(Self.blocked92, pageCopy: true)
        var line = app.descendants(matching: .any)["detail.pageCopy"].firstMatch
        // The line shows only once WebKit has drawn the copy: up to `ReplicaSnapshot.loadTimeout` (10 s) plus
        // `snapshotTimeout` (5 s). A busy CI runner used all of it (#354, #363), so 15 s was too tight.
        // Past that the app has given up and shows the screenshot, so waiting longer can't help. A cold WebKit
        // content process on CI can still miss `loadTimeout` (#402): one fresh launch gets a second draw, as
        // `PageCopyTests` tries the render three times. A copy that never draws still fails below.
        if !line.waitForExistence(timeout: 30) {
            app.terminate()
            app = openDetail(Self.blocked92, pageCopy: true)
            line = app.descendants(matching: .any)["detail.pageCopy"].firstMatch
        }
        XCTAssertTrue(line.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(line.label.contains("Copy of the page"), line.label)
        XCTAssertTrue(line.label.contains("Copied from bca-verifikasi.site/login/pin"), line.label)
        XCTAssertTrue(app.descendants(matching: .any)["detail.screenshot"].firstMatch.exists)
        XCTAssertFalse(app.webViews.firstMatch.exists, "no live web view on screen")
    }

    @MainActor
    func testGuardianMarksNotSafeAtOnce() {
        let app = openDetail(Self.blocked92)
        let header = app.descendants(matching: .any)["detail.header"]
        XCTAssertTrue((header.value as? String ?? "").contains("Blocked"))
        XCTAssertTrue(app.descendants(matching: .any)["detail.link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["detail.owner"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["detail.evidence.2"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["detail.evidence.3"].exists)

        app.buttons["detail.verdict.notSafe"].tap()

        // No confirmation dialog: the label changes right away.
        XCTAssertEqual(app.alerts.count, 0)
        let note = app.descendants(matching: .any)["detail.verdictNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue((header.value as? String ?? "").contains("Verified scam by you"), header.debugDescription)
        // The card replaces the buttons, with "Change" to undo it.
        XCTAssertFalse(app.buttons["detail.verdict.notSafe"].exists)
        XCTAssertTrue(app.buttons["detail.verdictChange"].exists)
    }

    /// QA 2026-11-11 #5: a Danger tapped by mistake can be changed back to Safe (R4: NotSafe → Safe).
    @MainActor
    func testDangerCanBeChangedBackToSafe() throws {
        let app = openDetail(Self.blocked92)
        app.buttons["detail.verdict.notSafe"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.verdictNote"].waitForExistence(timeout: 5), app.debugDescription)
        try shot(app, "detail-after-danger")
        let change = app.buttons["detail.verdictChange"]
        XCTAssertTrue(change.waitForExistence(timeout: 5), app.debugDescription)
        change.tap()
        let safe = app.buttons["detail.verdict.safe"]
        XCTAssertTrue(safe.waitForExistence(timeout: 5), app.debugDescription)
        try shot(app, "detail-change-open")
        safe.tap()
        // GD-07: "Aman" asks why first (SafeReasonSheet).
        let reason = app.buttons["safeReason.chip.official_site"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5), app.debugDescription)
        reason.tap()
        app.buttons["safeReason.submit"].tap()
        let header = app.descendants(matching: .any)["detail.header"]
        let marked = expectation(for: NSPredicate(format: "value CONTAINS 'Marked safe by you'"), evaluatedWith: header)
        wait(for: [marked], timeout: 5)
        try shot(app, "detail-back-to-safe")
        // GD-07: a fresh "Aman" is locked until the weekly AI review.
        XCTAssertFalse(app.buttons["detail.verdictChange"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["detail.verdictLocked"].exists, app.debugDescription)
    }

    /// 29g peek sheet: "Tandai aman" still closes like a sheet: a drag down and a tap on the dimming drop it, and
    /// nothing is saved.
    @MainActor
    func testSafeReasonSheetClosesOnDragAndDimming() {
        let app = openDetail(Self.blocked92)
        let safe = app.buttons["detail.verdict.safe"]
        let sheet = app.descendants(matching: .any)["safeReason.sheet"]
        let reason = app.buttons["safeReason.chip.official_site"]

        safe.tap()
        XCTAssertTrue(reason.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        let start = reason.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 500)))
        XCTAssertTrue(sheet.waitForNonExistence(timeout: UITestTimeout.screen), app.debugDescription)

        safe.tapWhenHittable()
        XCTAssertTrue(reason.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.12)).tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: UITestTimeout.screen), app.debugDescription)
        XCTAssertTrue(safe.isHittable, app.debugDescription)
    }

    /// A-02 (fase 28c, K5): "Aman" was saved but its answer was lost; the retry gets `409 verdict_locked`.
    /// Detail reloads and shows the server's safe verdict, so the badge, buttons and footer agree.
    @MainActor
    func testLockedVerdictShowsTheServersSafeVerdict() throws {
        try lockedVerdictShowsTheServersSafeVerdict(language: "en")
    }

    @MainActor
    func testLockedVerdictShowsTheServersSafeVerdictInIndonesian() throws {
        try lockedVerdictShowsTheServersSafeVerdict(language: "id")
    }

    @MainActor
    private func lockedVerdictShowsTheServersSafeVerdict(language: String) throws {
        let app = openDetail(
            Self.blocked92, language: language,
            extra: ["-mock.fail", "setVerdict.lost,setVerdict~1=verdict_locked"]
        )
        app.buttons["detail.verdict.safe"].tap()
        let reason = app.buttons["safeReason.chip.official_site"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5), app.debugDescription)
        reason.tap()
        app.buttons["safeReason.submit"].tap()
        // The answer was lost: the sheet stays with "Try again".
        XCTAssertTrue(app.descendants(matching: .any)["safeReason.error"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["safeReason.submit"].tap()
        // The 409 closes the sheet once Detail reloaded; the footer says the site stays safe until the review.
        XCTAssertTrue(app.descendants(matching: .any)["safeReason.sheet"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["detail.verdictError"].waitForExistence(timeout: 5), app.debugDescription)
        let decided = app.descendants(matching: .any)["detail.verdictNote"].waitForExistence(timeout: 5)
        try shot(app, "detail-locked-\(language)")
        XCTAssertTrue(decided, "\(language): no verdict after verdict_locked\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["detail.verdict.safe"].waitForNonExistence(timeout: 5), language)
        XCTAssertTrue(app.buttons["detail.verdict.notSafe"].waitForNonExistence(timeout: 5), language)
        XCTAssertTrue(app.descendants(matching: .any)["detail.verdictLocked"].exists, app.debugDescription)
    }

    /// `SHOO_SHOT_DIR` keeps the screens for the PR.
    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SHOO_SHOT_DIR"] else { return }
        try XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }

    @MainActor
    func testChangeBringsTheButtonsBackOnASafeVerdict() {
        let app = openDetail(Self.markedSafe)
        XCTAssertFalse(app.buttons["detail.verdict.safe"].exists)
        let change = app.buttons["detail.verdictChange"]
        XCTAssertTrue(change.waitForExistence(timeout: 5), app.debugDescription)
        change.tap()
        XCTAssertTrue(app.buttons["detail.verdict.notSafe"].waitForExistence(timeout: 5))
        app.buttons["detail.verdict.notSafe"].tap()
        let header = app.descendants(matching: .any)["detail.header"]
        let expectation = expectation(for: NSPredicate(format: "value CONTAINS 'Verified scam by you'"), evaluatedWith: header)
        wait(for: [expectation], timeout: 5)
    }

    /// DT-04: an address reason shows the domain instead of the page; the page photo is not tappable (no full
    /// screen view).
    @MainActor
    func testAddressReasonShowsTheDomainAndThePhotoIsNotAButton() {
        let app = openDetail(Self.blocked92, pageCopy: true)
        // new_domain is the heaviest reason: its card is the address, not a photo.
        let address = app.descendants(matching: .any)["detail.address.0"]
        XCTAssertTrue(address.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(address.label.contains("bca-verifikasi.site"), address.label)
        app.swipeUp()
        let photo = app.descendants(matching: .any)["detail.screenshot"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["detail.screenshot"].exists)
        // unreasonable_request has two marks on the fixture page: one photo per mark, swiped sideways.
        app.swipeUp()
        let carousel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'detail.carousel.'")).firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS ' of 2'")).firstMatch.exists, app.debugDescription)
    }

    /// DT-04 (#497): with the detector's `host`, the address card names the brand's real address.
    @MainActor
    func testAddressCardNamesTheRealAddress() {
        let app = openDetail("address-marks", extra: ["-mock.scenario", "addressMarks"])
        let address = app.descendants(matching: .any)["detail.address.0"]
        XCTAssertTrue(address.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(address.label.contains("bca-verifikasi.site"), address.label)
        XCTAssertTrue(address.label.contains("Real address: bca.co.id"), address.label)
        // new_domain has no `host`: no real-address line on its card.
        let age = app.descendants(matching: .any)["detail.address.1"]
        XCTAssertTrue(age.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(age.label.contains("Real:"), age.label)
    }

    @MainActor
    func testWarningTakesAVerdictAndHasNoPhotoWithoutAScreenshot() {
        let app = openDetail(Self.warning41)
        XCTAssertTrue((app.descendants(matching: .any)["detail.header"].value as? String ?? "").contains("Warning"))
        // GD-07: warnings take a verdict too (Figma 416:9469, #190).
        XCTAssertTrue(app.buttons["detail.verdict.safe"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["detail.screenshot"].exists)
    }

    @MainActor
    func testProtectedSeesSimpleWordsAndNoButtons() {
        let app = openDetail(Self.blocked92, mode: "protected")
        XCTAssertFalse(app.buttons["detail.verdict.safe"].exists)
        XCTAssertFalse(app.buttons["detail.verdict.notSafe"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["detail.owner"].exists)
        let first = app.descendants(matching: .any)["detail.evidence.0"]
        XCTAssertEqual(first.label, "This site was made 3 days ago, adds 30 percent to the risk score")
    }

    @MainActor
    func testProtectedIndonesianVerdictNote() {
        let app = openDetail(Self.markedSafe, mode: "protected", language: "id")
        let header = app.descendants(matching: .any)["detail.header"]
        XCTAssertTrue((header.value as? String ?? "").contains("Ditandai aman oleh Adhella"), header.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["detail.verdictNote"].exists)
        XCTAssertFalse(app.buttons["detail.verdictChange"].exists)
    }

    /// Screens below the fold for the UI gate (attached to the result bundle, `keepAlways`).
    @MainActor
    func testBelowTheFoldScreens() {
        let app = openDetail(Self.blocked92)
        attach(app, "blocked-92-guardian-en-top")
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["detail.screenshot"].firstMatch.waitForExistence(timeout: 5))
        attach(app, "blocked-92-guardian-en-bottom")
        app.buttons["detail.verdict.notSafe"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.verdictNote"].waitForExistence(timeout: 5))
        app.swipeDown()
        attach(app, "blocked-92-guardian-en-after-not-safe")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// U-11 (fase 28m, GD-07): while the Guardian types a note, "Tandai Aman" stays above the keyboard and its
    /// suggestion bar. iPhone 17, ID, default size. Red on main (fase 28 cell A `sheet-safeReason-kb`): the
    /// button at y 557.3 to 613.3, the keyboard from y 590, the suggestion bar above it from y 546.
    @MainActor
    func testSafeReasonSubmitStaysAboveTheKeyboardOnIPhone17() throws {
        try XCTSkipUnless(UIScreen.main.bounds.width == 402, "measured on iPhone 17 only")
        try assertSafeReasonSubmitAboveTheKeyboard(language: "id")
    }

    /// U-11 on iPhone SE, EN, default size. Recorded on main (28m, software keyboard on screen): the button at
    /// y 497.5 to 553.5, the keyboard from y 451, the suggestion bar from y 407. The matrix cell E said pass, but
    /// its screenshot had no keyboard (notes [f]).
    @MainActor
    func testSafeReasonSubmitStaysAboveTheKeyboardOnSE() throws {
        try XCTSkipUnless(UIScreen.main.bounds.width == 375, "measured on iPhone SE only")
        try assertSafeReasonSubmitAboveTheKeyboard(language: "en")
    }

    @MainActor
    private func assertSafeReasonSubmitAboveTheKeyboard(language: String) throws {
        let app = openDetail(Self.blocked92, language: language, extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"])
        app.buttons["detail.verdict.safe"].tap()
        let reason = app.buttons["safeReason.chip.official_site"]
        XCTAssertTrue(reason.waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        reason.tap()
        let note = app.descendants(matching: .any)["safeReason.note"].firstMatch
        note.tap()
        // A simulator with a hardware keyboard shows none, and without one this test proves nothing.
        // A minimized keyboard also "exists", below the screen's bottom edge: it has to be on the screen.
        let keyboard = app.keyboards.firstMatch
        let screenBottom = app.frame.maxY
        let onScreen = NSPredicate { _, _ in keyboard.exists && keyboard.frame.minY < screenBottom }
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: onScreen, object: nil)], timeout: UITestTimeout.screen)
        XCTAssertLessThan(keyboard.frame.minY, screenBottom, "no software keyboard on screen: \(keyboard.frame)")
        note.typeText("Situs resmi bank saya")
        let submit = app.buttons["safeReason.submit"]
        // The suggestion bar sits on top of the keyboard when it shows. Without it (or if its private name
        // changes) the keys alone still put main's button under them on both devices (613.3 > 590, 553.5 > 451).
        func keyboardTop() -> CGFloat {
            let bar = app.otherElements["SystemInputAssistantView"]
            return bar.exists && bar.frame.height > 0 ? min(keyboard.frame.minY, bar.frame.minY) : keyboard.frame.minY
        }
        // The sheet may still be moving: wait for it before measuring.
        let above = NSPredicate { _, _ in submit.frame.maxY <= keyboardTop() }
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: above, object: nil)], timeout: UITestTimeout.screen)
        XCTAssertLessThanOrEqual(submit.frame.maxY, keyboardTop(), "Tandai Aman \(submit.frame) under the keyboard from y \(keyboardTop())")
        XCTAssertTrue(submit.isHittable, "Tandai Aman \(submit.frame) can't be tapped")
    }
}
