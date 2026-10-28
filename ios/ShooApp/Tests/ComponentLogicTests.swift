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

    /// QA-A P2-3: the Detail ring grows with Dynamic Type only up to its cap, so link and evidence stay in view.
    @Test(arguments: [
        (CGFloat(1), CGFloat(2), CGFloat(160)), (1.2, 2, 192), (3, 2, 320),
        (1, 1.25, 160), (1.2, 1.25, 192), (3, 1.25, 200), (0.8, 1, 128), (3, 1, 160),
    ])
    func scoreRingGrowsUpToItsCap(textScale: CGFloat, maxScale: CGFloat, expected: CGFloat) {
        #expect(abs(ScoreRing.side(size: 160, textScale: textScale, maxScale: maxScale) - expected) < 0.001)
    }
}
