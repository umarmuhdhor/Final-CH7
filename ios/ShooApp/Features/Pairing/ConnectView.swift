import SwiftUI

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
    @State private var tab: Tab = .code
    @State private var scanRefused = false
    @State private var codeFocused = false

    var body: some View {
        if case .joined(let guardian) = model.state {
            ProtectedByView(guardian: guardian, onContinue: onFinish)
        } else {
            form
        }
    }

    private static let codeFieldID = "connect.codeField"

    private var language: AppLanguage { AppLanguage(locale: locale) }

    private var form: some View {
        OnboardingFormPage(
            title: "Connect your account",
            message: "Scan the QR or enter the invite code from your Guardian.",
            onBack: onBack.map { back in { if model.state != .joining { back() } } },
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
                            OnboardingErrorLabel(text: Text("That QR code isn't a Shoo family code."))
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
                        VStack(spacing: 12) {
                            CodeField(code: Binding(get: { model.code }, set: { model.code = $0 }), onFocusChange: { codeFocused = $0 })
                            problemLabel
                        }
                        .id(Self.codeFieldID)
                    }
                    .padding(.top, 39)
                }
            }
        } footer: {
            // fase 18 K17: said before joining, since copies are only made while connected.
            Label {
                Text("Shoo keeps a copy of pages it blocks or warns you about for 14 days, so your Guardian can see the evidence.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .onboardingFont(13, design: .rounded, relativeTo: .footnote)
            .foregroundStyle(OnboardingTheme.secondaryInk)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("connect.copyNote")
            if tab == .code {
                Button {
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
                    .disabled(model.state == .joining)
                    .accessibilityIdentifier("connect.skip")
            }
        }
        .footerEndsWithLink(onSkip != nil)
        .headlineInset(24)
        .onChange(of: tab) { scanRefused = false }
        .onChange(of: scanRefused) { _, refused in
            guard refused else { return }
            AccessibilityNotification.Announcement(L10n.string("That QR code isn't a Shoo family code.", language: language)).post()
        }
        .onChange(of: model.problem) { _, problem in
            guard let problem else { return }
            AccessibilityNotification.Announcement(L10n.string(problem.message, language: language)).post()
        }
    }

    @ViewBuilder
    private var problemLabel: some View {
        if let problem = model.problem {
            OnboardingErrorLabel(
                text: Text(verbatim: L10n.string(problem.message, language: language)),
                systemImage: problem == .expired ? "clock.arrow.circlepath" : "exclamationmark.circle"
            )
            .accessibilityIdentifier("connect.error")
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
                            .strokeBorder(OnboardingTheme.ink.opacity(isActive ? 1 : 0.1), lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onChange(of: focused) { _, isFocused in onFocusChange(isFocused) }
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
