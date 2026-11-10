import SwiftUI

/// ON-04 inside onboarding: the online check question as a checkbox (Figma "Persetujuan · Checkbox", 1328:13421).
/// Turn on stays off until it is ticked; `prepare` saves the answer and registers the device.
struct OnboardingExtensionConsent {
    @Binding var isChecked: Bool
    var isWorking = false
    var failed = false
    /// `true` once Settings may open.
    let prepare: () async -> Bool
}

/// ON-04 (fallback PRD §10, Figma "Aktifkan Ekstensi"): where the switch is, a Turn on button, a status
/// check whenever the app comes back, and a tutorial video. Reused as a sheet from PR-04 / GD-01 "Turn on".
struct TurnOnExtensionView: View {
    /// Re-reads Safari's switch and the heartbeat (on appear and when the user is back from Settings or Safari).
    var refreshStatus: () async -> ExtensionStatus? = { nil }
    /// Onboarding only: back to the name or Connect.
    var onBack: (() -> Void)?
    /// Onboarding only: Safari says Shoo is on but no page has checked in yet. A way on, so nobody is stuck
    /// when Safari is not their default browser. Also Next after Back, when Shoo is already on.
    var onSkipCheck: (() -> Void)?
    /// Onboarding only: the consent checkbox.
    var consent: OnboardingExtensionConsent?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var isVideoPresented = false
    @State private var isDataSheetPresented = false
    @State private var status: ExtensionStatus?
    /// Settings or Safari was opened from here. Figma has no status note; it shows only once the user is
    /// back and Shoo is still not on (#135).
    @State private var leftForSettings = false
    @State private var cameBack = false

    /// A heartbeat can land a moment after the user is back from Safari: look again for this long (#135).
    private static let recheck = (times: 10, every: Duration.seconds(2))
    private let steps = ExtensionSetup.steps(for: ProcessInfo.processInfo.operatingSystemVersion)

    private var isChecked: Bool { consent?.isChecked ?? true }
    private var isWorking: Bool { consent?.isWorking ?? false }

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
                if let nextStep, showsStatusNote {
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
                if !showsStatusNote || nextStep?.opensSafariFirst != true {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        OnboardingStepRow(number: index + 1, text: step.text)
                            .accessibilityIdentifier("extension.step.\(index + 1)")
                    }
                }
                if let consent, consent.failed {
                    OnboardingErrorLabel(text: Text("Couldn't save. Check your connection and try again."), systemImage: "wifi.exclamationmark")
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("extension.error")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 40)
        } footer: {
            if let consent {
                // Figma: 24 under the steps' area, 55 above the button.
                // Figma: the checkbox block ends 55 above the button (footer rows are 12 apart).
                ConsentCheckbox(isChecked: consent.$isChecked) { isDataSheetPresented = true }
                    .padding(.bottom, 43)
            }
            if let onSkipCheck, status != nil, nextStep == nil {
                // Shoo is already on (Back from Safari Default, or switched on before): nothing left to do here.
                Button(action: onSkipCheck) { workingLabel("Next") }
                    .buttonStyle(OnboardingCapsuleButtonStyle())
                    .disabled(!isChecked)
                    .accessibilityIdentifier("extension.continue")
            } else {
                // One main button that fits the reason (#135); the other half of the fix stays one tap away.
                let step = showsStatusNote ? (nextStep ?? .switchOn) : .switchOn
                Button {
                    Task { await open(safariFirst: step.opensSafariFirst) }
                } label: {
                    workingLabel(step.opensSafariFirst ? "Open Safari" : "Turn on the extension")
                }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .disabled(!isChecked)
                .accessibilityIdentifier(step.opensSafariFirst ? "extension.openSafari" : "extension.turnOn")
                if showsStatusNote, step.hasSecondAction {
                    Button(step.opensSafariFirst ? "Open Safari settings" : "Open Safari") {
                        Task { await open(safariFirst: !step.opensSafariFirst) }
                    }
                    .buttonStyle(OnboardingLinkButtonStyle(color: OnboardingTheme.ink, weight: .semibold))
                    .disabled(!isChecked)
                    .accessibilityIdentifier(step.opensSafariFirst ? "extension.settings" : "extension.openSafariLink")
                }
                if let onSkipCheck, showsStatusNote, status?.isActive == true {
                    Button("Continue without checking", action: onSkipCheck)
                        .buttonStyle(OnboardingLinkButtonStyle(color: OnboardingTheme.secondaryInk, weight: .regular))
                        .disabled(!isChecked)
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
            if leftForSettings { cameBack = true }
            for attempt in 0..<Self.recheck.times {
                if attempt > 0 {
                    do { try await Task.sleep(for: Self.recheck.every) } catch { return }
                }
                status = await refreshStatus()
                if status != nil, nextStep == nil { return }
            }
        }
        .onChange(of: consent?.failed ?? false) { _, failed in
            guard failed else { return }
            AccessibilityNotification.Announcement(
                L10n.string("Couldn't save. Check your connection and try again.", language: AppLanguage(locale: locale))
            ).post()
        }
        .fullScreenCover(isPresented: $isVideoPresented) {
            TutorialVideoPlayer()
        }
        .sheet(isPresented: $isDataSheetPresented) {
            DataSentSheet()
        }
    }

    /// nil until the first read, and once Shoo is on and has checked in.
    private var nextStep: ExtensionStatus.NextStep? { status?.nextStep }

    /// Outside onboarding (Home "Turn on") the reason shows right away; in onboarding once the user is back.
    private var showsStatusNote: Bool { consent == nil || cameBack }

    private func open(safariFirst: Bool) async {
        if let consent {
            guard await consent.prepare() else { return }
        }
        leftForSettings = true
        if safariFirst { await ExtensionSetup.openSafari() } else { await ExtensionSetup.openSettings() }
    }

    private func workingLabel(_ title: LocalizedStringKey) -> some View {
        ZStack {
            Text(title).opacity(isWorking ? 0 : 1)
            if isWorking { ProgressView().tint(OnboardingTheme.onButton) }
        }
    }
}

