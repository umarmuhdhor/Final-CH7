import Foundation
import Testing
@testable import Shoo

/// The backend's Live Activity push (contracts/api.md "Live score (Dynamic Island)") must decode into
/// `ScoreActivityAttributes` on the phone, or the island never shows. Keys are a contract.
struct ScoreActivityAttributesTests {
    private let contentState = #"{"domain":"hadiah-gratis.xyz","score":60,"isAnalyzing":false,"isBlocked":false}"#

    @Test func decodesTheContractContentState() throws {
        let state = try JSONDecoder().decode(ScoreActivityAttributes.ContentState.self, from: Data(contentState.utf8))
        #expect(state == .init(domain: "hadiah-gratis.xyz", score: 60, isAnalyzing: false, isBlocked: false))
        #expect(state.tone == .danger)
    }

    @Test func attributesAreEmptyAndIgnoreExtraKeys() throws {
        // Contract: `attributes: {}`. #356 also sends `{ domain }`: an extra key must not break decoding.
        _ = try JSONDecoder().decode(ScoreActivityAttributes.self, from: Data("{}".utf8))
        _ = try JSONDecoder().decode(ScoreActivityAttributes.self, from: Data(#"{"domain":"hadiah-gratis.xyz"}"#.utf8))
    }

    @Test func toneFollowsTheExtensionBands() {
        func tone(_ score: Int, blocked: Bool = false) -> ScoreActivityAttributes.Tone {
            ScoreActivityAttributes.ContentState(domain: "a.com", score: score, isAnalyzing: false, isBlocked: blocked).tone
        }
        #expect(tone(29) == .safe)
        #expect(tone(30) == .warning)
        #expect(tone(50) == .danger)
        #expect(tone(80) == .blocked)
        #expect(tone(10, blocked: true) == .blocked)
    }

    /// #383: the island's colour follows the status the phone sent, not fixed score bands.
    @Test func toneFollowsTheStatusWhenThePushCarriesIt() throws {
        func tone(_ score: Int, _ status: String) -> ScoreActivityAttributes.Tone {
            ScoreActivityAttributes.ContentState(domain: "a.com", score: score, isAnalyzing: false, isBlocked: status == "blocked", status: status).tone
        }
        #expect(tone(35, "normal") == .safe) // warnAt moved to 40: a 35 is not a warning
        #expect(tone(75, "blocked") == .blocked) // blockAt moved to 70: a 75 is blocked
        #expect(tone(40, "warning") == .warning)
        #expect(tone(60, "warning") == .danger)
        let json = #"{"domain":"a.com","score":75,"isAnalyzing":false,"isBlocked":true,"status":"blocked"}"#
        let state = try JSONDecoder().decode(ScoreActivityAttributes.ContentState.self, from: Data(json.utf8))
        #expect(state.status == "blocked")
        #expect(state.tone == .blocked)
    }
}
