import SwiftUI

/// One reason on the Detail screen (DT-04): "Domain age 3 days · +30%".
struct Evidence: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    let weight: Int

    /// The heaviest `limit` signals; equal weights keep the contract's order.
    /// Guardian reads `label`, Protected reads the simpler `labelSimple`.
    static func top(_ signals: [Signal], mode: UserMode, language: AppLanguage, limit: Int = 3) -> [Evidence] {
        signals.enumerated()
            .sorted { ($0.element.weight, $1.offset) > ($1.element.weight, $0.offset) }
            .prefix(limit)
            .map { index, signal in
                let text = mode == .guardian ? signal.label : signal.labelSimple
                return Evidence(id: "\(index)-\(signal.id)", text: text.text(for: language.code), weight: signal.weight)
            }
    }

    /// "+30%".
    func weightText(language: AppLanguage) -> String {
        "+" + Formatters.percent(weight, language: language)
    }

    /// "Domain age 3 days · +30%" as shown.
    func line(language: AppLanguage) -> String {
        "\(text) · \(weightText(language: language))"
    }

    /// VoiceOver: "Domain age 3 days, adds 30 percent to the risk score".
    func spokenLine(language: AppLanguage) -> String {
        L10n.string("\(text), adds \(weight) percent to the risk score", language: language)
    }
}

/// DT-04 list of reasons.
struct EvidenceList: View {
    let items: [Evidence]

    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why Shoo flagged this")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text(verbatim: item.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: item.weightText(language: language))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: item.spokenLine(language: language)))
                .accessibilityIdentifier("detail.evidence.\(index)")
            }
        }
    }
}