/// Figma "Persetujuan · Checkbox": a 24 pt box, the sentence, and "Lihat data yang dikirim" 2 pt under it.
private struct ConsentCheckbox: View {
    @Binding var isChecked: Bool
    let onShowData: () -> Void
    @ScaledMetric(relativeTo: .body) private var boxSize: CGFloat = 24

    private static let checkedFill = Color.dynamic(0x1E6FCB, dark: 0x3D8BE0)
    private static let link = Color.dynamic(0x186FB9, dark: 0x5EAAF0)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { isChecked.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isChecked ? Self.checkedFill : OnboardingTheme.card)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isChecked ? Self.checkedFill : OnboardingTheme.placeholder, lineWidth: 2)
                        if isChecked {
                            Image(systemName: "checkmark")
                                .font(.system(size: boxSize * 0.55, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: boxSize, height: boxSize)
                    Text("I agree to pages being checked online.")
                        .onboardingFont(17, design: .rounded, tracking: -0.17, relativeTo: .body)
                        .foregroundStyle(OnboardingTheme.stepInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isChecked ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("extension.consent")

            Button(action: onShowData) {
                Text("See what is sent")
                    .onboardingFont(17, design: .rounded, tracking: -0.17, relativeTo: .body)
                    .foregroundStyle(Self.link)
                    // 44 pt to tap, laid out as its 22 pt line.
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .padding(.vertical, -11)
            }
            .buttonStyle(.plain)
            .padding(.leading, boxSize + 12)
            .accessibilityIdentifier("extension.dataSent")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Figma "Sheet · Data yang dikirim" (1328:13313): what leaves the phone with the online check on.
struct DataSentSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What is sent")
                        .onboardingFont(28, weight: .semibold, tracking: -0.4, relativeTo: .title)
                        .foregroundStyle(OnboardingTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("When the online check is on.")
                        .onboardingFont(17, design: .rounded, tracking: -0.17, relativeTo: .body)
                        .foregroundStyle(OnboardingTheme.bodyInk)
                }
                Spacer(minLength: 12)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.secondaryInk)
                        .frame(width: 32, height: 32)
                        .background(OnboardingTheme.background, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
                .padding(.trailing, -6)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    row("doc.text.magnifyingglass", tint: 0x1E6FCB, fill: 0xE6F0FB,
                        title: "Pages you open", text: "Page text, form field names and the address. What you type is not sent.")
                    row("exclamationmark.shield", tint: 0xD23B3B, fill: 0xFDECEC,
                        title: "Risky pages", text: "The address and a copy are kept. Some of it stays after the account is deleted.")
                    row("sparkles", tint: 0x0D8F93, fill: 0xE2F6F4,
                        title: "AI check by DeepSeek", text: "A summary of a suspicious page is sent to DeepSeek, an AI from China.")
                    row("iphone", tint: 0x5B616C, fill: 0xEEF0F3,
                        title: "Without the online check", text: "Shoo checks on your iPhone only, with less protection.")
                }
                .padding(.top, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button("Got it") { dismiss() }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .padding(.top, 20)
                .accessibilityIdentifier("dataSent.done")
        }
        .padding(.horizontal, 24)
        .padding(.top, 25)
        .padding(.bottom, 8)
        .background(OnboardingTheme.card)
        // Figma: a 618 pt sheet; larger text scrolls, and can be pulled up.
        .presentationDetents([.height(618), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    private func row(_ symbol: String, tint: UInt32, fill: UInt32, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(hex: tint))
                .frame(width: 40, height: 40)
                .background(Color(hex: fill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .onboardingFont(17, weight: .semibold, relativeTo: .body)
                    .foregroundStyle(OnboardingTheme.ink)
                Text(text)
                    .onboardingFont(16, design: .rounded, tracking: -0.31, relativeTo: .callout)
                    .foregroundStyle(OnboardingTheme.bodyInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
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
    @Previewable @State var checked = false
    TurnOnExtensionView(
        refreshStatus: { .off(lastSeen: Date(), reason: .someSitesOnly) }, onBack: {},
        consent: OnboardingExtensionConsent(isChecked: $checked, prepare: { true })
    )
}

#Preview("Turned on") {
    ExtensionOnView(onContinue: {})
}
