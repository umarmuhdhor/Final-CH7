import SwiftUI

/// The server no longer knows this iPhone (401), or its token didn't come along from a backup.
/// MVP answer (SECURITY T3, P1): say so plainly and start onboarding again.
struct SessionExpiredView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        OnboardingPage {
            OnboardingHeader(
                systemImage: "person.crop.circle.badge.exclamationmark",
                title: "Session expired",
                message: "This iPhone isn't connected to Shoo anymore. Set it up again to stay protected."
            )
            .padding(.top, 32)
            .accessibilityIdentifier("sessionExpired")
        } footer: {
            OnboardingPrimaryButton(title: "Start again") { env.restartOnboarding() }
                .accessibilityIdentifier("sessionExpired.restart")
        }
    }
}

#Preview {
    SessionExpiredView().environment(AppEnvironment.preview())
}
