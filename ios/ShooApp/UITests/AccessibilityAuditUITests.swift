import XCTest

/// Fase 06Q (QA-A): Xcode's accessibility audit (contrast, labels, hit areas, Dynamic Type, clipped text)
/// on every Fase A screen, both languages. Each issue is printed as `AUDIT|…` for the QA report.
/// Takes ~7 minutes, so it only runs on request:
/// `TEST_RUNNER_SHOO_A11Y_AUDIT=1 xcodebuild test … -only-testing:ShooAppUITests/AccessibilityAuditUITests`.
final class AccessibilityAuditUITests: XCTestCase {
    private static let done = ["-settings.onboardingCompleted", "YES", "-settings.onboardingConnectPassed", "YES"]
    private static let guardian = done + ["-settings.mode", "guardian", "-UITestNotifications", "granted"]
    private static let protected = done + ["-settings.mode", "protected"]
    private static let active = ["-UITestExtensionActive", "YES"]

    /// Screen name → launch arguments (same set as the QA-A screenshots).
    private static let screens: [(String, [String])] = [
        ("ON01-splash", ["-UITestReset", "YES"]),
        ("ON02-name", ["-UITestReset", "YES", "-debug.onboardingStep", "name"]),
        ("ON03-mode", ["-UITestReset", "YES", "-debug.onboardingStep", "mode"]),
        ("ON03-greeting", ["-UITestReset", "YES", "-settings.mode", "guardian", "-debug.onboardingStep", "greeting"]),
        ("ON03-connect", ["-UITestReset", "YES", "-settings.mode", "protected", "-debug.onboardingStep", "connect"]),
        ("ON04-extension", ["-UITestReset", "YES", "-settings.mode", "guardian", "-debug.onboardingStep", "turnOnExtension"]),
        ("ON05-notifications", ["-UITestReset", "YES", "-settings.mode", "guardian", "-debug.onboardingStep", "notifications"]),
        ("PR04-shield-on", protected + active),
        ("PR04-shield-off", protected),
        ("PR05-activity", protected + active + ["-debug.tab", "activity"]),
        ("PR05-activity-empty", protected + active + ["-debug.tab", "activity", "-mock.scenario", "empty"]),
        ("GD01-self-on", guardian + active + ["-settings.familyModeOn", "NO"]),
        ("GD01-self-off", guardian + ["-settings.familyModeOn", "NO"]),
        ("GD03-family-3", guardian + active + ["-settings.familyModeOn", "YES", "-mock.scenario", "threeMembers"]),
        ("GD03-family-0", guardian + active + ["-settings.familyModeOn", "YES", "-mock.scenario", "empty"]),
        ("GD05-activity-family", guardian + active + ["-settings.familyModeOn", "YES", "-debug.tab", "activity"]),
        ("DT-warning-g", guardian + active + ["-debug.detail", "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e01"]),
        ("DT-blocked-g", guardian + active + ["-debug.detail", "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"]),
        ("DT-scam-g", guardian + active + ["-debug.detail", "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e04"]),
        ("DT-safe-g", guardian + active + ["-debug.detail", "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e05"]),
        ("DT-blocked-p", protected + active + ["-debug.detail", "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"]),
        ("PF01-guardian", guardian + active + ["-settings.familyModeOn", "YES", "-debug.profile", "YES"]),
        ("PF01-protected", protected + active + ["-debug.profile", "YES"]),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SHOO_A11Y_AUDIT"] == "1", "Audit runs on request only")
    }

    @MainActor
    func testAuditEnglish() throws {
        try audit(language: "en")
    }

    @MainActor
    func testAuditIndonesian() throws {
        try audit(language: "id")
    }

    @MainActor
    private func audit(language: String) throws {
        for (name, arguments) in Self.screens {
            let app = XCUIApplication()
            app.launchArguments = ["-UITestMock", "YES", "-settings.language", language] + arguments
            app.launch()
            // Let the mock answer and the screen settle.
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 10)
            sleep(2)
            try record(app, language: language, screen: name)
            // Text under the floating tab bar / pinned buttons is faded by the scroll edge effect;
            // a second pass after scrolling shows whether it fails in plain view too.
            app.swipeUp()
            sleep(1)
            try record(app, language: language, screen: name + "↓")
            app.terminate()
        }
    }

    @MainActor
    private func record(_ app: XCUIApplication, language: String, screen: String) throws {
        try app.performAccessibilityAudit { issue in
            let element = issue.element
            let id = element.map { "\($0.elementType.rawValue)·\($0.identifier)·\($0.label)" } ?? "-"
            print("AUDIT|\(language)|\(screen)|\(issue.auditType.rawValue)|\(id)|\(issue.compactDescription)")
            return true
        }
    }
}
