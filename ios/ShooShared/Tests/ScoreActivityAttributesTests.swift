import Foundation
import Testing
@testable import Shoo

// TODO(#555): delete with ScoreActivityAttributes.swift once the app PR for #555 is merged (EX-03 dropped).

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

    /// #486: a failed online check or a link marked safe never reads "Aman" on the island.
    @Test func labelledLowScoreNeverReadsSafe() throws {
        func state(_ score: Int, _ status: String, label: String?, analyzing: Bool = false) -> ScoreActivityAttributes.ContentState {
            .init(domain: "a.com", score: score, isAnalyzing: analyzing, isBlocked: false, status: status, label: label)
        }
        #expect(state(25, "normal", label: "offline_check").headline == .offlineCheck)
        #expect(state(0, "normal", label: "marked_safe").headline == .markedSafe)
        #expect(state(25, "normal", label: nil).headline == .tone(.safe))
        #expect(state(25, "normal", label: "offline_check", analyzing: true).headline == .analyzing)
        // A label never softens a warning.
        #expect(state(40, "warning", label: "offline_check").headline == .tone(.warning))
        #expect(state(25, "normal", label: "something_new").headline == .tone(.safe))

        let json = #"{"domain":"a.com","score":25,"isAnalyzing":false,"isBlocked":false,"status":"normal","label":"offline_check"}"#
        let decoded = try JSONDecoder().decode(ScoreActivityAttributes.ContentState.self, from: Data(json.utf8))
        #expect(decoded.label == "offline_check")
        #expect(decoded.headline != .tone(.safe))
    }

    /// #486: the warning split follows the extension's second warning, not a fixed 50.
    @Test func dangerFollowsSecondWarning() throws {
        func tone(_ score: Int, second: Int?) -> ScoreActivityAttributes.Tone {
            ScoreActivityAttributes.ContentState(domain: "a.com", score: score, isAnalyzing: false, isBlocked: false, status: "warning", secondWarning: second).tone
        }
        #expect(tone(55, second: 65) == .warning) // warnAt 50, blockAt 80 → second warning 65
        #expect(tone(65, second: 65) == .danger)
        #expect(tone(55, second: nil) == .danger) // older push: built-in 50
        let json = #"{"domain":"a.com","score":55,"isAnalyzing":false,"isBlocked":false,"status":"warning","secondWarning":65}"#
        let decoded = try JSONDecoder().decode(ScoreActivityAttributes.ContentState.self, from: Data(json.utf8))
        #expect(decoded.tone == .warning)
    }
}
