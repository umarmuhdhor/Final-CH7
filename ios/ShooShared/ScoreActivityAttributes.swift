import ActivityKit
import Foundation

/// Live Activity shown in the Dynamic Island while a page is being scored (EX-03).
/// Only the running score — warnings and blocks stay in-page (EX-04, EX-06).
struct ScoreActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var score: Int
        var isAnalyzing: Bool
    }

    var domain: String
}
