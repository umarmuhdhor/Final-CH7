import SwiftUI
import UIKit

/// PR-01: connect to the guardian by Scan QR or Code, then PR-02 "Connected to …" (Figma "Connect with Guardian").
/// Used in onboarding (with "Not now") and from Shield / an invite link after onboarding.
struct ConnectView: View {
    let model: ConnectModel
    /// After onboarding (sheet): close. Inside onboarding: back to ON-03 until the mode is saved.
    var onBack: (() -> Void)?
    /// Continue without a guardian for now.
    var onSkip: (() -> Void)?
    /// After PR-02.
    let onFinish: () -> Void

    enum Tab: Hashable {
        case scan
        case code
    }

    @Environment(\.locale) private var locale
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var tab: Tab = .code
    @State private var scanRefused = false
    @State private var codeFocused = false
    /// Bumped each time a problem shows: shakes the code boxes once and taps an error haptic.
    @State private var problemsShown = 0
    /// Bumped by "Ketik ulang kode": the code field takes focus again.
    @State private var focusRequests = 0

    var body: some View {
        Group {
            if case .joined(let guardian) = model.state {
                ProtectedByView(guardian: guardian, onContinue: onFinish)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            } else {
                form
                    .transition(.opacity)
            }
        }
        // PR-02: "Connected to …" settles in instead of replacing the form at once.
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.4), value: isJoined)
        .sensoryFeedback(.success, trigger: isJoined) { wasJoined, joined in !wasJoined && joined }
        .sensoryFeedback(.error, trigger: problemsShown)
    }

    private var isJoined: Bool {
        if case .joined = model.state { true } else { false }
    }

    private static let codeFieldID = "connect.codeField"

    private var language: AppLanguage { AppLanguage(locale: locale) }

    private var form: some View {
        OnboardingFormPage(
            title: "Connect your account",
            message: "Scan the QR or enter the invite code from your Guardian.",
            onBack: onBack.map { back in { if !model.isBusy { back() } } },
            scrollTarget: codeFocused || model.problem != nil ? Self.codeFieldID : nil
        ) {
            VStack(spacing: 0) {
                // Figma: tabs at y 242, label at y 332.
                ConnectTabs(tab: $tab)
                    .padding(.top, 37)

                switch tab {
                case .scan:
                    VStack(spacing: 16) {
                        ScannerFrame {
                            QRScannerView { payload in
                                if model.scanned(payload) {
                                    scanRefused = false
                                    tab = .code
                                } else {
                                    scanRefused = true
                                }
                            }
                        }
                        if scanRefused {
                            // Figma "QR bukan kode Shoo" (1681:4972): the line, then a way to type the code instead.
                            VStack(alignment: .leading, spacing: 12) {
                                ConnectProblemLabel(text: Text("This QR isn't a Shoo invite code. Scan the QR from your Guardian's Shoo app."))
                                    .accessibilityIdentifier("connect.scanRefused")
                                Button("Just enter the code") {
                                    withAnimation(.snappy(duration: 0.3)) { tab = .code }
                                    focusRequests += 1
                                }
                                .buttonStyle(ConnectInlineLinkStyle())
                                .accessibilityIdentifier("connect.enterCodeInstead")
                            }
                            .transition(StateMotion.transition(reduceMotion: reduceMotion, edge: .top))
                        } else {
                            problemLabel
                        }
                    }
                    .padding(.top, 24)
                case .code:
                    // Figma "Frame 91": 32 between the label and the boxes.
                    VStack(spacing: 32) {
                        Text("Enter the invite code")
                            .onboardingBodyStyle()
                        VStack(alignment: .leading, spacing: 12) {
                            CodeField(
                                code: Binding(get: { model.code }, set: { model.code = $0 }),
                                isWrong: model.problem == .invalid,
                                focusRequests: focusRequests,
                                onFocusChange: { codeFocused = $0 }
                            )
                            .modifier(ShakeOnProblem(trigger: problemsShown, isEnabled: !reduceMotion))
                            problemLabel
                            // Figma "Kode salah" (1681:4712): "Ketik ulang kode" under the line empties the boxes.
                            if model.problem == .invalid {
                                Button("Retype code") {
                                    model.retype()
                                    focusRequests += 1
                                }
                                .buttonStyle(ConnectInlineLinkStyle())
                                .padding(.top, 12)
                                .transition(StateMotion.transition(reduceMotion: reduceMotion, edge: .top))
                                .accessibilityIdentifier("connect.retype")
                            }
                        }
                        // Fades in; editing the code clears it at once (no fade-out to wait for).
                        .animation(model.problem == nil ? nil : StateMotion.enter(reduceMotion: reduceMotion), value: model.problem)
                        .id(Self.codeFieldID)
                    }
                    .padding(.top, 39)
                }

                // fase 18 K17: said before joining, since copies are only made while connected.
                // QA 1110 #8, #16: part of the page, not the pinned footer. In the footer a two-line error ran
                // into it, and with the keyboard up it took the room the headline needs.
                copyNote
                    .padding(.top, 24)
                    // While typing it would only peek out beside the button; it was read before the field.
                    .opacity(codeFocused ? 0 : 1)
                    .accessibilityHidden(codeFocused)
            }
        } footer: {
            if tab == .code, model.problem == .full, let onBack {
                // Figma "Keluarga penuh" (1681:4750): nothing to retry here until the guardian makes room.
                Button("Back") { if !model.isBusy { onBack() } }
                    .buttonStyle(OnboardingCapsuleButtonStyle())
                    .transition(.opacity)
                    .accessibilityIdentifier("connect.back")
            } else if tab == .code, model.retryAt != nil {
                WaitButton(model: model)
                    .transition(.opacity)
            } else if tab == .code {
                Button {
                    // QA 1110 #8: the answer shows on the whole page, not squeezed above the keyboard where
                    // a two-line error ran under the button and the headline was pushed off the top.
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    Task { await model.join() }
                } label: {
                    ZStack {
                        Text("Connect").opacity(model.state == .joining ? 0 : 1)
                        if model.state == .joining { ProgressView().tint(OnboardingTheme.onButton) }
                    }
                }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                // Stays dark while joining so the spinner is visible; taps are ignored by `join()` then.
                .disabled(!model.canJoin && model.state != .joining)
                .accessibilityIdentifier("connect.join")
            }
            if let onSkip {
                Button("Not now", action: onSkip)
                    .buttonStyle(OnboardingLinkButtonStyle())
                    // A join already sent finishes on the server: wait for its answer (PR-02).
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("connect.skip")
            }
        }
        .footerEndsWithLink(onSkip != nil)
        .headlineInset(24)
        .animation(.easeInOut(duration: 0.2), value: footerKind)
        .animation(StateMotion.enter(reduceMotion: reduceMotion), value: scanRefused)
        .onChange(of: tab) { scanRefused = false }
        .onChange(of: scanRefused) { _, refused in
            guard refused else { return }
            AccessibilityNotification.Announcement(L10n.string("This QR isn't a Shoo invite code. Scan the QR from your Guardian's Shoo app.", language: language)).post()
        }
        .onChange(of: model.problem) { _, problem in
            guard let problem else { return }
            problemsShown += 1
            AccessibilityNotification.Announcement(L10n.string(problem.message, language: language)).post()
        }
    }

    private var copyNote: some View {
        Label {
            Text("Shoo keeps a copy of pages it blocks or warns you about for 14 days, so your Guardian can see the evidence.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .onboardingFont(13, design: .rounded, relativeTo: .footnote)
        .foregroundStyle(OnboardingTheme.secondaryInk)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("connect.copyNote")
    }

    /// Which footer shows; its swaps cross-fade.
    private var footerKind: Int {
        if model.problem == .full, onBack != nil { 1 } else if model.retryAt != nil { 2 } else { 0 }
    }

    @ViewBuilder
    private var problemLabel: some View {
        if let problem = model.problem {
            ConnectProblemLabel(
                text: Text(verbatim: L10n.string(problem.message, language: language)),
                systemImage: problem.isWait ? "clock" : (problem == .expired ? "clock.arrow.circlepath" : "exclamationmark.triangle.fill"),
                tint: problem.isWait ? ConnectProblemLabel.waitInk : ConnectProblemLabel.errorInk
            )
            .accessibilityIdentifier("connect.error")
            .transition(.opacity)
        }
    }
}

/// Figma "Pesan verdict" under the code (1681:4816): the symbol and SF Pro Rounded 13 / 18, 6 apart, left-aligned;
/// red #C81414 for a refusal, orange #C2610C for a wait.
private struct ConnectProblemLabel: View {
    static let errorInk = Color(hex: 0xC81414)
    static let waitInk = Color(hex: 0xC2610C)

    let text: Text
    var systemImage = "exclamationmark.triangle.fill"
    var tint = errorInk

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 16)
                .accessibilityHidden(true)
            text
                .onboardingFont(13, design: .rounded, tracking: -0.08, relativeTo: .footnote)
                .figmaLineHeight(18, relativeTo: .footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
    }
}

