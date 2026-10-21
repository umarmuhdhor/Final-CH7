import SwiftUI

/// DT-06: who decided, under the label. "by you" when the viewer decided (PRD §5 Validasi).
enum VerdictNote {
    static func text(for verdict: Verdict, viewerDeviceId: String?, language: AppLanguage) -> String {
        let name = verdict.byName
        switch (verdict.value, verdict.byDeviceId == viewerDeviceId) {
        case (.notSafe, true): return L10n.string("Verified scam by you", language: language)
        case (.safe, true): return L10n.string("Marked safe by you", language: language)
        case (.notSafe, false): return L10n.string("Verified scam by \(name)", language: language)
        case (.safe, false): return L10n.string("Marked safe by \(name)", language: language)
        }
    }
}

/// The note as shown under the status chip.
struct VerdictNoteView: View {
    let text: String
    let value: Verdict.Value

    var body: some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: value == .notSafe ? "xmark.octagon.fill" : "checkmark.seal.fill")
                .foregroundStyle(value == .notSafe ? Color.red : Color.green)
        }
        .font(.subheadline.weight(.medium))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.verdictNote")
    }
}
