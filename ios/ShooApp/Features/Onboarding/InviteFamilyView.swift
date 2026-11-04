import SwiftUI

/// Guardian onboarding after ON-03 (Figma "Lindungi dirimu dan orang terdekat"): invite family now
/// with the QR / link sheet, or skip and invite later from Shield or Profile. Either one saves the mode.
struct InviteFamilyView: View {
    let model: OnboardingModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @State private var isInvitePresented = false

    private var onBack: (() -> Void)? {
        guard model.canGoBackToMode else { return nil }
        return { model.goBack() }
    }

    var body: some View {
        OnboardingFormPage(
            title: "Protect yourself and your loved ones",
            message: "Share an invite with a QR code or an invite link.",
            onBack: onBack
        ) {
            FamilyCardIllustration()
        } content: {
            if model.registrationFailed {
                OnboardingErrorLabel(text: Text("Couldn't save. Check your connection and try again."), systemImage: "wifi.exclamationmark")
                    .padding(.top, 16)
                    .accessibilityIdentifier("invite.error")
            }
        } footer: {
            Button {
                Task {
                    if await model.prepareInvite() { isInvitePresented = true }
                }
            } label: {
                ZStack {
                    Text("Invite").opacity(model.isWorking ? 0 : 1)
                    if model.isWorking { ProgressView().tint(OnboardingTheme.onButton) }
                }
            }
            .buttonStyle(OnboardingCapsuleButtonStyle())
            .accessibilityIdentifier("invite.open")
            Button("Skip") { Task { await model.skipInvite() } }
                .buttonStyle(OnboardingLinkButtonStyle(weight: .semibold))
                .accessibilityIdentifier("invite.skip")
        }
        .footerEndsWithLink()
        .largeHeadline()
        .headlineInset(45)
        .onChange(of: model.registrationFailed) { _, failed in
            guard failed else { return }
            AccessibilityNotification.Announcement(
                L10n.string("Couldn't save. Check your connection and try again.", language: AppLanguage(locale: locale))
            ).post()
        }
        .sheet(isPresented: $isInvitePresented) {
            InviteSheet(repository: env.repository) {
                isInvitePresented = false
                model.continueFromInvite()
            }
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    let model = OnboardingModel(environment: env)
    return InviteFamilyView(model: model).environment(env)
}