/// "Ketik ulang kode", "Masukkan kode saja": Figma #136CB7, SF Pro Semibold 17, left-aligned, 44 pt to tap.
private struct ConnectInlineLinkStyle: ButtonStyle {
    @Environment(\.shooReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onboardingFont(17, weight: .semibold, relativeTo: .body)
            .foregroundStyle(Color(hex: 0x136CB7))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1, anchor: .leading)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .padding(.vertical, -10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Figma "Terlalu banyak percobaan / pendaftaran" (1681:4787, 4824): the grey button counts down
/// ("Coba lagi dalam 04:59", or minutes when it's long) and turns back into Connect when the wait ends.
private struct WaitButton: View {
    let model: ConnectModel
    @Environment(\.shooReduceMotion) private var reduceMotion

    /// Waits of 10 minutes or more count in minutes ("59 menit"); shorter ones as mm:ss.
    static func label(seconds: Int) -> Text {
        if seconds >= 600 {
            let minutes = Int((Double(seconds) / 60).rounded(.up))
            return Text("Try again in \(minutes) minutes")
        }
        return Text("Try again in \(String(format: "%02d:%02d", seconds / 60, seconds % 60))")
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = model.secondsToWait(now: context.date) ?? 0
            Button {} label: {
                Self.label(seconds: seconds)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                    .animation(.snappy(duration: 0.3), value: seconds)
            }
            .buttonStyle(OnboardingCapsuleButtonStyle())
            .disabled(true)
            .accessibilityIdentifier("connect.wait")
        }
        .task(id: model.retryAt) {
            guard let retryAt = model.retryAt else { return }
            try? await Task.sleep(for: .seconds(max(0, retryAt.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            model.waitEnded()
        }
        // A light tap when Connect comes back.
        .sensoryFeedback(.impact(weight: .light), trigger: model.retryAt) { old, new in old != nil && new == nil }
    }
}

/// A wrong or expired code: three quick swings (±6 pt, 0.3 s) of the code boxes. Offset only, never layout.
/// Off with Reduce Motion: the error still fades in and the haptic still taps.
private struct ShakeOnProblem: ViewModifier {
    let trigger: Int
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { view, x in
                view.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(6, duration: 0.05)
                    LinearKeyframe(-6, duration: 0.1)
                    LinearKeyframe(6, duration: 0.1)
                    LinearKeyframe(0, duration: 0.05)
                }
            }
        } else {
            content
        }
    }
}

/// "Kode | Pindai QR": capsule track with a white thumb that slides (Figma "Segmented Control").
private struct ConnectTabs: View {
    @Binding var tab: ConnectView.Tab
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 4) {
            segment(.code, title: "Code", id: "connect.tab.code")
            segment(.scan, title: "Scan QR", id: "connect.tab.scan")
        }
        .padding(2)
        .background(Color(red: 0x76 / 255, green: 0x76 / 255, blue: 0x80 / 255).opacity(0.12), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connect.tabs")
    }

