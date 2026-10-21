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

    @ViewBuilder
    private func button(_ value: Verdict.Value, title: LocalizedStringKey, systemImage: String, tint: Color) -> some View {
        let selected = current == value
        Button {
            onDecide(value)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .tint(tint)
        .modify { view in
            if selected {
                view.buttonStyle(.borderedProminent)
            } else {
                view.buttonStyle(.bordered)
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension View {
    func modify<Content: View>(@ViewBuilder _ transform: (Self) -> Content) -> some View {
        transform(self)
    }
}
