import SwiftUI

/// ON-01 … ON-05 until the device is registered and onboarding is finished; then `RootView` shows the tabs.
struct OnboardingFlow: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: OnboardingModel?

    var body: some View {
        Group {
            if let model {
                OnboardingStepView(model: model)
            } else {
                Color(.systemBackground)
            }
        }
        .onAppear {
            guard model == nil else { return }
            let model = OnboardingModel(environment: env)
            #if DEBUG
            if let step = Self.screenshotStep { model.showForScreenshot(step) }
            if UserDefaults.standard.string(forKey: "debug.onboardingStep") == "connected" { model.connect().showJoinedForScreenshot() }
            // The splash has no demo link in Figma: the sample family opens from a launch argument.
            if UserDefaults.standard.bool(forKey: "debug.demo") { model.startDemo() }
            #endif
            if model.step == .done { env.finishOnboarding() }
            self.model = model
        }
    }
}

#if DEBUG
extension OnboardingFlow {
    /// `-debug.onboardingStep name|consent|connect|connected|turnOnExtension|safariDefault|extensionOn`
    static var screenshotStep: OnboardingStep? {
        switch UserDefaults.standard.string(forKey: "debug.onboardingStep") {
        case "name": .name
        case "consent": .consent
        case "connect", "connected": .connect
        case "turnOnExtension": .turnOnExtension
        case "safariDefault": .safariDefault
        case "extensionOn": .extensionOn
        default: nil
        }
    }
}
#endif

private struct OnboardingStepView: View {
    let model: OnboardingModel
    @Environment(\.shooReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.step {
            case .splash: SplashView(model: model)
            case .name: NameView(model: model)
            case .consent: DataConsentView(onBack: { model.goBack() }, onAnswer: { model.answerConsent($0) })
            case .connect: OnboardingConnectStep(model: model)
            case .turnOnExtension: OnboardingExtensionStep(model: model)
            case .safariDefault: SafariDefaultView(onBack: model.goBack, onContinue: model.continueFromSafariDefault)
            case .extensionOn: ExtensionOnView { Task { await model.requestNotifications() } }
            case .done: Color(.systemBackground)
            }
        }
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .move(edge: model.movedBack ? .leading : .trailing),
                    removal: .move(edge: model.movedBack ? .trailing : .leading)
                ).combined(with: .opacity)
        )
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth, value: model.step)
    }
}

/// Bottom call-to-action shared by every onboarding screen: full width, at least 44 pt, grows with text.
struct OnboardingPrimaryButton: View {
    let title: LocalizedStringKey
    var isWorking = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isWorking ? 0 : 1)
                if isWorking { ProgressView() }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
    }
}

/// Large symbol + title + one short sentence (persona: parents 45–65, PRD §3). Re-skin when illustrations arrive.
struct OnboardingHeader: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Scrollable content with the button pinned at the bottom, so nothing clips at large text sizes.
struct OnboardingPage<Content: View, Footer: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        ScrollView {
            content
                .padding(24)
                .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) { footer }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    env.settings.reset()
    return OnboardingFlow().environment(env)
}

/// PR-01 inside onboarding (Protected): join now, or "Not now" and connect later from Shield.
private struct OnboardingConnectStep: View {
    let model: OnboardingModel
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ConnectView(
            model: model.connect(),
            onBack: model.canGoBackFromConnect ? { Task { await model.backFromConnect() } } as (() -> Void)? : nil,
            onSkip: { Task { await model.skipConnect() } },
            onFinish: model.continueFromConnect
        )
        // An invite link opened while this screen is showing.
        .onChange(of: env.router.pendingJoinCode) { _, code in
            guard code != nil, let pending = env.router.takePendingJoinCode() else { return }
            model.connect().prefill(pending)
        }
    }
}

/// ON-04 inside onboarding: the consent checkbox (only while the question is unanswered) gates the button,
/// and the first tap registers the device.
private struct OnboardingExtensionStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        TurnOnExtensionView(
            refreshStatus: model.refreshExtensionStatus,
            onBack: model.canGoBackFromExtension ? { model.goBack() } as (() -> Void)? : nil,
            onSkipCheck: { Task { await model.skipExtensionCheck() } },
            consent: OnboardingExtensionConsent(
                isChecked: $model.consentChecked,
                showsCheckbox: model.showsConsentCheckbox,
                isWorking: model.isWorking,
                failed: model.registrationFailed,
                prepare: model.activateExtension
            )
        )
    }
}
