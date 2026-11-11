import XCTest

/// Figma parity QA (plan/alief/qa/figma-parity-2026-10-31.md): every app screen next to its Figma frame.
/// Not a gate: it only takes screenshots. Run with `TEST_RUNNER_QA_SHOT_DIR=<dir>` to get the PNGs as files
/// (they are attached to the result bundle either way), and `TEST_RUNNER_QA_SCENARIO=<name>` for a
/// `MockRepository.Scenario` other than `figma`.
final class FigmaParityUITests: XCTestCase {
    private var scenario: String { ProcessInfo.processInfo.environment["QA_SCENARIO"] ?? "figma" }
    private var prefix: String { scenario == "figma" ? "" : "\(scenario)-" }

    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: Onboarding

    @MainActor
    func testOnboarding() {
        guard scenario == "figma" else { return }
        var app = launch(["-UITestReset", "YES"], onboarded: false)
        XCTAssertTrue(app.buttons["splash.next"].waitForExistence(timeout: 10))
        // Figma 110:3692 "Onboarding 1" and 110:3786 "Onboarding 2"; wait for the page swipe to finish.
        shot("on-splash-1")
        app.buttons["splash.next"].tap()
        settle()
        shot("on-splash-2")

        for step in ["name", "connect", "turnOnExtension", "safariDefault", "extensionOn"] {
            // "Aktifkan Ekstensi" only shows while the extension is still off.
            app = launch(["-UITestReset", "YES", "-debug.onboardingStep", step], onboarded: false, extensionActive: step != "turnOnExtension")
            shot("on-\(step)")
            switch step {
            case "name":
                let field = app.textFields["name.field"]
                if field.waitForExistence(timeout: 5) {
                    field.tap()
                    field.typeText("Nisrina")
                    shot("on-name-typed")
                    // Figma 110:4271 "nama terlalu panjang": over the 20-character limit.
                    field.typeText(" Thifal Khairunnisa")
                    _ = app.descendants(matching: .any)["name.error"].waitForExistence(timeout: 3)
                    // Figma shows this state with the keyboard down.
                    dismissKeyboard(app)
                    settle()
                    shot("on-name-tooLong")
                }
            case "connect":
                // Figma 141:5887 "Connect with Guardian · Kode" (keyboard down) and 140:5762 "· Pindai QR".
                let typed = app.textFields["connect.code"]
                if typed.waitForExistence(timeout: 5) {
                    typed.tap()
                    typed.typeText("4821")
                    dismissKeyboard(app)
                    settle()
                    shot("on-connect-typed")
                    if tapIfExists(app.buttons["connect.tab.scan"]) { shot("on-connect-qr") }
                }
                app = launch(["-UITestReset", "YES", "-debug.onboardingStep", step, "-settings.mode", "protected"], onboarded: false)
                let code = app.textFields["connect.code"]
                if code.waitForExistence(timeout: 5) {
                    code.tap()
                    code.typeText("999999")
                    if app.buttons["connect.join"].exists { app.buttons["connect.join"].tap() }
                    _ = app.descendants(matching: .any)["connect.error"].waitForExistence(timeout: 5)
                    dismissKeyboard(app)
                    settle()
                    shot("on-connect-expired")
                    // Figma 205:1081 "Kode Kadaluarsa · QR": the same error under the scanner.
                    if tapIfExists(app.buttons["connect.tab.scan"]) {
                        settle()
                        shot("on-connect-expired-qr")
                    }
                }
                // Figma 141:5945 "Berhasil Terhubung" (PR-02).
                // "unpaired": no guardian yet, so the join goes through.
                app = launch(
                    ["-UITestReset", "YES", "-debug.onboardingStep", step, "-settings.mode", "protected", "-mock.scenario", "unpaired"],
                    onboarded: false
                )
                let fresh = app.textFields["connect.code"]
                if fresh.waitForExistence(timeout: 5) {
                    fresh.tap()
                    fresh.typeText("123456")
                    if app.buttons["connect.join"].exists { app.buttons["connect.join"].tap() }
                    settle()
                    shot("on-connected")
                }
            case "turnOnExtension":
                // Figma 1328:13415 (box ticked) and 1328:13313 "Data yang dikirim".
                if tapIfExists(app.buttons["extension.consent"]) { shot("on-turnOnExtension-agreed") }
                if tapIfExists(app.buttons["extension.dataSent"]) {
                    _ = app.buttons["dataSent.done"].waitForExistence(timeout: 5)
                    settle()
                    shot("on-dataSent-sheet")
                }
            default: break
            }
        }
    }

