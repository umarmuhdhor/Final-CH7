import SwiftUI

/// Guardian onboarding after ON-03 (Figma "Lindungi dirimu dan orang terdekat"): invite family now
/// with the QR / link sheet, or skip and invite later from Shield or Profile.
struct InviteFamilyView: View {
    let model: OnboardingModel
    @Environment(AppEnvironment.self) private var env
    @State private var isInvitePresented = false

    var body: some View {
        OnboardingFormPage(
            title: "Protect yourself and your loved ones",
            message: "Share an invite with a QR code or an invite link.",
            onBack: nil
        ) {
            OnboardingHeroImage(name: "ConnectedIllustration")
        } content: {
            EmptyView()
        } footer: {
            Button("Invite") { isInvitePresented = true }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .accessibilityIdentifier("invite.open")
            Button("Skip", action: model.continueFromInvite)
                .buttonStyle(OnboardingLinkButtonStyle(weight: .semibold))
                .accessibilityIdentifier("invite.skip")
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
