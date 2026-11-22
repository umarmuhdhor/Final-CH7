import AVFoundation
import SwiftUI

/// ON-04 inside onboarding: the online check question as a checkbox (Figma "Persetujuan · Checkbox", 1328:13421).
/// Figma "Aktifkan Ekstensi" (110:4505): the button stays grey until the box is ticked, and a tap on the grey
/// button says to tick it first (Alief, 20 Nov 2026). This brings back the lock 5dbec833 removed for App Review
/// 5.1.1(iv) (#616), on Alief's decision. `prepare` saves the answer and registers the device. Without the
/// checkbox (answered before, e.g. on the invite path's consent step) the buttons are on (fase 27d K6).
struct OnboardingExtensionConsent {
    @Binding var isChecked: Bool
    var showsCheckbox = true
    var isWorking = false
    var failed = false
    /// `failed` was the sign-up limit (429), not the connection.
    var limited = false
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
    /// Onboarding only: Next once Shoo is on (back from Settings, after Back, or switched on before). The screen
    /// never moves on by itself, so the consent box is seen again before leaving. Outside onboarding it is not set.
    var onSkipCheck: (() -> Void)?
    /// Onboarding only: the consent checkbox.
    var consent: OnboardingExtensionConsent?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var isVideoPresented = false
    @State private var videoStartTime: CMTime = .zero
    @State private var isDataSheetPresented = false
    @State private var status: ExtensionStatus?
    /// Settings or Safari was opened from here. Figma has no status note; it shows only once the user is
    /// back and Shoo is still not on (#135).
    @State private var leftForSettings = false
    @State private var cameBack = false
    /// F3 (goldfish 21 Nov 2026): onboarding is back from Settings and Shoo is still not on everywhere.
    @State private var returnToast: SettingsReturnToast?
    /// Taps on the grey button before the box was ticked; "tick the box first" shows under the box from the first.
    @State private var consentNudges = 0

    /// A heartbeat can land a moment after the user is back from Safari: look again for this long (#135).
    private static let recheck = (times: 10, every: Duration.seconds(2))
    private let steps = ExtensionSetup.steps(for: ProcessInfo.processInfo.operatingSystemVersion)

    private var isWorking: Bool { consent?.isWorking ?? false }
    /// Onboarding with the box on screen and not ticked yet: the buttons look disabled.
    /// Step 01 names the box, because the button stays grey until it is ticked (Alief, 20 Nov 2026). Without the
    /// box (answered on an earlier install, or Shield's sheet) it still says "Tap the button below".
    private func text(for step: ExtensionSetup.Step) -> LocalizedStringKey {
        if step == .tapTurnOn, consent?.showsCheckbox == true { return "Tick the box below, then tap Turn on the extension." }
        return step.text
    }

    private var needsConsent: Bool { consent.map { $0.showsCheckbox && !$0.isChecked } ?? false }
    private var showsConsentHint: Bool { consentNudges > 0 && needsConsent }

