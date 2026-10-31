import Foundation
import Testing
@testable import Shoo

/// PR-05 empty states (Figma 480:5490 …): which one shows, and the pill / "off since" texts.
struct ActivityEmptyStateTests {
    private let jakarta = TimeZone(identifier: "Asia/Jakarta")!
    /// 29 Oct 2026, 14:00 WIB.
    private let now = Date(timeIntervalSince1970: 1_793_257_200)

    @Test(arguments: [
        (ActivityFilter.all, ActivityEmptyKind.all), (.warning, .warning), (.blocked, .blocked),
    ])
    func extensionOnShowsTheFilter(filter: ActivityFilter, kind: ActivityEmptyKind) {
        #expect(ActivityEmptyKind.of(filter: filter, family: false, extensionStatus: .active(lastSeen: now)) == kind)
    }

    @Test(arguments: ActivityFilter.allCases)
    func extensionOffWinsOverEveryFilter(filter: ActivityFilter) {
        let off = ExtensionStatus.off(lastSeen: nil, reason: .switchedOff)
        #expect(ActivityEmptyKind.of(filter: filter, family: false, extensionStatus: off) == .protectionOff)
    }

    @Test func unknownStatusNeverFlashesOff() {
        #expect(ActivityEmptyKind.of(filter: .all, family: false, extensionStatus: nil) == .all)
    }

    @Test func familyActivityIgnoresThisPhonesExtension() {
        let off = ExtensionStatus.off(lastSeen: nil, reason: .notSeen)
        #expect(ActivityEmptyKind.of(filter: .blocked, family: true, extensionStatus: off) == .blocked)
    }

    @Test func allSaysTheExtensionIsOn() {
        let stats = CheckStats(checked: 1284, lastCheckedAt: now)
        #expect(ActivityEmptyText.pill(kind: .all, stats: stats, now: now, language: .indonesian, timeZone: jakarta)
            == "Ekstensi Safari aktif")
    }

    @Test func warningShowsCountAndTimeAsInFigma() {
        let lastChecked = now.addingTimeInterval(-(3 * 3600 + 18 * 60)) // 10.42 WIB
        let stats = CheckStats(checked: 1284, lastCheckedAt: lastChecked)
        #expect(ActivityEmptyText.pill(kind: .warning, stats: stats, now: now, language: .indonesian, timeZone: jakarta)
            == "1.284 situs diperiksa · terakhir 10.42 WIB")
        #expect(ActivityEmptyText.pill(kind: .blocked, stats: stats, now: now, language: .english, timeZone: jakarta)
            .hasPrefix("1,284 sites checked · last at "))
    }

    @Test func countWithoutTimeDropsTheTime() {
        let stats = CheckStats(checked: 7, lastCheckedAt: nil)
        #expect(ActivityEmptyText.pill(kind: .blocked, stats: stats, now: now, language: .indonesian, timeZone: jakarta)
            == "7 situs diperiksa")
    }

    @Test func nothingWrittenYetFallsBackToExtensionOn() {
        #expect(ActivityEmptyText.pill(kind: .warning, stats: CheckStats(), now: now, language: .english, timeZone: jakarta)
            == "Safari extension on")
    }

    @Test func offSinceAsInFigma() {
        let twoDaysAgo = now.addingTimeInterval(-2 * 86_400)
        #expect(ActivityEmptyText.offSince(twoDaysAgo, now: now, language: .indonesian) == "Mati sejak 2 hari lalu")
        #expect(ActivityEmptyText.offSince(twoDaysAgo, now: now, language: .english) == "Off for 2 days")
    }

    @Test func offSinceHiddenWhenTheExtensionNeverRan() {
        #expect(ActivityEmptyText.offSince(nil, now: now, language: .indonesian) == nil)
    }

    @Test func checkStatsReadAndClear() throws {
        let defaults = try #require(UserDefaults(suiteName: "ActivityEmptyStateTests"))
        defer { defaults.removePersistentDomain(forName: "ActivityEmptyStateTests") }
        #expect(CheckStats.current(defaults: defaults) == CheckStats())
        defaults.set(12, forKey: CheckStats.Key.checked)
        defaults.set(now, forKey: CheckStats.Key.lastCheckedAt)
        #expect(CheckStats.current(defaults: defaults) == CheckStats(checked: 12, lastCheckedAt: now))
        CheckStats.clear(defaults: defaults)
        #expect(CheckStats.current(defaults: defaults) == CheckStats())
    }
}