    // MARK: Home

    @MainActor
    func testHome() {
        launch(guardian(family: true) + ["-debug.tab", "shield"])
        shot("home-guardian")
        scrollShot("home-guardian-2")

        launch(guardian(family: false) + ["-debug.tab", "shield", "-UITestCheckStats", "YES"])
        shot("home-pribadi")
        scrollShot("home-pribadi-2")

        launch(protected() + ["-debug.tab", "shield"])
        shot("home-protected")
        scrollShot("home-protected-2")

        guard scenario == "figma" else { return }
        launch(guardian(family: true, scenario: "mixedVerdicts") + ["-debug.tab", "shield"])
        shot("home-guardian-pending")
        launch(guardian(family: true, scenario: "empty") + ["-debug.tab", "shield"])
        shot("home-guardian-empty")
        // Every family site decided: no card, the people row shows (435:20373).
        launch(guardian(family: true, scenario: "allSafe") + ["-debug.tab", "shield"])
        shot("home-guardian-members")
    }

    /// Home parity (Pribadi 435:20058 / 1382:10567, protected/Home 1115:17162 … 1373:12752): one launch per frame,
    /// the top of the page, then two fixed drags (held, so no momentum) for what is under it.
    @MainActor
    func testHomeStates() {
        guard scenario == "figma" else { return }
        let states: [(String, [String])] = [
            ("pribadi", guardian(family: false, scenario: "homePribadi")),
            ("pribadi-cta", guardian(family: false, scenario: "homePribadiAlone")),
            ("prot-quiet", protected(scenario: "protectedQuiet")),
            ("prot-blocked", protected(scenario: "protectedBlocked")),
            ("prot-blocked-scam", protected(scenario: "protectedBlockedScam")),
            ("prot-warning-scam", protected(scenario: "protectedWarningScam")),
            ("prot-warning", protected(scenario: "protectedWarning")),
            ("prot-alone", protected(scenario: "protectedAlone")),
            ("prot-warning-safe", protected(scenario: "protectedWarningSafe")),
            ("prot-blocked-safe", protected(scenario: "protectedBlockedSafe")),
        ]
        for (name, arguments) in states {
            let app = launch(arguments + ["-debug.tab", "shield", "-UITestReduceMotion", "YES"])
            shot("hs-\(name)-0")
            for page in 1...2 {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
                Thread.sleep(forTimeInterval: 1)
                shot("hs-\(name)-\(page)")
            }
        }
    }

    // MARK: Activity

    @MainActor
    func testActivity() {
        var app = launch(guardian(family: true) + ["-debug.tab", "activity"])
        shot("act-guardian")
        scrollShot("act-guardian-2")
        if tapIfExists(app.descendants(matching: .any)["filter.warning"].firstMatch) { shot("act-guardian-warning") }
        if tapIfExists(app.descendants(matching: .any)["filter.blocked"].firstMatch) { shot("act-guardian-blocked") }
        // Figma "Picker" (416:9208) and "Only one selected" (416:8989): opened by the DEBUG launch flags,
        // the menu is an overlay the UI test can't reliably open by tapping.
        launch(guardian(family: true) + ["-debug.tab", "activity", "-debug.activityPicker", "YES"])
        shot("act-guardian-picker")
        launch(guardian(family: true) + ["-debug.tab", "activity", "-debug.activityPerson", "dev_syahnaz"])
        shot("act-guardian-one")

        app = launch(guardian(family: false) + ["-debug.tab", "activity"])
        shot("act-pribadi")
        if tapIfExists(app.descendants(matching: .any)["filter.warning"].firstMatch) { shot("act-pribadi-warning") }

        app = launch(protected() + ["-debug.tab", "activity"])
        shot("act-protected")
        scrollShot("act-protected-2")
        // Figma 450:8574 / 450:8657: the v2 (guardian notes) list filtered.
        app = launch(protected() + ["-debug.tab", "activity", "-debug.activityFilter", "warning"])
        shot("act-protected-warning")
        app = launch(protected() + ["-debug.tab", "activity", "-debug.activityFilter", "blocked"])
        shot("act-protected-blocked")

        guard scenario == "figma" else { return }
        app = launch(guardian(family: false, scenario: "empty") + ["-debug.tab", "activity", "-UITestCheckStats", "YES"])
        shot("act-empty-all")
        if tapIfExists(app.descendants(matching: .any)["filter.warning"].firstMatch) { shot("act-empty-warning") }
        if tapIfExists(app.descendants(matching: .any)["filter.blocked"].firstMatch) { shot("act-empty-blocked") }
        launch(guardian(family: false, scenario: "empty") + [
            "-debug.tab", "activity", "-UITestCheckStats", "YES", "-UITestExtensionStatus", "offTwoDays",
        ], extensionActive: false)
        shot("act-off")
    }

