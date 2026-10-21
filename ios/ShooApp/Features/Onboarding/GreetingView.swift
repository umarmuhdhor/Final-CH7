import SwiftUI

/// After ON-03: "Hi, [name]" with the random avatar the server picked (D-alief-22, not initials).
struct GreetingView: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingPage {
            VStack(spacing: 20) {
                AvatarView(id: model.avatarId ?? "", size: 128, name: model.registeredName)
                    .accessibilityIdentifier("greeting.avatar")
                    .padding(.top, 32)
                Text("Hi, \(model.registeredName)!")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("This is your avatar. Your family will see it next to your name.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } footer: {
            OnboardingPrimaryButton(title: "Continue") { model.continueFromGreeting() }
                .accessibilityIdentifier("greeting.continue")
        }
    }
}
