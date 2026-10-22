import Foundation
import Testing
@testable import Shoo

struct ComponentLogicTests {
    @Test(arguments: [
        (0, ScoreLevel.normal), (29, .normal), (30, .firstWarning), (49, .firstWarning),
        (50, .secondWarning), (79, .secondWarning), (80, .blocked), (100, .blocked),
    ])
    func scoreLevelFollowsPRDThresholds(score: Int, expected: ScoreLevel) {
        #expect(ScoreLevel(score: score) == expected)
    }

    @Test(arguments: [
        ("warning-41", ScanBadge.warning),
        ("blocked-92", .blocked),
        ("blocked-verified-scam", .verifiedScam),
        ("blocked-marked-safe", .markedSafe),
    ])
    func badgeFromScan(fixture: String, expected: ScanBadge) throws {
        let url = try #require(Bundle.main.url(forResource: fixture, withExtension: "json"))
        let scan = try JSONDecoder.shoo.decode(ScanResult.self, from: Data(contentsOf: url))
        #expect(ScanBadge(scan: scan) == expected)
    }

    @Test func twelveDistinctAvatars() {
        #expect(AvatarCatalog.ids.count == 12)
        #expect(AvatarCatalog.ids.first == "avatar_01")
        #expect(AvatarCatalog.ids.last == "avatar_12")
        let symbols = Set(AvatarCatalog.ids.map { AvatarCatalog.avatar(for: $0).symbol })
        #expect(symbols.count == 12)
        #expect(AvatarCatalog.avatar(for: "avatar_99") == AvatarCatalog.fallback)
    }

    @Test(arguments: [("bca-verifikasi.site", "B"), ("www.p0stindonesia.com", "P"), ("123.example", "E"), ("", "?")])
    func siteMonogram(domain: String, expected: String) {
        #expect(SiteIcon.monogram(for: domain) == expected)
    }
}
