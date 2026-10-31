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
        shot("on-splash-1")
        app.buttons["splash.next"].tap()
        shot("on-splash-2")
        app.buttons["splash.next"].tap()
        shot("on-splash-3")

        for step in ["name", "mode", "greeting", "connect", "invite", "turnOnExtension", "extensionOn", "notifications"] {
            app = launch(["-UITestReset", "YES", "-debug.onboardingStep", step], onboarded: false)
            shot("on-\(step)")
            switch step {
            case "name":
                let field = app.textFields["name.field"]
                if field.waitForExistence(timeout: 5) {
                    field.tap()
                    field.typeText("Adhella")
                    shot("on-name-typed")
                }
            case "mode":
                for mode in ["guardian", "joinFamily", "personal"] where app.buttons["mode.\(mode)"].exists {
                    app.buttons["mode.\(mode)"].tap()
                    shot("on-mode-\(mode)")
                }
            case "connect":
                let code = app.textFields["connect.code"]
                if code.waitForExistence(timeout: 5) {
                    code.tap()
                    code.typeText("999999")
                    if app.buttons["connect.join"].exists { app.buttons["connect.join"].tap() }
                    _ = app.descendants(matching: .any)["connect.error"].waitForExistence(timeout: 5)
                    shot("on-connect-expired")
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
    }

    // MARK: Activity

    @MainActor
    func testActivity() {
        var app = launch(guardian(family: true) + ["-debug.tab", "activity"])
        shot("act-guardian")
        scrollShot("act-guardian-2")
        if tapIfExists(app.descendants(matching: .any)["filter.warning"].firstMatch) { shot("act-guardian-warning") }
        if tapIfExists(app.descendants(matching: .any)["filter.blocked"].firstMatch) { shot("act-guardian-blocked") }
        _ = tapIfExists(app.descendants(matching: .any)["filter.all"].firstMatch)
        if tapIfExists(app.descendants(matching: .any)["activity.personMenu"].firstMatch) {
            shot("act-guardian-picker")
            if tapText(app, "Syahnaz") { shot("act-guardian-one") }
        }

        app = launch(guardian(family: false) + ["-debug.tab", "activity"])
        shot("act-pribadi")
        if tapIfExists(app.descendants(matching: .any)["filter.warning"].firstMatch) { shot("act-pribadi-warning") }

        app = launch(protected() + ["-debug.tab", "activity"])
        shot("act-protected")
        scrollShot("act-protected-2")

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
        app.launchArguments = ["-UITestMock", "YES", "-settings.language", "id", "-UITestNotifications", "granted"]
            + (onboarded ? ["-settings.onboardingCompleted", "YES"] : [])
            + (extensionActive ? ["-UITestExtensionActive", "YES"] : [])
            + arguments
        // Figma times are WIB; the simulator follows the Mac's zone otherwise.
        app.launchEnvironment["TZ"] = "Asia/Jakarta"
        app.launch()
        settle()
        // GD-01 "Notifikasi mati" popup covers Home and Activity once per launch.
        let notNow = app.buttons["reminder.notNow"]
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
