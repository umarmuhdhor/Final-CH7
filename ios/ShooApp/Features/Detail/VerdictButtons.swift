import SwiftUI

/// DT-05 / GD-07: It's safe / Not safe. Guardian only, blocked items only, no confirmation dialog.
/// The current verdict is shown as selected; tapping the other one changes it.
struct VerdictButtons: View {
    let current: Verdict.Value?
    let isSubmitting: Bool
    let failed: Bool
    let onDecide: (Verdict.Value) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                button(.safe, title: "It's safe", systemImage: "checkmark.seal.fill", tint: .green)
                    .accessibilityIdentifier("detail.verdict.safe")
                button(.notSafe, title: "Not safe", systemImage: "xmark.octagon.fill", tint: .red)
                    .accessibilityIdentifier("detail.verdict.notSafe")
            }
            .disabled(isSubmitting)
            if failed {
                Label("Couldn't save. Check your connection and try again.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("detail.verdictError")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func button(_ value: Verdict.Value, title: LocalizedStringKey, systemImage: String, tint: Color) -> some View {
        Button {
            onDecide(value)
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(VerdictButtonStyle(tint: tint, selected: current == value))
        .accessibilityAddTraits(current == value ? .isSelected : [])
    }
}

/// Text stays `.primary` for full contrast (green or red text on a pale tint is about 2:1);
/// the colour sits on the icon and the background. The chosen verdict gets a stronger fill and
/// a border, so the selection never depends on colour alone.
private struct VerdictButtonStyle: ButtonStyle {
    let tint: Color
    let selected: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint.opacity(selected ? 0.3 : 0.12), in: shape)
            .overlay(shape.strokeBorder(tint, lineWidth: selected ? 2.5 : 0))
            .opacity(isEnabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
