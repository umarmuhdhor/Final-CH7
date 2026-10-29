import SwiftUI

/// ON-03: Guardian or Protected, saved for good. Saving registers the device (Figma "Choose Mode").
struct ModeView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        OnboardingFormPage(
            title: "Choose your mode",
            message: "Pick one mode to use Shoo",
            onBack: model.goBack
        ) {
            VStack(spacing: 16) {
                // Side by side as in Figma; stacked at accessibility sizes so words are not split (QA-A P2-2).
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 16))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                layout {
                    ModeCard(
                        mode: .guardian,
                        image: "ModeGuardian",
                        title: "Guardian",
                        message: "Protect myself and my loved ones",
                        selection: $model.selectedMode
                    )
                    ModeCard(
                        mode: .protected,
                        image: "ModeProtected",
                        title: "Protected",
                        message: "I'm protected by someone else",
                        selection: $model.selectedMode
                    )
                }

                Label { Text("You can't change this later.") } icon: { Image(systemName: "info.circle") }
                    .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                    .foregroundStyle(OnboardingTheme.secondaryInk)

                if model.registrationFailed {
                    Label { Text("Couldn't save. Check your connection and try again.") } icon: {
                        Image(systemName: "wifi.exclamationmark")
                    }
                    .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("mode.error")
                }
            }
            .padding(.top, 99)
        } footer: {
            Button {
                Task { await model.register() }
            } label: {
                ZStack {
                    Text("Next").opacity(model.isWorking ? 0 : 1)
                    if model.isWorking { ProgressView().tint(OnboardingTheme.onButton) }
                }
            }
            .buttonStyle(OnboardingCapsuleButtonStyle())
            // Stays dark while saving so the spinner is visible; `register()` ignores taps then.
            .disabled(model.selectedMode == nil)
            .accessibilityIdentifier("mode.continue")
        }
        .onChange(of: model.registrationFailed) { _, failed in
            if failed {
                AccessibilityNotification.Announcement(L10n.string("Couldn't save. Check your connection and try again.", language: language)).post()
            }
        }
    }
}

/// White card with the mode's icon tile; blue border when chosen (Figma "Build progress", 169 × 198).
private struct ModeCard: View {
    let mode: UserMode
    let image: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @Binding var selection: UserMode?

    private var isSelected: Bool { selection == mode }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { selection = mode }
        } label: {
            VStack(spacing: 0) {
                Image(image)
                    .accessibilityHidden(true)
                Text(title)
                    .onboardingFont(20, relativeTo: .title3)
                    .tracking(-0.2)
                    .foregroundStyle(OnboardingTheme.ink)
                    .padding(.top, 7)
                Text(message)
                    .onboardingFont(15, design: .rounded, relativeTo: .subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 17)
            .padding(.top, 17)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, minHeight: 198, alignment: .top)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.dynamic(0xF5FAFF, dark: 0x1B2230).opacity(0.86), OnboardingTheme.card.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isSelected ? OnboardingTheme.selectedStroke : OnboardingTheme.cardStroke, lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("mode.\(mode.rawValue)")
    }
}

#Preview {
    let env = AppEnvironment.preview()
    env.settings.reset()
    let model = OnboardingModel(environment: env)
    model.skipSplash()
    model.name = "Rina"
    model.submitName()
    return ModeView(model: model).environment(env)
}
