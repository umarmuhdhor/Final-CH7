import SwiftUI

/// PR-01: connect to the guardian by Scan QR or Code, then PR-02 "Connected to …" (Figma "Connect with Guardian").
/// Used in onboarding (with "Not now") and from Shield / an invite link after onboarding.
struct ConnectView: View {
    let model: ConnectModel
    /// After onboarding only (sheet): close. Inside onboarding there is no way back, the mode is saved.
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
                ConnectTabs(tab: $tab)
                    .padding(.top, 23)

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
                    VStack(spacing: 24) {
                        Text("Enter the invite code")
                            .onboardingBodyStyle()
                        VStack(spacing: 12) {
                            CodeField(code: Binding(get: { model.code }, set: { model.code = $0 }), onFocusChange: { codeFocused = $0 })
                            problemLabel
                        }
                        .id(Self.codeFieldID)
                    }
                    .padding(.top, 64)
                }
            }
        } footer: {
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

/// "Pindai QR | Kode": capsule track with a white thumb that slides (Figma "Segmented Control").
private struct ConnectTabs: View {
    @Binding var tab: ConnectView.Tab
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 4) {
            segment(.scan, title: "Scan QR", id: "connect.tab.scan")
            segment(.code, title: "Code", id: "connect.tab.code")
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
                .onboardingFont(13.33, weight: isSelected ? .semibold : .medium, relativeTo: .footnote)
                .tracking(-0.08)
                .foregroundStyle(OnboardingTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(OnboardingTheme.card)
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
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
    @ScaledMetric(relativeTo: .title2) private var digitSize: CGFloat = 24
    private var boxWidth: CGFloat { min(max(46, digitSize * 2), 56) }

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
            HStack(spacing: 6) {
                let digits = Array(code)
                ForEach(0..<ConnectModel.codeLength, id: \.self) { index in
                    let isActive = focused && index == min(digits.count, ConnectModel.codeLength - 1)
                    ZStack {
                        if index < digits.count {
                            Text(verbatim: String(digits[index]))
                                .font(.system(size: min(digitSize, 32), weight: .semibold, design: .rounded))
                                .foregroundStyle(OnboardingTheme.ink)
                        } else if isActive {
                            Caret(reduceMotion: reduceMotion)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .aspectRatio(62 / 72, contentMode: .fit)
                    .frame(maxWidth: boxWidth)
                    .background(OnboardingTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(OnboardingTheme.ink.opacity(isActive ? 1 : 0.1), lineWidth: 1)
                    }
                }
            }
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

/// PR-02: who looks after this phone now (Figma "Berhasil Terhubung").
struct ProtectedByView: View {
    let guardian: GuardianInfo
    let onContinue: () -> Void

    var body: some View {
        OnboardingSuccessPage(
            title: Text("Connected to \(guardian.name)!"),
            message: Text("Your account is connected. You now get online protection with your Guardian's support."),
            idPrefix: "protectedBy",
            onContinue: onContinue
        ) {
            Image("ConnectedIllustration")
                .resizable()
                .scaledToFit()
                .frame(width: 300, height: 300)
                .overlay(alignment: .topLeading) {
                    // Sits on the "+" badge of the illustration.
                    AvatarView(id: guardian.avatarId, size: 55)
                        .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
                        .offset(x: 198.5, y: 186.5)
                }
                .accessibilityHidden(true)
        }
    }
}

#Preview("Connect") {
    ConnectView(model: ConnectModel(repository: MockRepository()), onSkip: {}, onFinish: {})
}

#Preview("Connected") {
    ProtectedByView(guardian: GuardianInfo(deviceId: "dev_nis", name: "Nisrina", avatarId: "avatar_03"), onContinue: {})
}
