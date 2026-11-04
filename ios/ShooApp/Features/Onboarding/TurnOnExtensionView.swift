import SwiftUI

/// ON-04 (fallback PRD §10, Figma "Aktifkan Ekstensi"): where the switch is, a Turn on button, a status
/// check whenever the app comes back, and a tutorial video. Reused as a sheet from PR-04 / GD-01 "Turn on".
struct TurnOnExtensionView: View {
    /// Re-reads Safari's switch and the heartbeat (on appear and when the user is back from Settings or Safari).
    var refreshStatus: () async -> ExtensionStatus? = { nil }
    /// Onboarding only: back to Invite or Connect.
    var onBack: (() -> Void)?
    /// Onboarding only: Safari says Shoo is on but no page has checked in yet. A way on, so nobody is stuck
    /// when Safari is not their default browser. Also Next after Back, when Shoo is already on.
    var onSkipCheck: (() -> Void)?
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVideoPresented = false
    @State private var status: ExtensionStatus?

    /// A heartbeat can land a moment after the user is back from Safari: look again for this long (#135).
    private static let recheck = (times: 10, every: Duration.seconds(2))

    private let steps = ExtensionSetup.steps(for: ProcessInfo.processInfo.operatingSystemVersion)

    var body: some View {
        OnboardingFormPage(
            title: "Turn on the extension",
            onBack: onBack
        ) {
            // Figma "image 1" at y 72.5, the headline right under it at 373.
            OnboardingHeroImage(name: "ExtensionIllustration", top: 10.5, bottom: 0.5)
        } content: {
            // Figma "stack": 16 between rows, 40 under the headline.
            VStack(alignment: .leading, spacing: 16) {
                // The reason first, above the steps, so it is seen without scrolling (#135).
                if let nextStep {
                    Label { Text(nextStep.message) } icon: { Image(systemName: "info.circle.fill") }
                        .onboardingFont(15, design: .rounded, relativeTo: .subheadline)
                        .foregroundStyle(OnboardingTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(OnboardingTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityIdentifier("extension.offHint")
                }
                // Once the switch is known to be on, the setup steps are done; only the callout is left.
                if nextStep?.opensSafariFirst != true {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        OnboardingStepRow(number: index + 1, text: step.text)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 40)
        } footer: {
            if let onSkipCheck, status != nil, nextStep == nil {
                // Back from Safari Default: Shoo is on, nothing left to do here.
                Button("Next", action: onSkipCheck)
                    .buttonStyle(OnboardingCapsuleButtonStyle())
                    .accessibilityIdentifier("extension.continue")
            } else {
                // One main button that fits the reason (#135); the other half of the fix stays one tap away.
                let step = nextStep ?? .switchOn
                Button(step.opensSafariFirst ? "Open Safari" : "Turn on the extension") {
                    Task { step.opensSafariFirst ? await ExtensionSetup.openSafari() : await ExtensionSetup.openSettings() }
                }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .accessibilityIdentifier(step.opensSafariFirst ? "extension.openSafari" : "extension.turnOn")
                if step.hasSecondAction {
                    Button(step.opensSafariFirst ? "Open Safari settings" : "Open Safari") {
                        Task { step.opensSafariFirst ? await ExtensionSetup.openSettings() : await ExtensionSetup.openSafari() }
                    }
                    .buttonStyle(OnboardingLinkButtonStyle(color: OnboardingTheme.ink, weight: .semibold))
                    .accessibilityIdentifier(step.opensSafariFirst ? "extension.settings" : "extension.openSafariLink")
                }
                if let onSkipCheck, status?.isActive == true {
                    Button("Continue without checking", action: onSkipCheck)
                        .buttonStyle(OnboardingLinkButtonStyle(color: OnboardingTheme.secondaryInk, weight: .regular))
                        .accessibilityIdentifier("extension.skipCheck")
                }
            }
            OnboardingTutorialLink { isVideoPresented = true }
                .accessibilityIdentifier("extension.video")
        }
        .footerEndsWithLink()
        .largeHeadline()
        // On appear and every time the user is back from Settings or Safari: read now, then a few more
        // times in case the heartbeat from Safari is still on its way (no app restart needed, #135).
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            for attempt in 0..<Self.recheck.times {
                if attempt > 0 {
                    do { try await Task.sleep(for: Self.recheck.every) } catch { return }
                }
                status = await refreshStatus()
                if status != nil, nextStep == nil { return }
            }
        }
        .fullScreenCover(isPresented: $isVideoPresented) {
            TutorialVideoPlayer()
        }
    }

    /// nil until the first read, and once Shoo is on and has checked in.
    private var nextStep: ExtensionStatus.NextStep? { status?.nextStep }
}

/// Figma: "Terkendala? " regular ink + "Tonton Tutorial" semibold blue.
struct OnboardingTutorialLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Having trouble?") + Text(verbatim: " ")
                + Text("Watch the tutorial").fontWeight(.semibold).foregroundStyle(OnboardingTheme.link)
        }
        .buttonStyle(OnboardingLinkButtonStyle(color: OnboardingTheme.ink, weight: .regular))
    }
}

/// White 40 pt badge "01" + one instruction (Figma "row").
struct OnboardingStepRow: View {
    let number: Int
    let text: LocalizedStringKey
    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: CGFloat = 40

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: String(format: "%02d", number))
                .onboardingFont(15, weight: .semibold, relativeTo: .subheadline)
                .tracking(-0.19)
                .foregroundStyle(Color.dynamic(0x136CB7, dark: 0x5EAAF0))
                .frame(width: badgeSize, height: badgeSize)
                .background(OnboardingTheme.card, in: Circle())
                // Figma "Button": black 20%, y 2.7, blur 4.5 (its -2.7 spread has no SwiftUI equivalent).
                .shadow(color: .black.opacity(0.2), radius: 2.3, y: 2.7)
                .accessibilityLabel(Text("Step \(number)"))
            Text(text)
                // Figma: 22 pt lines, the font's own.
                .onboardingFont(17, design: .rounded, tracking: -0.17, relativeTo: .body)
                .foregroundStyle(OnboardingTheme.stepInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: badgeSize, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// ON-04 passed (Figma "Yeay, kamu berhasil lebih terlindungi!").
struct ExtensionOnView: View {
    let onContinue: () -> Void

    private static let shieldScale: CGFloat = 1.67

    var body: some View {
        OnboardingSuccessPage(
            title: Text("Yeay, you're better protected now!"),
            message: Text("The extension is on and ready to help spot possible scams on the internet."),
            idPrefix: "extensionOn",
            onContinue: onContinue,
            largeTitle: false
        ) {
            // Figma: the teal shield, its outline 177 pt wide around y 268; the headline at y 437.
            HalftoneShield(tint: .teal)
                .scaleEffect(Self.shieldScale)
                .frame(
                    width: HalftoneShield.size.width * Self.shieldScale,
                    height: HalftoneShield.size.height * Self.shieldScale
                )
                .padding(.top, 59)
                .padding(.bottom, 21)
        }
    }
}

#Preview("Turn on") {
    TurnOnExtensionView(refreshStatus: { .off(lastSeen: Date(), reason: .someSitesOnly) }, onBack: {})
}

#Preview("Turned on") {
    ExtensionOnView(onContinue: {})
}
