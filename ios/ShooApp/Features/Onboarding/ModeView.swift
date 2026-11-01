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
            // Figma: cards at y 280.
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
        .messageLineHeight(24)
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
    private var selectedStroke: Color {
        mode == .protected ? OnboardingTheme.selectedStrokeProtected : OnboardingTheme.selectedStroke
    }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { selection = mode }
        } label: {
            // Figma "Frame 5": 72 pt icon, 20, title row 28 (20 pt), 4, message rows of 20 (15 pt).
            // The icon image carries its own shadow: 1.8 pt above the tile, 10.8 below.
            VStack(spacing: 0) {
                Image(image)
                    .accessibilityHidden(true)
                Text(title)
                    .onboardingFont(20, relativeTo: .title3)
                    .tracking(-0.2)
                    .foregroundStyle(OnboardingTheme.ink)
                    .frame(minHeight: 28)
                    .padding(.top, 9.2)
                Text(message)
                    .onboardingFont(15, design: .rounded, relativeTo: .subheadline)
                    .lineSpacing(2)
                    .foregroundStyle(OnboardingTheme.bodyInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
            }
            .padding(.horizontal, 16)
            .padding(.top, 15.2)
            .padding(.bottom, 17)
            .frame(maxWidth: .infinity, minHeight: 198, alignment: .top)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.dynamic(0xF5FAFF, dark: 0x1B2230).opacity(0.86), OnboardingTheme.card.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    // Figma "Build progress": #784650 5% y 1 blur 2, #965A5F 6% y 6 blur 16.
                    .shadow(color: Color(hex: 0x784650, opacity: 0.05), radius: 1, y: 1)
                    .shadow(color: Color(hex: 0x965A5F, opacity: 0.06), radius: 8, y: 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    // Figma: 2 pt inside when chosen, blue for Guardian, teal for Protected.
                    .strokeBorder(isSelected ? selectedStroke : OnboardingTheme.cardStroke, lineWidth: isSelected ? 2 : 1)
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