    private func segment(_ value: ConnectView.Tab, title: LocalizedStringKey, id: String) -> some View {
        let isSelected = tab == value
        return Button {
            withAnimation(.snappy(duration: 0.3)) { tab = value }
        } label: {
            Text(title)
                .onboardingFont(13.33, weight: isSelected ? .semibold : .medium, family: .sfPro, relativeTo: .footnote)
                .tracking(-0.08)
                .foregroundStyle(OnboardingTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(OnboardingTheme.card)
                            // Figma: #000 6 %, y 2, blur 20.
                            .shadow(color: .black.opacity(0.06), radius: 10, y: 2)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(id)
    }
}

/// Grey viewfinder with white corner marks around the camera (Figma "Frame 90" + "Group 1486").
private struct ScannerFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Rectangle().fill(Color(red: 0x77 / 255, green: 0x75 / 255, blue: 0x75 / 255).opacity(0.25))
            content
            CornerMarks()
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .square))
                .padding(.horizontal, 30)
                .padding(.vertical, 50)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .aspectRatio(354 / 433, contentMode: .fit)
        .frame(maxHeight: 433)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct CornerMarks: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 18
        var path = Path()
        for (corner, dx, dy) in [
            (CGPoint(x: rect.minX, y: rect.minY), length, length),
            (CGPoint(x: rect.maxX, y: rect.minY), -length, length),
            (CGPoint(x: rect.minX, y: rect.maxY), length, -length),
            (CGPoint(x: rect.maxX, y: rect.maxY), -length, -length),
        ] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx, y: corner.y))
        }
        return path
    }
}

