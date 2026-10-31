import SwiftUI

/// Figma "Footer" of Detail (416:9255 / 416:9362 / 480:5768): the guardian's question with Aman / Bahaya
/// (GD-07, warning and blocked alike), or the card saying who verified it. "Ubah" on a safe verdict
/// brings the buttons back; a new choice replaces the old one. No confirmation dialog.
struct DetailFooter: View {
    let verdict: Verdict?
    let viewerDeviceId: String?
    let canValidate: Bool
    let failed: Bool
    /// The person who opened the site, when it isn't the viewer (the note under a safe verdict).
    let ownerName: String?
    let onDecide: (Verdict.Value) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isChanging = false
    private var language: AppLanguage { AppLanguage(locale: locale) }

    private var showsButtons: Bool { canValidate && (verdict == nil || isChanging) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsButtons {
                Text("Is this site really a scam?")
                    .activityFont(15, tracking: -0.15)
                    .foregroundStyle(DetailStyle.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                buttons
            } else if let verdict {
                VerifiedCard(
                    verdict: verdict,
                    viewerDeviceId: viewerDeviceId,
                    canChange: canValidate && verdict.value == .safe,
                    onChange: { isChanging = true }
                )
                if verdict.value == .safe, let ownerName {
                    Text("\(ownerName) still sees Shoo's warning when opening this site.")
                        .activityFont(13, rounded: true)
                        .foregroundStyle(DetailStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
            if failed {
                Label("Couldn't save. Check your connection and try again.", systemImage: "exclamationmark.triangle.fill")
                    .activityFont(13)
                    .foregroundStyle(DetailStyle.title)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("detail.verdictError")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                stops: [
                    .init(color: DetailStyle.footer.opacity(0), location: 0),
                    .init(color: DetailStyle.footer.opacity(0.96), location: 0.16),
                    .init(color: DetailStyle.footer, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
        // A saved choice from the server closes "Ubah".
        .onChange(of: verdict) { _, _ in isChanging = false }
    }

    /// Side by side; stacked at accessibility sizes so the words never wrap per letter.
    private var buttons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Button { onDecide(.safe) } label: {
                Label("Safe", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(VerdictButtonStyle(kind: .safe, selected: verdict?.value == .safe))
            .accessibilityAddTraits(verdict?.value == .safe ? .isSelected : [])
            .accessibilityIdentifier("detail.verdict.safe")
            Button { onDecide(.notSafe) } label: {
                Label("Danger", systemImage: "exclamationmark.circle.fill")
            }
            .buttonStyle(VerdictButtonStyle(kind: .notSafe, selected: verdict?.value == .notSafe))
            .accessibilityAddTraits(verdict?.value == .notSafe ? .isSelected : [])
            .accessibilityIdentifier("detail.verdict.notSafe")
        }
        .accessibilityHint(Text("Applies right away. You can change it later."))
    }
}

/// Aman: white capsule, dark text. Bahaya: red gradient with a darker rim, white text. 56 pt high.
private struct VerdictButtonStyle: ButtonStyle {
    let kind: Verdict.Value
    let selected: Bool

    @Environment(\.shooReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(VerdictLabelStyle())
            .activityFont(17, .semibold, tracking: -0.17)
            .foregroundStyle(kind == .safe ? DetailStyle.title : .white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                if kind == .safe {
                    Capsule().fill(.white)
                    Capsule().stroke(selected ? DetailStyle.title : DetailStyle.safeStroke, lineWidth: selected ? 2 : 1)
                } else {
                    Capsule().fill(LinearGradient(colors: [DetailStyle.dangerTop, DetailStyle.dangerBottom], startPoint: .bottom, endPoint: .top))
                    Capsule().stroke(DetailStyle.dangerTop, lineWidth: selected ? 3 : 1.5)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct VerdictLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title.lineLimit(2)
        }
    }
}

/// Figma "Catatan": "Diverifikasi sebagai penipuan" / "Diverifikasi aman", "oleh Adhella · Baru saja".
private struct VerifiedCard: View {
    let verdict: Verdict
    let viewerDeviceId: String?
    let canChange: Bool
    let onChange: () -> Void

    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage(locale: locale) }
    private var isScam: Bool { verdict.value == .notSafe }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isScam ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isScam ? DetailStyle.scamIcon : DetailStyle.safeIcon)
                .frame(width: 40, height: 40)
                .background(isScam ? DetailStyle.scamIconFill : DetailStyle.safeIconFill, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(isScam ? "Verified as a scam" : "Verified safe")
                    .activityFont(16, .medium, tracking: -0.16)
                    .foregroundStyle(DetailStyle.title)
                Text(verbatim: VerdictNote.byline(for: verdict, viewerDeviceId: viewerDeviceId, language: language))
                    .activityFont(13, rounded: true)
                    .foregroundStyle(DetailStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail.verdictNote")
            if canChange {
                Button("Change", action: onChange)
                    .activityFont(15, .medium, tracking: -0.15)
                    .foregroundStyle(DetailStyle.change)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint(Text("Shows the Safe and Danger buttons again"))
                    .accessibilityIdentifier("detail.verdictChange")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