    var body: some View {
        OnboardingFormPage(
            title: "Turn on the extension",
            onBack: onBack
        ) {
            // Figma "image 1" at y 72.5, the headline right under it at 373.
            // Figma 110:4440 has it 10.5 lower; with four steps that is the room step 04 needs above the box.
            OnboardingHeroImage(name: "ExtensionIllustration", top: 0, bottom: 0.5)
        } content: {
            // Figma "stack" had 16 between rows and 40 under the headline for three steps; 12 and 20 fit all four
            // above the consent box on a 402 × 874 iPhone without scrolling (Alief, 20 Nov 2026).
            VStack(alignment: .leading, spacing: 12) {
                // The reason first, above the steps, so it is seen without scrolling (#135).
                if let nextStep, showsStatusNote || showsAllSitesWarning {
                    Label { Text(nextStep.message) } icon: { Image(systemName: "info.circle.fill") }
                        .onboardingFont(15, design: .rounded, relativeTo: .subheadline)
                        .foregroundStyle(OnboardingTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(OnboardingTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        // Back from Settings: it drops in over the steps; a fade with Reduce Motion.
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                        .accessibilityIdentifier("extension.offHint")
                }
                // Once the switch is known to be on, the setup steps are done; only the callout is left.
                if !showsStatusNote || nextStep?.switchIsOn != true {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        OnboardingStepRow(number: index + 1, text: text(for: step))
                            .accessibilityIdentifier("extension.step.\(index + 1)")
                    }
                }
                if let consent, consent.failed, consent.limited {
                    OnboardingErrorLabel(text: Text("Too many sign-ups from this network. Try again in 1 hour."), systemImage: "clock")
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("extension.error")
                } else if let consent, consent.failed {
                    OnboardingErrorLabel(text: Text("Couldn't save. Check your connection and try again."), systemImage: "wifi.exclamationmark")
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("extension.error")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
        } footer: {
            if let consent, consent.showsCheckbox {
                // Figma 110:4440: the box sits right above the button (Alief: lower it so every step shows).
                VStack(alignment: .leading, spacing: 8) {
                    ConsentCheckbox(isChecked: consent.$isChecked) { isDataSheetPresented = true }
                    if showsConsentHint {
                        OnboardingErrorLabel(text: Text("Tick the box above first to continue."))
                            .multilineTextAlignment(.leading)
                            .transition(.opacity)
                            .accessibilityIdentifier("extension.consentHint")
                    }
                }
                .padding(.bottom, showsConsentHint ? 4 : 12)
            }
            if let onSkipCheck, status != nil, nextStep == nil || (consent != nil && status?.isActive == true) {
                // Shoo is already on (Back from Safari Default, or switched on before): nothing left to do here.
                // In onboarding the switch is enough; Safari Default then sends the user to Safari.
                Button {
                    guard consentGiven() else { return }
                    onSkipCheck()
                } label: { workingLabel("Next") }
                    .buttonStyle(OnboardingCapsuleButtonStyle(looksDisabled: needsConsent))
                    .accessibilityHint(needsConsent ? Text("Tick the box above first to continue.") : Text(verbatim: ""))
                    .accessibilityIdentifier("extension.continue")
            } else {
                // One main button that fits the reason (#135); the other half of the fix stays one tap away.
                let step = showsStatusNote ? (nextStep ?? .switchOn) : .switchOn
                Button {
                    guard consentGiven() else { return }
                    Task { await open(safariFirst: step.opensSafariFirst) }
                } label: {
                    workingLabel(mainTitle(for: step))
                }
                .buttonStyle(OnboardingCapsuleButtonStyle(looksDisabled: needsConsent))
                .accessibilityHint(needsConsent ? Text("Tick the box above first to continue.") : Text(verbatim: ""))
                .accessibilityIdentifier(step.opensSafariFirst ? "extension.openSafari" : "extension.turnOn")
                if showsStatusNote, step.hasSecondAction {
                    Button(step.opensSafariFirst ? "Open Safari settings" : "Open Safari") {
                        Task { await open(safariFirst: !step.opensSafariFirst) }
                    }
                    .buttonStyle(OnboardingLinkButtonStyle(color: OnboardingTheme.ink, weight: .semibold))
                    .transition(.opacity)
                    .accessibilityIdentifier(step.opensSafariFirst ? "extension.settings" : "extension.openSafariLink")
                }
                if let onSkipCheck, showsStatusNote, status?.isActive == true {
                    Button("Continue without checking", action: onSkipCheck)
                        .buttonStyle(OnboardingLinkButtonStyle(color: OnboardingTheme.secondaryInk, weight: .regular))
                        .transition(.opacity)
                        .accessibilityIdentifier("extension.skipCheck")
                }
            }
            OnboardingTutorialLink { watchTutorial() }
                .accessibilityIdentifier("extension.video")
        }
        .footerEndsWithLink()
        .largeHeadline()
        // Back from Settings the note, steps and buttons change together, not in one jump.
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3), value: cameBack)
        // On appear and every time the user is back from Settings or Safari: read now, then a few more
        // times in case the heartbeat from Safari is still on its way (no app restart needed, #135).
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            let returned = leftForSettings
            if returned {
                cameBack = true
                leftForSettings = false
            }
            for attempt in 0..<Self.recheck.times {
                if attempt > 0 {
                    do { try await Task.sleep(for: Self.recheck.every) } catch { return }
                }
                status = await refreshStatus()
                // F3: said once per return, from the first read; gone as soon as Shoo is found on.
                if consent != nil {
                    if attempt == 0, returned { returnToast = status.flatMap(SettingsReturnToast.init) }
                    if status?.isActive == true { returnToast = nil }
                }
                if status != nil, nextStep == nil { return }
                // Onboarding never moves on by itself: back from Settings with the switch on, the screen keeps the
                // consent box and turns the main button into Next, so the box is seen once more before leaving.
                // Next follows the same lock as Turn on: grey until the box is ticked.
                if consent != nil, status?.isActive == true { return }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: showsConsentHint)
        // F3: where an iOS notification would be, Shoo's head 8 pt under the status bar.
        .overlay(alignment: .top) {
            if let returnToast {
                ShooToast(
                    title: L10n.string(returnToast.title, language: AppLanguage(locale: locale)),
                    line: L10n.string(returnToast.line, language: AppLanguage(locale: locale)),
                    colors: SettingsReturnToast.colors, pose: returnToast.pose, identifier: "extension.returnToast",
                    duration: UIAccessibility.isVoiceOverRunning ? .seconds(10) : .seconds(6),
                    onClose: { self.returnToast = nil }
                )
                .padding(.top, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(StateMotion.enter(reduceMotion: reduceMotion), value: returnToast)
        .onChange(of: needsConsent) { _, needed in
            if !needed { consentNudges = 0 }
        }
        // Every tap on the grey button, not only the first.
        .sensoryFeedback(.warning, trigger: consentNudges) { old, new in new > old }
        .onChange(of: consent?.failed ?? false) { _, failed in
            guard failed else { return }
            AccessibilityNotification.Announcement(
                L10n.string("Couldn't save. Check your connection and try again.", language: AppLanguage(locale: locale))
            ).post()
        }
        .fullScreenCover(isPresented: $isVideoPresented) {
            TutorialVideoPlayer(startTime: videoStartTime)
        }
        .peekSheet(isPresented: $isDataSheetPresented, background: OnboardingTheme.card) {
            DataSentSheet()
        }
    }

    /// nil until the first read, and once Shoo is on and has checked in.
    private var nextStep: ExtensionStatus.NextStep? { status?.nextStep }

    /// Only outside onboarding (Home "Turn on"). Onboarding always shows the Figma "Aktifkan Ekstensi" frame:
    /// the steps, the consent box, Turn on and the tutorial link, also after Settings.
    private var showsStatusNote: Bool { consent == nil }

    /// Onboarding too: the extension has reported that Safari lets it read only some sites (`extension.allSites`
    /// false). The one case the app can see; with Ask and no page loaded yet nothing reports in, so the step
    /// above is what tells the user (usability test 20 Nov 2026).
    private var showsAllSitesWarning: Bool { consent != nil && nextStep == .allowEveryWebsite }

    /// `false` while the box is unticked: shows "tick the box first" and tells VoiceOver, instead of going on.
    private func consentGiven() -> Bool {
        guard needsConsent else { return true }
        consentNudges += 1
        AccessibilityNotification.Announcement(
            L10n.string("Tick the box above first to continue.", language: AppLanguage(locale: locale))
        ).post()
        return false
    }

    private func open(safariFirst: Bool) async {
        if let consent {
            guard await consent.prepare() else { return }
        }
        leftForSettings = true
        if safariFirst { await ExtensionSetup.openSafari() } else { await ExtensionSetup.openSettings() }
    }

    /// The switch is on, but Safari still asks per site: the button goes where the fix is (F5).
    private func mainTitle(for step: ExtensionStatus.NextStep) -> LocalizedStringKey {
        if step.opensSafariFirst { return "Open Safari" }
        return step.switchIsOn ? "Open Safari settings" : "Turn on the extension"
    }

    private func workingLabel(_ title: LocalizedStringKey) -> some View {
        ZStack {
            Text(title).opacity(isWorking ? 0 : 1)
            if isWorking { ProgressView().tint(OnboardingTheme.onButton) }
        }
    }

    /// "Watch the tutorial": straight into PiP so the steps stay on screen; full screen where PiP can't run.
    private func watchTutorial() {
        TutorialPiP.shared.start(
            fallback: {
                videoStartTime = .zero
                isVideoPresented = true
            },
            restore: { time in
                videoStartTime = time
                isVideoPresented = true
            }
        )
    }
}

/// F3 (Figma elephant–goldfish 2425:4545): ON-04 in onboarding is back from Settings with nothing changed. A: Shoo is
/// still off (Tidur). B: it is on but Safari still asks per site (Tap di sini). Orange like a warning, step number
/// included, so the user knows which step to redo.
enum SettingsReturnToast: Equatable {
    case stillOff
    case someSitesOnly

    init?(_ status: ExtensionStatus) {
        switch status {
        case .active: return nil
        case .off(_, .someSitesOnly): self = .someSitesOnly
        case .off(_, .switchedOff), .off(_, .notSeen): self = .stillOff
        }
    }

    static let colors = [Color(hex: 0xF2B14C), Color(hex: 0xE0892B)]

    var title: String.LocalizationValue {
        switch self {
        case .stillOff: "Shoo isn't on yet"
        case .someSitesOnly: "Shoo is on for some sites only"
        }
    }

    var line: String.LocalizationValue {
        switch self {
        case .stillOff: "Open Settings again and switch Shoo on (step 02)."
        case .someSitesOnly: "Tap All Websites and choose Allow (step 03)."
        }
    }

    var pose: Mascot {
        switch self {
        case .stillOff: .sleep
        case .someSitesOnly: .tapHere
        }
    }
}

/// Figma "Persetujuan · Checkbox": a 24 pt box, the sentence, and "Lihat data yang dikirim" 2 pt under it.
private struct ConsentCheckbox: View {
    @Binding var isChecked: Bool
    let onShowData: () -> Void
    @ScaledMetric(relativeTo: .body) private var boxSize: CGFloat = 24
    @Environment(\.shooReduceMotion) private var reduceMotion

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
                                // Pops in under the toggle's `.snappy`; a plain fade with Reduce Motion.
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
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
            .sensoryFeedback(.selection, trigger: isChecked)
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

/// Figma "Sheet · Data yang dikirim" (1328:13313): what leaves the phone with the online check on. Presented with
/// `peekSheet` (fase 29g): Shoo peeks over the top edge.
struct DataSentSheet: View {
    @Environment(\.closePeekSheet) private var close
    /// The rows' height and the room they got: while they fit, the list stays still so a drag moves the sheet.
    @State private var rowsHeight: CGFloat = 0
    @State private var rowsViewport: CGFloat = 0

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
                Button { close() } label: {
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
                        title: "Risky pages",
                        // C6 (goldfish 21 Nov): what stays, and after what, without the word "akun" seen nowhere before.
                        text: "The address and a copy of the page are kept for 14 days. After you delete your data (Profile › Delete Account), the site's address and score stay, without your name.")
                    row("iphone", tint: 0x5B616C, fill: 0xEEF0F3,
                        title: "Without the online check", text: "Shoo checks on your iPhone only, with less protection.")
                }
                .padding(.top, 20)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsViewport = $0 }
            .scrollDisabled(rowsHeight <= rowsViewport + 0.5)
            .scrollBounceBehavior(.basedOnSize)
            Button("Got it") { close() }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .padding(.top, 20)
                .accessibilityIdentifier("dataSent.done")
        }
        .padding(.horizontal, 24)
        .padding(.top, 25)
        .padding(.bottom, 8)
        // Figma: a 618 pt sheet; larger text (or a shorter screen) scrolls the rows.
        .frame(maxHeight: 618, alignment: .top)
        // The grabber the system sheet drew.
        .overlay(alignment: .top) {
            Capsule().fill(ProfileStyle.sheetGrabber).frame(width: 36, height: 5)
                .padding(.top, 8)
                .accessibilityHidden(true)
        }
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

/// ON-04 passed, step 1 of 2 done (Figma 2502:5639 "B2 · Layar selamat · Ekstensi aktif"): the success page
/// with the celebrating owl, then Next to Safari Default. Without it ON-04 and Safari Default look alike and
/// "Next" seemed to do nothing (transition B, 22 Nov 2026).
struct ExtensionReadyView: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingSuccessPage(
            title: Text("Shoo extension is on!"),
            message: Text("One more step: make Safari your main browser, so links you tap open with Shoo's protection."),
            idPrefix: "extensionReady",
            onContinue: onContinue,
            largeTitle: false,
            celebrates: true,
            buttonTitle: "Continue"
        ) {
            // Figma: the owl about 300 pt tall from y 90, the headline under it.
            MascotImage(pose: .celebrate, height: 300)
                .successCelebrationHero(ringSize: 220)
                .padding(.top, 44)
                .padding(.bottom, 16)
        }
    }
}

/// Safari Default passed (Figma "Yeay, kamu berhasil lebih terlindungi!").
struct ExtensionOnView: View {
    let onContinue: () -> Void

    private static let shieldScale: CGFloat = 1.67

    var body: some View {
        OnboardingSuccessPage(
            title: Text("Yeay, you're better protected now!"),
            message: Text("The extension is on and ready to help spot possible scams on the internet."),
            idPrefix: "extensionOn",
            onContinue: onContinue,
            largeTitle: false,
            // "Yeay": the shield pops in with rings and confetti, a heavy tap as it lands and a success tap with
            // the title (they replace the single success tap this screen had).
            celebrates: true
        ) {
            // Figma: the teal shield, its outline 177 pt wide around y 268; the headline at y 437.
            HalftoneShield(tint: .teal)
                .scaleEffect(Self.shieldScale)
                .frame(
                    width: HalftoneShield.size.width * Self.shieldScale,
                    height: HalftoneShield.size.height * Self.shieldScale
                )
                .successCelebrationHero(ringSize: 177)
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

#Preview("Extension ready") {
    ExtensionReadyView(onContinue: {})
}

#Preview("Turned on") {
    ExtensionOnView(onContinue: {})
}