/// Six digit boxes over one number-pad field: one VoiceOver element, paste and autofill still work.
private struct CodeField: View {
    @Binding var code: String
    /// Figma "Kode salah": every box gets the red ring.
    var isWrong = false
    /// Bumped from outside ("Ketik ulang kode", "Masukkan kode saja") to focus the field.
    var focusRequests = 0
    let onFocusChange: (Bool) -> Void
    @FocusState private var focused: Bool
    @Environment(\.shooReduceMotion) private var reduceMotion
    /// Grows with Dynamic Type; the boxes share the row, so six always fit an iPhone SE width.
    @ScaledMetric(relativeTo: .title2) private var digitSize: CGFloat = 26
    /// Figma "row": 72 pt tall (62 wide for its 5 boxes; 6 boxes share the same 342 pt row here).
    @ScaledMetric(relativeTo: .title2) private var boxHeight: CGFloat = 72

    var body: some View {
        ZStack {
            // No placeholder: it would show through the empty boxes. VoiceOver gets the label below.
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .focused($focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .accessibilityLabel(Text("6-digit code"))
                .accessibilityIdentifier("connect.code")
            HStack(spacing: 8) {
                let digits = Array(code)
                ForEach(0..<ConnectModel.codeLength, id: \.self) { index in
                    let isActive = focused && index == min(digits.count, ConnectModel.codeLength - 1)
                    ZStack {
                        if index < digits.count {
                            Text(verbatim: String(digits[index]))
                                // Figma uses Geist SemiBold 26, which the app doesn't bundle; SF Pro Display is closest.
                                .font(FigmaFont.font(size: min(digitSize, 34), weight: .semibold))
                                .foregroundStyle(OnboardingTheme.ink)
                        } else if isActive {
                            Caret(reduceMotion: reduceMotion)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: min(boxHeight, 96))
                    .background(OnboardingTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isWrong ? ConnectProblemLabel.errorInk : OnboardingTheme.ink.opacity(isActive ? 1 : 0.1), lineWidth: 1)
                    }
                    .animation(.easeOut(duration: 0.2), value: isWrong)
                }
            }
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onChange(of: focused) { _, isFocused in onFocusChange(isFocused) }
        .onChange(of: focusRequests) { focused = true }
        // After the sheet / page has settled: focus set mid-animation is often ignored.
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            if code.isEmpty { focused = true }
        }
    }
}

private struct Caret: View {
    let reduceMotion: Bool
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(OnboardingTheme.ink)
            .frame(width: 2, height: 26)
            .opacity(visible ? 1 : 0)
            .task {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(530))
                    visible.toggle()
                }
            }
    }
}

/// PR-02: who looks after this phone now (Figma "Berhasil Terhubung", 929:8067).
struct ProtectedByView: View {
    let guardian: GuardianInfo
    let onContinue: () -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var ownAvatarId: String?

    var body: some View {
        OnboardingSuccessPage(
            title: Text("Connected to \(guardian.name)!"),
            message: Text("You can now enjoy digital protection with your Guardian's support."),
            idPrefix: "protectedBy",
            onContinue: onContinue,
            background: "ConnectedBackground"
        ) {
            ConnectedOrbitIllustration(guardian: guardian, ownAvatarId: ownAvatarId)
                // Figma: the illustration at y 46, the headline at 402.
                .padding(.top, -16)
                .padding(.bottom, 17)
        }
        .task {
            do {
                ownAvatarId = try await env.repository.me().avatarId
            } catch {
                Log.ui.error("Own avatar for PR-02 failed", error)
            }
        }
    }
}

#Preview("Connect") {
    ConnectView(model: ConnectModel(repository: MockRepository()), onSkip: {}, onFinish: {})
}

#Preview("Connected") {
    ProtectedByView(guardian: GuardianInfo(deviceId: "dev_nis", name: "Nisrina", avatarId: "avatar_03"), onContinue: {})
        .environment(AppEnvironment.preview(mode: .protected))
}