    // MARK: Detail

    @MainActor
    func testDetail() {
        let cases: [(String, String, [String])]
        switch scenario {
        case "figma":
            cases = [
                ("dt-blocked", "figma-blocked-92", guardian(family: true)),
                ("dt-warning", "figma-warning-72", guardian(family: true)),
                ("dt-validated", "mixed-blocked-notsafe", guardian(family: true, scenario: "mixedVerdicts")),
                ("dt-safe", "mixed-warning-safe", guardian(family: true, scenario: "mixedVerdicts")),
                ("dt-unchecked", "mixed-blocked-none", guardian(family: true, scenario: "mixedVerdicts")),
                ("dt-pribadi", "figma-me-1", guardian(family: false)),
                ("dt-protected", "maria-1", protected()),
                // Figma 487:5990 "Waspada (v2, tanpa pemilik)": own warning, no owner chip, no buttons.
                ("dt-protected-warning", "maria-2", protected()),
                ("dt-protected-verdict", "maria-3", protected()),
                ("dt-protected-safe", "maria-5", protected()),
            ]
        case "edge":
            cases = [("dt-long", "edge-long", guardian(family: true)), ("dt-one-signal", "edge-one-signal", guardian(family: true))]
        case "heavy":
            cases = [("dt-first", "heavy-0", guardian(family: true))]
        case "allSafe":
            cases = [("dt-safe", "figma-blocked-92", guardian(family: true))]
        case "corpus":
            // Highest score, the two real scam pages, and a legit page the detector blocks (false positive).
            cases = [
                ("dt-top", "corpus-syn-ovo-upgrade-premier", guardian(family: true)),
                ("dt-real-bsi", "corpus-cusbsi-bsi-cash-management", guardian(family: true)),
                ("dt-real-lphone", "corpus-lphone-login", guardian(family: true)),
                ("dt-false-positive", "corpus-trap-fintech-kyc-sah", guardian(family: true)),
            ]
        default:
            cases = []
        }
        for (name, scanId, args) in cases {
            let app = launch(args + ["-debug.detail", scanId, "-debug.replicaFixture", "YES"])
            _ = app.descendants(matching: .any)["detail.header"].waitForExistence(timeout: 10)
            settle()
            shot(name)
            scrollShot("\(name)-2")
            scrollShot("\(name)-3")
        }
    }

    // MARK: Profile

