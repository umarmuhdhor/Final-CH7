import SwiftUI

/// PR-01: connect to the guardian by Scan QR or Enter code, then PR-02 "You're protected by …".
/// Used in onboarding (with "Not now") and from Shield / an invite link after onboarding.
struct ConnectView: View {
    let model: ConnectModel
    /// Onboarding only: continue without a guardian for now.
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

    var body: some View {
        if case .joined(let guardian) = model.state {
            ProtectedByView(guardian: guardian, onContinue: onFinish)
        } else {
            form
        }
    }

    private static let codeFieldID = "connect.codeField"

    /// The keyboard and the pinned footer cover the lower half: keep the digits in sight.
    private func showCodeField(_ proxy: ScrollViewProxy) {
        Task {
            // After the keyboard has slid up and the footer has moved.
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation { proxy.scrollTo(Self.codeFieldID, anchor: .bottom) }
        }
    }

    private var form: some View {
        OnboardingPage {
            ScrollViewReader { proxy in
                VStack(spacing: 24) {
                    OnboardingHeader(
                        systemImage: "link.circle.fill",
                        title: "Connect to your guardian",
                        message: "Scan the QR code on your guardian's phone, or enter the 4-digit code."
                    )
                    Picker(selection: $tab) {
                        Text("Scan QR").tag(Tab.scan)
                        Text("Enter code").tag(Tab.code)
                    } label: {
                        Text("How to connect")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("connect.tabs")
                    switch tab {
                    case .scan:
                        QRScannerView { payload in
                            if model.scanned(payload) {
                                scanRefused = false
                                tab = .code
                            } else {
                                scanRefused = true
                            }
                        }
                        if scanRefused {
                            Text("That QR code isn't a Shoo family code.")
                                .foregroundStyle(Color.readableRed)
                        }
                    case .code:
                        CodeField(code: Binding(get: { model.code }, set: { model.code = $0 }), onFocus: { showCodeField(proxy) })
                            .id(Self.codeFieldID)
                    }
                }
                .padding(.top, 16)
                // The footer grows with the message: the digits stay above it.
                .onChange(of: model.problem) { _, problem in
                    if problem != nil { showCodeField(proxy) }
                }
            }
        } footer: {
            if tab == .code {
                // In the footer, so the keyboard never hides it.
                if let problem = model.problem {
                    Text(verbatim: L10n.string(problem.message, language: AppLanguage(locale: locale)))
                        .font(.callout)
                        .foregroundStyle(Color.readableRed)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("connect.error")
                }
                OnboardingPrimaryButton(title: "Connect", isWorking: model.state == .joining) {
                    Task { await model.join() }
                }
                .disabled(!model.canJoin)
                .accessibilityIdentifier("connect.join")
            }
            if let onSkip {
                Button(action: onSkip) {
                    Text("Not now").frame(maxWidth: .infinity, minHeight: 44)
                }
                // A join already sent finishes on the server: wait for its answer (PR-02).
                .disabled(model.state == .joining)
                .accessibilityIdentifier("connect.skip")
            }
        }
        .onChange(of: tab) { scanRefused = false }
        .onChange(of: scanRefused) { _, refused in
            guard refused else { return }
            AccessibilityNotification.Announcement(L10n.string("That QR code isn't a Shoo family code.", language: AppLanguage(locale: locale))).post()
        }
        .onChange(of: model.problem) { _, problem in
            guard let problem else { return }
            AccessibilityNotification.Announcement(L10n.string(problem.message, language: AppLanguage(locale: locale))).post()
        }
    }
}

/// Four digit boxes over one number-pad field: one VoiceOver element, paste and autofill still work.
private struct CodeField: View {
    @Binding var code: String
    let onFocus: () -> Void
    @FocusState private var focused: Bool
    /// Grows with Dynamic Type, capped so four boxes fit an iPhone SE width.
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize: CGFloat = 36
    private var boxWidth: CGFloat { min(digitSize * 1.67, 72) }

    var body: some View {
        ZStack {
            TextField(text: $code) { Text("4-digit code") }
                .keyboardType(.numberPad)
                .focused($focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .accessibilityLabel(Text("4-digit code"))
                .accessibilityIdentifier("connect.code")
            HStack(spacing: 12) {
                ForEach(0..<ConnectModel.codeLength, id: \.self) { index in
                    let digits = Array(code)
                    Text(verbatim: index < digits.count ? String(digits[index]) : "")
                        .font(.system(size: min(digitSize, 44), weight: .bold, design: .monospaced))
                        .frame(width: boxWidth, height: boxWidth * 1.2)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(focused && index == min(digits.count, ConnectModel.codeLength - 1) ? Color.accentColor : .clear, lineWidth: 2)
                        )
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onChange(of: focused) { _, isFocused in
            if isFocused { onFocus() }
        }
        // After the sheet / page has settled: focus set mid-animation is often ignored.
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            if code.isEmpty { focused = true }
        }
    }
}

/// PR-02: who looks after this phone now.
struct ProtectedByView: View {
    let guardian: GuardianInfo
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage {
            VStack(spacing: 20) {
                AvatarView(id: guardian.avatarId, size: 128, name: guardian.name)
                    .padding(.top, 32)
                Text("You're protected by \(guardian.name)")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("protectedBy.title")
                Text("\(guardian.name) will be told when you open a risky site, and can check it for you.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } footer: {
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
                .accessibilityIdentifier("protectedBy.continue")
        }
    }
}
