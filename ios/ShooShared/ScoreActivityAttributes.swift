import ActivityKit
import Foundation

/// Live Activity shown in the Dynamic Island while a page is on screen in Safari (EX-03).
/// Only the running score — warnings and blocks stay in-page (EX-04, EX-06).
///
/// Started, updated and ended by Live Activity push from the backend (path C, #49), so the JSON keys
/// below are a contract: contracts/api.md "Live score (Dynamic Island)". Renaming one breaks decoding
/// on the phone. No attributes: one island follows the page, so the domain is part of the state.
struct ScoreActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var domain: String
        var score: Int
        var isAnalyzing: Bool
        var isBlocked: Bool

        /// Same bands as the extension (pipeline.js THRESHOLD defaults 30 / 50 / 80).
        var tone: Tone {
            if isBlocked || score >= 80 { return .blocked }
            if score >= 50 { return .danger }
            if score >= 30 { return .warning }
            return .safe
        }
    }

    enum Tone {
        case safe, warning, danger, blocked
    }
}
