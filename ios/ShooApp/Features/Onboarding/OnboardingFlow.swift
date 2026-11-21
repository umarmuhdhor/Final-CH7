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
            // The splash has no demo link in Figma: the sample family opens from a launch argument.
            if UserDefaults.standard.bool(forKey: "debug.demo") { model.startDemo() }
            #endif
            if model.step == .done { env.finishOnboarding() }
            self.model = model
            Task { await model.resumeAfterRelaunch() }
        }
    }
}

#if DEBUG
extension OnboardingFlow {
    /// `-debug.onboardingStep name|turnOnExtension|safariDefault|extensionOn`
    static var screenshotStep: OnboardingStep? {
        switch UserDefaults.standard.string(forKey: "debug.onboardingStep") {
        case "name": .name
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

#Preview {
    let env = AppEnvironment.preview()
    env.settings.reset()
    return OnboardingFlow().environment(env)
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
                limited: model.registrationLimited,
                prepare: model.activateExtension
            )
        )
    }
}
