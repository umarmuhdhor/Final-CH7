import CoreGraphics
import Foundation

/// One reason on the Detail screen (DT-04): "Domain age 3 days", +30 %, the kind of signal and,
/// when the page copy marked it, where it sits on the page.
struct Evidence: Identifiable, Equatable, Sendable {
    let id: String
    /// Position in the list, heaviest first (`detail.evidence.N`).
    let index: Int
    let signalId: String
    let text: String
    let weight: Int
    /// This reason's weight and every heavier one before it, for the stacked contribution bar.
    let runningWeights: [Int]
    /// Areas on the page for this signal (`marks` in the page copy's meta), in page CSS px.
    var highlights: [CGRect] = []

    var kind: SignalKind { SignalKind(signalId: signalId) }

    /// The heaviest `limit` signals; equal weights keep the contract's order.
    /// Guardian reads `label`, Protected reads the simpler `labelSimple`.
    static func top(
        _ signals: [Signal], mode: UserMode, language: AppLanguage, marks: [ReplicaMark] = [], limit: Int = 3
    ) -> [Evidence] {
        let picked = signals.enumerated()
            .sorted { ($0.element.weight, $1.offset) > ($1.element.weight, $0.offset) }
            .prefix(limit)
        var running: [Int] = []
        return picked.enumerated().map { position, entry in
            let (index, signal) = entry
            running.append(signal.weight)
            let text = mode == .guardian ? signal.label : signal.labelSimple
            return Evidence(
                id: "\(index)-\(signal.id)",
                index: position,
                signalId: signal.id,
                text: text.text(for: language.code),
                weight: signal.weight,
                runningWeights: running,
                highlights: marks.filter { $0.signalId == signal.id }.map(\.rect)
            )
        }
    }

    /// "+30%".
    func weightText(language: AppLanguage) -> String {
        "+" + Formatters.percent(weight, language: language)
    }

    /// VoiceOver: "Domain age 3 days, adds 30 percent to the risk score".
    func spokenLine(language: AppLanguage) -> String {
        L10n.string("\(text), adds \(weight) percent to the risk score", language: language)
    }
}
