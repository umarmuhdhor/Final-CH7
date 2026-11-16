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
        /// #486: why a low score must not read "Aman", the same words as the in-page pill. `"offline_check"`: the
        /// online check was skipped or failed (#379). `"marked_safe"`: a Guardian marked this link safe (#369).
        /// Optional, like `status`: a push without it still decodes.
        var label: String? = nil
        /// #486: the extension's second warning (`/config/public`, middle of the warning band when `warnAt` ≥ 50).
        /// Optional: without it, 50.
        var secondWarning: Int? = nil

        /// Follows `status`, so a moved `/config/public` threshold can't colour a warning green or a block orange.
        /// Inside a warning, `secondWarning`+ is the darker "danger" tone, the same split as the pill.
        var tone: Tone {
            switch status {
            case "blocked": return .blocked
            case "normal": return isBlocked ? .blocked : .safe
            case "warning": return score >= (secondWarning ?? 50) ? .danger : .warning
            default:
                if isBlocked || score >= 80 { return .blocked }
                if score >= 50 { return .danger }
                if score >= 30 { return .warning }
                return .safe
            }
        }

        /// What the island's status line says. Never `.tone(.safe)` ("Aman") when the pill says it was not
        /// checked online or that a Guardian marked it safe (#486): the island never says more than the pill.
        var headline: Headline {
            if isAnalyzing { return .analyzing }
            let current = self.tone
            switch label {
            case "marked_safe" where current == .safe: return .markedSafe
            case "offline_check" where current == .safe: return .offlineCheck
            default: return .tone(current)
            }
        }
    }

    enum Tone {
        case safe, warning, danger, blocked
    }

    enum Headline: Equatable {
        case analyzing, offlineCheck, markedSafe
        case tone(Tone)
    }
}
