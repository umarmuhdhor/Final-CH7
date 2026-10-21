import Foundation
import os

/// Thin wrapper around `os.Logger` (SECURITY §3 P6).
/// The event name is public; every value passed with it is `.private` (redacted in release logs).
/// Never log tokens, `Authorization` headers or screenshots — not even as a private value.
struct AppLogger: Sendable {
    let logger: Logger

    init(category: String) {
        logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Shoo", category: category)
    }

    func debug(_ event: StaticString) {
        logger.debug("\(event.description, privacy: .public)")
    }

    func debug(_ event: StaticString, _ value: String) {
        logger.debug("\(event.description, privacy: .public): \(value, privacy: .private)")
    }

    func info(_ event: StaticString) {
        logger.info("\(event.description, privacy: .public)")
    }

    func info(_ event: StaticString, _ value: String) {
        logger.info("\(event.description, privacy: .public): \(value, privacy: .private)")
    }

    func error(_ event: StaticString) {
        logger.error("\(event.description, privacy: .public)")
    }

    func error(_ event: StaticString, _ value: String) {
        logger.error("\(event.description, privacy: .public): \(value, privacy: .private)")
    }

    func error(_ event: StaticString, _ error: any Error) {
        logger.error("\(event.description, privacy: .public): \(String(describing: error), privacy: .private)")
    }
}

/// Loggers per area. Use these instead of `print`.
enum Log {
    static let app = AppLogger(category: "app")
    static let data = AppLogger(category: "data")
    static let ui = AppLogger(category: "ui")
}
