import XCTest

/// Fase 23c (K6 a): a Guardian sees the page copy of a real scan, on one simulator against a local stack
/// (`pnpm -C backend/api dev` + `supabase start`). Run it with `bash plan/alief/qa/replica-ui.sh`.
/// The app onboards as Guardian through the UI (a real `POST /devices`) and writes the family code on
/// screen to `$SHOO_REPLICA_DIR/code.txt`. The host script then registers a Protected device with curl,
/// joins, posts a scan with a replica built by the extension's own code (`replica-input.mjs`) and writes
/// the scan id to `scan.txt` (or the reason it could not to `error.txt`). The test opens `shoo://scan/<id>`,
/// waits for "Copy of the page" and deletes the Guardian through Profile at the end (`DELETE /devices/me`
/// from the app, so its token never leaves the simulator).
/// Skipped unless the runner gets `SHOO_LIVE_BACKEND=1`, `SHOO_LIVE_REPLICA=1` and `SHOO_REPLICA_DIR`.
/// Screenshots go to `SHOO_SHOT_DIR` when it is set.
final class LiveReplicaUITests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var replicaDir: URL { URL(fileURLWithPath: environment["SHOO_REPLICA_DIR"] ?? "/nonexistent") }

    /// The host builds the replica, posts the scan and waits until the Worker stored the copy.
    private static let scanTimeout: TimeInterval = 120
    /// K6: the copy shows within 30 s of opening Detail.
    private static let copyTimeout: TimeInterval = 30

    /// The running app, so `tearDown` can still delete the Guardian after a failure half way.
    private var app: XCUIApplication?
    private var guardianDeleted = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            environment["SHOO_LIVE_BACKEND"] == "1" && environment["SHOO_LIVE_REPLICA"] == "1"
                && environment["SHOO_REPLICA_DIR"] != nil,
            "needs replica-ui.sh: wrangler dev on localhost:8787, SHOO_LIVE_REPLICA=1 and SHOO_REPLICA_DIR"
        )
    }

    override func tearDownWithError() throws {
        // A failure half way leaves the Guardian registered: try once more to delete it, best effort.
        // Otherwise it stays in the local Supabase until `supabase db reset`.
        if let app, !guardianDeleted {
            MainActor.assumeIsolated { deleteMyData(app, strict: false) }
        }
        app = nil
    }

    @MainActor
    func testGuardianSeesThePageCopyOfALiveScan() throws {
        let app = launch()
        self.app = app

        onboardAsGuardian(app)
        let scanId = try waitForScan()

        try openLink("shoo://scan/\(scanId)")
        XCTAssertTrue(app.descendants(matching: .any)["detail.header"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        let caption = app.descendants(matching: .any)["detail.pageCopy"].firstMatch
        let shown = NSPredicate(
            format: "label CONTAINS %@ AND NOT (label CONTAINS %@) AND NOT (label CONTAINS %@)",
            "Copy of the page", "No copy of this page", "Saving a copy of the page"
        )
        let found = XCTNSPredicateExpectation(predicate: shown, object: caption)
        XCTAssertEqual(XCTWaiter().wait(for: [found], timeout: Self.copyTimeout), .completed,
                       "No page copy within \(Int(Self.copyTimeout)) s: '\(caption.exists ? caption.label : "no caption")'\n\(app.debugDescription)")
        // K12: one picture of the copy, never a live web view on screen.
        XCTAssertEqual(app.webViews.count, 0, app.debugDescription)
        // On an SE the caption sits at the bottom: drag (no momentum) until the caption and the first
        // evidence card with the picture are both on screen.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        XCTAssertEqual(app.webViews.count, 0, app.debugDescription)
        shot(app, "live-replica-se")
        // Back to the top: after the drag the header with Back is scrolled away (run 8 without this
        // could not leave Detail).
        app.swipeDown()

        // Back from a link lands on Activity (DeepLinkUITests); Profile opens from Shield.
        app.buttons["detail.back"].tapWhenHittable()
        app.tap(app.tabBars.buttons["Shield"], until: app.buttons["profileButton"].firstMatch)
        deleteMyData(app, strict: true)
        guardianDeleted = true
    }

    // MARK: Steps

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // No -UITestMock: this is ApiRepository against AppConfig.apiBaseURL (http://localhost:8787 in a
        // Debug simulator build). The extension heartbeat and the notification answer are faked.
        app.launchArguments += [
            "-settings.dataConsent", "granted",
            "-UITestReset", "YES",
            "-UITestSkipSplash", "YES",
            "-settings.language", "en",
            "-UITestNotifications", "denied",
            "-UITestExtensionActive", "YES",
        ]
        app.launch()
        return app
    }

    /// ON (Figma 1205:4696) as Pribadi: ticking the consent box registers the device (`POST /devices`).
    /// Family mode on makes the Guardian (GD-02); Profile's Invite asks for the family code
    /// (`POST /family/code`), which goes to `code.txt` for the host.
    @MainActor
    private func onboardAsGuardian(_ app: XCUIApplication) {
        // Aktifkan Ekstensi has Next at once (the extension counts as on), then Safari Default and Yeay.
        app.onboardPersonal("Rina")
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
        app.dismissNotificationsReminder()
        app.becomeGuardian()

        app.buttons["profileButton"].tapWhenHittable()
        app.buttons["profile.invite"].tapWhenHittable()
        let code = app.descendants(matching: .any)["invite.code"].firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 30), "Invite sheet never showed a code (POST /family/code failed?)\n\(app.debugDescription)")
        let sixDigits = NSPredicate { element, _ in
            ((element as? XCUIElement)?.label.filter(\.isNumber).count ?? 0) == 6
        }
        let ready = XCTNSPredicateExpectation(predicate: sixDigits, object: code)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 15), .completed, "No 6-digit code: '\(code.label)'")
        write("code.txt", String(code.label.filter(\.isNumber)))

        let done = app.buttons["invite.done"].exists ? app.buttons["invite.done"] : app.buttons["invite.close"]
        done.tapWhenHittable()
        app.buttons["profile.back"].firstMatch.tapWhenHittable()
        XCTAssertTrue(app.tabBars.buttons["Shield"].waitForExistence(timeout: UITestTimeout.screen), app.debugDescription)
    }

    /// The id the host wrote to `scan.txt`; fails at once when it wrote `error.txt` instead.
    private func waitForScan() throws -> String {
        let end = Date().addingTimeInterval(Self.scanTimeout)
        while Date() < end {
            if let error = read("error.txt") { throw HostError("Host could not create the scan: \(error)") }
            if let id = read("scan.txt") { return id }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw HostError("Host never wrote scan.txt within \(Int(Self.scanTimeout)) s")
    }

    private struct HostError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// iOS asks "Open in “Shoo”?" for a custom scheme opened from outside the app (DeepLinkUITests).
    /// Not `app.open(_:)`: that launches the app again with its launch arguments, and `-UITestReset YES`
    /// would wipe the Guardian that just onboarded (mock tests get their state back from the arguments).
    @MainActor
    private func openLink(_ link: String) throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: link), "Not a link: \(link)"))
        // Live stack, no mock: the alert can be slower than in DeepLinkUITests.
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if open.waitForExistence(timeout: UITestTimeout.screen) { open.tap() }
    }

    /// Profile → "Delete my data" → confirm: `DELETE /devices/me` from the app, back to the splash.
    /// `strict: false` (teardown after a failure) records nothing when a step is missing.
    @MainActor
    private func deleteMyData(_ app: XCUIApplication, strict: Bool) {
        guard app.state == .runningForeground else { return }
        let button = app.buttons["profileButton"].firstMatch
        let delete = app.buttons["profile.delete"]
        if strict {
            app.tap(button, until: delete)
        } else {
            // Most failures leave the app on Detail (no copy): back out, then Shield has the Profile button.
            let back = app.buttons["detail.back"]
            if back.exists, back.isHittable { back.tap() }
            let shield = app.tabBars.buttons["Shield"]
            if shield.waitForExistence(timeout: UITestTimeout.optional) { shield.tap() }
            guard button.waitForExistence(timeout: UITestTimeout.optional) else { return }
            button.tap()
            guard delete.waitForExistence(timeout: UITestTimeout.screen) else { return }
        }
        // The row is below the cards on a small screen.
        for _ in 0..<6 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        let confirm = app.buttons["profile.delete.confirm"].firstMatch
        guard confirm.waitForExistence(timeout: UITestTimeout.screen) else {
            if strict { XCTFail("No delete confirmation\n\(app.debugDescription)") }
            return
        }
        confirm.tap()
        let splash = app.buttons["splash.skip"].waitForExistence(timeout: 15)
        if strict { XCTAssertTrue(splash, "Delete did not return to onboarding\n\(app.debugDescription)") }
    }

    // MARK: Files shared with the host

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let directory = environment["SHOO_SHOT_DIR"] else { return }
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }

    private func read(_ name: String) -> String? {
        let text = (try? String(contentsOf: replicaDir.appendingPathComponent(name), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private func write(_ name: String, _ text: String) {
        do {
            try text.write(to: replicaDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Could not write \(name) to SHOO_REPLICA_DIR: \(error)")
        }
    }
}
