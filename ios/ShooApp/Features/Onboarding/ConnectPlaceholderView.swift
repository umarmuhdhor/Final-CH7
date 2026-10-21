import SwiftUI

/// Protected only, between ON-03 and ON-04. PR-01 (Scan QR / Enter code) arrives in fase 14.
// TODO(sync:alief): PR-01 — replace after fase 14
struct ConnectPlaceholderView: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingPage {
            OnboardingHeader(
                systemImage: "link.circle.fill",
                title: "Connect to your guardian",
                message: "Your guardian will show you a 4-digit code."
            )
            .padding(.top, 32)
        } footer: {
            OnboardingPrimaryButton(title: "Continue") { model.continueFromConnect() }
                .accessibilityIdentifier("connect.continue")
        }
    }
}
