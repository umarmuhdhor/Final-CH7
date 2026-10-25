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

    @Test func safariSwitchOffIsOffEvenWithARecentHeartbeat() {
        let seen = now.addingTimeInterval(-60)
        #expect(ExtensionStatus.evaluate(lastSeen: seen, enabled: false, now: now) == .off(lastSeen: seen))
        #expect(ExtensionStatus.evaluate(lastSeen: nil, enabled: false, now: now) == .off(lastSeen: nil))
    }

    @Test func safariSwitchOnIsActiveBeforeAnyHeartbeat() {
        // ON-04: back from Settings, no page opened yet.
        #expect(ExtensionStatus.evaluate(lastSeen: nil, enabled: true, now: now) == .active(lastSeen: nil))
        let old = now.addingTimeInterval(-AppGroup.extensionActiveWindow * 2)
        #expect(ExtensionStatus.evaluate(lastSeen: old, enabled: true, now: now) == .active(lastSeen: old))
    }

    @Test func narrowedAccessStaysOffWhenTheSwitchIsOn() {
        let seen = now.addingTimeInterval(-60)
        #expect(ExtensionStatus.evaluate(lastSeen: seen, allSites: false, enabled: true, now: now) == .off(lastSeen: seen))
    }

    @Test func unknownSwitchFallsBackToTheHeartbeat() {
        let seen = now.addingTimeInterval(-60)
        #expect(ExtensionStatus.evaluate(lastSeen: seen, enabled: nil, now: now) == .active(lastSeen: seen))
        #expect(ExtensionStatus.evaluate(lastSeen: nil, enabled: nil, now: now) == .off(lastSeen: nil))
    }

    @Test func readsTheSwitchTogetherWithTheAppGroup() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        #expect(ExtensionStatus.current(defaults: defaults, enabled: true, now: now).isActive)
        defaults.set(now.addingTimeInterval(-10), forKey: AppGroup.Key.extensionLastSeenAt)
        #expect(!ExtensionStatus.current(defaults: defaults, enabled: false, now: now).isActive)
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
