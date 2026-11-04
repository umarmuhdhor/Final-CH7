import SwiftUI

/// Score bands from PRD §5 (`ScoreThreshold`, lead-owned). Drives ring colour and copy.
/// Built-in 30/50/80 only: the admins' thresholds (X1, `GET /config/public`) reach the extension,
/// not the app. Screens show the scan's `status` as the extension decided it (contracts/api.md
/// "Score thresholds"); this enum only colours `ScoreRing` (component gallery) and mock data.
enum ScoreLevel: Equatable, Sendable {
    /// 0–29: nothing shown, nothing sent.
    case normal
    /// 30–49: first popup.
    case firstWarning
    /// 50–79: second popup.
    case secondWarning
    /// ≥ 80: block screen.
    case blocked

    init(score: Int) {
        switch score {
        case ScoreThreshold.blocked...: self = .blocked
        case ScoreThreshold.secondWarning...: self = .secondWarning
        case ScoreThreshold.firstWarning...: self = .firstWarning
        default: self = .normal
        }
    }

    var color: Color {
        switch self {
        case .normal: .green
        case .firstWarning: .yellow
        case .secondWarning: .orange
        case .blocked: .red
        }
    }
}
