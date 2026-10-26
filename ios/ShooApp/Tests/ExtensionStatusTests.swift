import Foundation
import Testing
@testable import Shoo

struct ExtensionStatusTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func neverSeenIsOff() {
        #expect(ExtensionStatus.evaluate(lastSeen: nil, now: now) == .off(lastSeen: nil))
    }

    @Test func recentHeartbeatIsActive() {
        let seen = now.addingTimeInterval(-60)
        #expect(ExtensionStatus.evaluate(lastSeen: seen, now: now) == .active(lastSeen: seen))
    }

    @Test func heartbeatOlderThanWindowIsOff() {
        let seen = now.addingTimeInterval(-AppGroup.extensionActiveWindow)
        #expect(ExtensionStatus.evaluate(lastSeen: seen, now: now) == .off(lastSeen: seen))
    }

    @Test func narrowedSafariAccessIsOffEvenWithARecentHeartbeat() {
        let seen = now.addingTimeInterval(-60)
        #expect(ExtensionStatus.evaluate(lastSeen: seen, allSites: false, now: now) == .off(lastSeen: seen))
        #expect(ExtensionStatus.evaluate(lastSeen: seen, allSites: true, now: now) == .active(lastSeen: seen))
        // Missing = unknown, treated as every site (contracts/app-group-keys.md).
        #expect(ExtensionStatus.evaluate(lastSeen: seen, allSites: nil, now: now) == .active(lastSeen: seen))
    }

    @Test func readsTheAllSitesKey() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        defaults.set(now.addingTimeInterval(-10), forKey: AppGroup.Key.extensionLastSeenAt)
        #expect(ExtensionStatus.current(defaults: defaults, now: now).isActive)
        defaults.set(false, forKey: AppGroup.Key.extensionAllSites)
        #expect(!ExtensionStatus.current(defaults: defaults, now: now).isActive)
        defaults.set(true, forKey: AppGroup.Key.extensionAllSites)
        #expect(ExtensionStatus.current(defaults: defaults, now: now).isActive)
    }

    @Test func readsTheAppGroupKey() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        #expect(!ExtensionStatus.current(defaults: defaults, now: now).isActive)
        defaults.set(now.addingTimeInterval(-10), forKey: AppGroup.Key.extensionLastSeenAt)
        #expect(ExtensionStatus.current(defaults: defaults, now: now).isActive)
    }
}