    @MainActor
    func testProfile() {
        var app = launch(guardian(family: true) + ["-debug.profile", "YES"])
        shot("pf-guardian")
        scrollShot("pf-guardian-2")
        scrollShot("pf-guardian-3")

        guard scenario == "figma" else {
            launch(guardian(family: false) + ["-debug.profile", "YES", "-UITestCheckStats", "YES"])
            shot("pf-pribadi")
            return
        }

        app = launch(guardian(family: true) + ["-debug.profile", "YES"])
        if tapIfExists(app.descendants(matching: .any)["profile.member.dev_syahnaz"].firstMatch) {
            settle()
            shot("pf-member")
            scrollShot("pf-member-2")
            if tapIfExists(app.buttons["member.disconnect"]) { shot("pf-member-disconnect") }
        }

        launch(guardian(family: false) + ["-debug.profile", "YES", "-UITestCheckStats", "YES"])
        shot("pf-pribadi")
        scrollShot("pf-pribadi-2")

        launch(protected() + ["-debug.profile", "YES", "-UITestCheckStats", "YES"])
        shot("pf-protected")
        scrollShot("pf-protected-2")

        // Protected pages (Figma 455:9515 "Akun Tertaut", 462:11043 Kelola profil, 455:9627 Notifikasi).
        for (name, id) in [
            ("pf-protected-connection", "profile.connectedPill"), ("pf-protected-manage", "Kelola profil"),
            ("pf-protected-notifications", "Notifikasi"),
        ] {
            app = launch(protected() + ["-debug.profile", "YES"])
            let opened = id.hasPrefix("profile.") ? tapIfExists(app.buttons[id]) : tapText(app, id)
            if opened { shot(name) } else { XCTFail("no row \(id)") }
        }

        launch(guardian(family: true, scenario: "empty") + ["-debug.profile", "YES"])
        shot("pf-guardian-empty")

        for (name, label) in [
            ("pf-mode", "Mode akun"), ("pf-manage", "Kelola profil"), ("pf-notifications", "Notifikasi"),
            ("pf-language", "Bahasa"), ("pf-theme", "Tema"), ("pf-accessibility", "Aksesibilitas"), ("pf-about", "Tentang Shoo"),
        ] {
            app = launch(guardian(family: true) + ["-debug.profile", "YES"])
            if tapText(app, label) {
                settle()
                shot(name)
            } else {
                XCTFail("no row \(label)")
            }
        }
    }

    // MARK: Helpers

    private func guardian(family: Bool, scenario: String? = nil) -> [String] {
        ["-settings.mode", "guardian", "-settings.familyModeOn", family ? "YES" : "NO", "-mock.scenario", scenario ?? self.scenario]
    }

    private func protected(scenario: String? = nil) -> [String] {
        ["-settings.mode", "protected", "-mock.scenario", scenario ?? self.scenario]
    }

    @MainActor
    @discardableResult
    private func launch(_ arguments: [String], onboarded: Bool = true, extensionActive: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-UITestMock", "YES", "-UITestSkipSplash", "YES", "-settings.language", "id", "-UITestNotifications", "granted",
        ]
            + (onboarded ? ["-settings.onboardingCompleted", "YES"] : [])
            + (extensionActive ? ["-UITestExtensionActive", "YES"] : [])
            + arguments
        // Figma times are WIB; the simulator follows the Mac's zone otherwise.
        app.launchEnvironment["TZ"] = "Asia/Jakarta"
        app.launch()
        settle()
        // GD-01 "Notifikasi mati" popup covers Home and Activity once per launch.
        // An alert button keeps the alert's identifier, not its own: find it by its title too.
        let notNow = app.alerts.buttons["Nanti saja"].exists ? app.alerts.buttons["Nanti saja"] : app.buttons["reminder.notNow"]
        if notNow.exists {
            notNow.tap()
            settle()
        }
        return app
    }

    /// Mock latency is 300 ms; give lists, images and the page copy time to draw.
    private func settle() {
        Thread.sleep(forTimeInterval: 2)
    }

    /// Drags the page down past the keyboard (`scrollDismissesKeyboard(.interactively)`): the number pad
    /// has no return key.
    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    @MainActor
    private func scrollShot(_ name: String) {
        XCUIApplication().swipeUp(velocity: .slow)
        Thread.sleep(forTimeInterval: 1)
        shot(name)
    }

    @MainActor
    private func tapIfExists(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 3), element.isHittable else { return false }
        element.tap()
        settle()
        return true
    }

    /// Taps a row by its visible text, scrolling down up to five times to reach it.
    @MainActor
    private func tapText(_ app: XCUIApplication, _ text: String) -> Bool {
        for _ in 0..<6 {
            for element in [app.buttons[text].firstMatch, app.staticTexts[text].firstMatch] where element.exists && element.isHittable {
                element.tap()
                settle()
                return true
            }
            app.swipeUp(velocity: .slow)
        }
        return false
    }

    @MainActor
    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = prefix + name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["QA_SHOT_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)\(name).png")
            try? screenshot.pngRepresentation.write(to: url)
        }
    }
}
