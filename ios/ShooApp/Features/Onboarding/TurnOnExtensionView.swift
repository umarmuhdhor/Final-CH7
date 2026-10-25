import SwiftUI

/// ON-04 (fallback PRD §10, Figma "Aktifkan Ekstensi"): where the switch is, a Turn on button, a status
/// check whenever the app comes back, and a tutorial video. Reused as a sheet from PR-04 / GD-01 "Turn on".
struct TurnOnExtensionView: View {
    /// Re-reads the heartbeat (on appear and when the user is back from Settings).
    var refreshStatus: () -> Void = {}
    /// Guardian onboarding only: back to the invite screen.
    var onBack: (() -> Void)?
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVideoPresented = false

    private let steps = ExtensionSetup.steps(for: ProcessInfo.processInfo.operatingSystemVersion)

    var body: some View {
        OnboardingFormPage(
            title: "Turn on the extension",
            message: "Turn it on in Safari to get protection right away.",
            onBack: onBack
        ) {
            OnboardingHeroImage(name: "ExtensionIllustration")
                .padding(.top, 14)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    StepRow(number: index + 1, text: step.text)
                }
                Label { Text("Shoo is off.") } icon: { Image(systemName: "info.circle") }
                    .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                    .foregroundStyle(OnboardingTheme.secondaryInk)
                    .padding(.top, 4)
                    .accessibilityIdentifier("extension.offHint")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
        } footer: {
            Button("Turn on extension") {
                Task { await ExtensionSetup.openSettings() }
            }
            .buttonStyle(OnboardingCapsuleButtonStyle())
            .accessibilityIdentifier("extension.turnOn")
            Button("Having trouble? Watch the tutorial") { isVideoPresented = true }
                .buttonStyle(OnboardingLinkButtonStyle(color: OnboardingTheme.ink, weight: .regular))
                .accessibilityIdentifier("extension.video")
        }
        .onAppear(perform: refreshStatus)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshStatus() }
        }
        .fullScreenCover(isPresented: $isVideoPresented) {
            TutorialVideoPlayer()
        }
    }
}

/// White 40 pt badge "01" + one instruction (Figma "row").
private struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey
    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: CGFloat = 40

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: String(format: "%02d", number))
                .onboardingFont(15, weight: .semibold, relativeTo: .subheadline)
                .tracking(-0.19)
                .foregroundStyle(Color(red: 0x13 / 255, green: 0x6C / 255, blue: 0xB7 / 255))
                .frame(width: badgeSize, height: badgeSize)
                .background(.white, in: Circle())
                .accessibilityLabel(Text("Step \(number)"))
            Text(text)
                .onboardingFont(17, design: .rounded, relativeTo: .body)
                .lineSpacing(6.8)
                .foregroundStyle(OnboardingTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: badgeSize, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// ON-04 passed (Figma "Yeay, kamu berhasil lebih terlindungi!").
struct ExtensionOnView: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingSuccessPage(
            title: Text("Yeay, you're better protected now!"),
            message: Text("The extension is on and ready to help spot possible scams on the internet."),
            idPrefix: "extensionOn",
            onContinue: onContinue
        ) {
            Image("ExtensionOnIllustration")
                .resizable()
                .scaledToFit()
                .frame(width: 286, height: 285)
                .padding(.top, 40)
                .accessibilityHidden(true)
        }
    }
}

#Preview("Turn on") {
    TurnOnExtensionView(onBack: {})
}

#Preview("Turned on") {
    ExtensionOnView(onContinue: {})
}
