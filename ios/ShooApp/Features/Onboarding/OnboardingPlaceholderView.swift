import SwiftUI

/// Stand-in until fase 02 builds ON-01…ON-05. Lets the mode be picked so the tabs can be reached.
struct OnboardingPlaceholderView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Shoo")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Scam sites, shooed away.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    env.completeOnboarding(mode: .guardian)
                } label: {
                    Text("I'm a Guardian")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    env.completeOnboarding(mode: .protected)
                } label: {
                    Text("I'm Protected")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
    }
}

#Preview {
    OnboardingPlaceholderView().environment(AppEnvironment.preview())
}
