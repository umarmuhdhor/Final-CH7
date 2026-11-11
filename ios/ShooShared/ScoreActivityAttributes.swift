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
        /// #383: what the phone did, `"normal"` / `"warning"` / `"blocked"` (POST /live `status`). Optional so an
        /// older backend's push still decodes; without it the tone falls back to the built-in 30 / 50 / 80 bands.
        var status: String? = nil

        /// Follows `status`, so a moved `/config/public` threshold can't colour a warning green or a block orange.
        /// Inside a warning, 50+ is the darker "danger" tone (the extension's second warning, built in at 50).
        var tone: Tone {
            switch status {
            case "blocked": return .blocked
            case "normal": return isBlocked ? .blocked : .safe
            case "warning": return score >= 50 ? .danger : .warning
            default:
                if isBlocked || score >= 80 { return .blocked }
                if score >= 50 { return .danger }
                if score >= 30 { return .warning }
                return .safe
            }
        }
    }

    enum Tone {
        case safe, warning, danger, blocked
    }
}
