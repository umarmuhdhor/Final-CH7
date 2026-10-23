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
            #endif
            self.model = model
        }
    }
}

#if DEBUG
extension OnboardingFlow {
    /// `-debug.onboardingStep name|mode|greeting|connect|turnOnExtension|notifications`
    static var screenshotStep: OnboardingStep? {
        switch UserDefaults.standard.string(forKey: "debug.onboardingStep") {
        case "name": .name
        case "mode": .mode
        case "greeting": .greeting
        case "connect": .connect
        case "turnOnExtension": .turnOnExtension
        case "notifications": .notifications
        default: nil
        }
    }
}
#endif

private struct OnboardingStepView: View {
    let model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.step {
            case .splash: SplashView(model: model)
            case .name: NameView(model: model)
            case .mode: ModeView(model: model)
            case .greeting: GreetingView(model: model)
            case .connect: OnboardingConnectStep(model: model)
            case .turnOnExtension: TurnOnExtensionView(refreshStatus: model.refreshExtensionStatus)
            case .notifications: NotificationPermissionView(model: model)
            case .done: Color(.systemBackground)
            }
        }
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity)
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
    @State private var connect: ConnectModel?

    var body: some View {
        Group {
            if let connect {
                ConnectView(model: connect, onSkip: model.continueFromConnect, onFinish: model.continueFromConnect)
            } else {
                // An empty Group never appears, so `onAppear` below would never run.
                Color(.systemBackground)
            }
        }
        .onAppear {
            guard connect == nil else { return }
            connect = ConnectModel(repository: env.repository, code: env.router.takePendingJoinCode())
        }
        // An invite link opened while this screen is showing.
        .onChange(of: env.router.pendingJoinCode) { _, code in
            guard code != nil, let pending = env.router.takePendingJoinCode() else { return }
            connect?.prefill(pending)
        }
    }
}
