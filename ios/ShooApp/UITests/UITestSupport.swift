import XCTest

/// Fase 23a (C2): one way to launch the mock app, wait and tap in every UI test, so a slow CI runner
/// doesn't fail a test that passes locally (flakes F3–F6, `plan/alief/fase-23-ci-reliability.md`).
enum UITestTimeout {
    /// A screen or element that should appear. `waitForExistence` returns as soon as it exists, so a
    /// longer limit costs nothing when the test passes.
    static let screen: TimeInterval = 10
    /// Something that may or may not show (an optional popup): short on purpose.
    static let optional: TimeInterval = 3
}

extension XCUIApplication {
    /// Launches the app on `MockRepository` (`-UITestMock YES`) with the endless shield animations and
    /// UIKit transitions off (`-UITestReduceMotion YES`, K2), from clean settings (`-UITestReset YES`).
    /// `reset: false` only for a relaunch inside the same test that checks what was saved.
    /// Not for screenshots or the accessibility audit: those need the real look.
    @MainActor
    static func mock(_ arguments: [String] = [], reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMock", "YES", "-UITestReduceMotion", "YES"]
        if reset { app.launchArguments += ["-UITestReset", "YES"] }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    /// GD-01: with notifications denied the Guardian gets a "Notifications are off" popup once per launch.
    /// It can cover the screen or swallow a tap, so close it when it shows.
    @MainActor
    func dismissNotificationsReminder(timeout: TimeInterval = UITestTimeout.optional, file: StaticString = #filePath, line: UInt = #line) {
        let notNow = alerts.buttons["Not now"].firstMatch
        if notNow.waitForExistence(timeout: timeout) { notNow.tap() }
        // No other alert may cover the screen either.
        XCTAssertTrue(alerts.firstMatch.waitForNonExistence(timeout: UITestTimeout.screen), debugDescription, file: file, line: line)
    }

    /// Taps `element`, then waits for `condition`. A tap during a push or pop transition can be lost (F3, F4),
    /// so it taps again (at most `retries` times) while `element` is still there. Only for taps that are
    /// safe to repeat: Back, opening a pushed screen or a sheet. Each retap shows in the xcresult. With
    /// `-UITestReduceMotion` transitions are instant, so a retap after `UITestTimeout.screen` means the
    /// first tap was lost, not that the next screen is still sliding in.
    @MainActor
    func tap(_ element: XCUIElement, until condition: XCUIElement, retries: Int = 2, file: StaticString = #filePath, line: UInt = #line) {
        element.tapWhenHittable(file: file, line: line)
        for attempt in 0...retries {
            if condition.waitForExistence(timeout: UITestTimeout.screen) { return }
            guard attempt < retries, element.exists else { break }
            XCTContext.runActivity(named: "Retap \(element.identifier) (attempt \(attempt + 2))") { _ in
                element.tapWhenHittable(file: file, line: line)
            }
        }
        XCTFail("\(condition) did not appear after tapping \(element)\n\(debugDescription)", file: file, line: line)
    }
}

extension XCUIElement {
    /// Waits until the element exists and can be tapped, then taps it. A plain `tap()` right after
    /// `waitForExistence` can land while a transition still covers it. Some elements never report
    /// `isHittable` though they take taps (toolbar buttons on iOS 26, e.g. `profileButton`): after
    /// `hittableWait` those are tapped anyway, and `tap(_:until:)` checks the result.
    /// Such a button can exist before it has a frame (CI on #285: "Activation point invalid and no suggested
    /// hit points based on element frame"), so it is tapped by coordinate only once its frame is laid out.
    @MainActor
    func tapWhenHittable(timeout: TimeInterval = UITestTimeout.screen, hittableWait: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line) {
        guard waitForExistence(timeout: timeout) else {
            XCTFail("\(self) never appeared", file: file, line: line)
            return
        }
        // The frame first: asking `isHittable` of a button with no frame yet records "Failed to determine
        // hittability … Activation point invalid" as a test failure (CI on #362 and #363, `profileButton`).
        let laidOut = XCTNSPredicateExpectation(predicate: NSPredicate { element, _ in
            guard let element = element as? XCUIElement, element.exists else { return false }
            return element.frame.width > 0 && element.frame.height > 0
        }, object: self)
        guard XCTWaiter().wait(for: [laidOut], timeout: timeout) == .completed else {
            XCTFail("\(self) never got a frame to tap", file: file, line: line)
            return
        }
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: self)
        if XCTWaiter().wait(for: [hittable], timeout: hittableWait) == .completed {
            tap()
            return
        }
        XCTContext.runActivity(named: "\(identifier) not reported hittable, tapping its frame") { _ in }
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
