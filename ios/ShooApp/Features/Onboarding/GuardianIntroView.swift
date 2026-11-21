import SwiftUI

/// Figma "To be guardian" (1229:1904): shown before Family mode turns on for the first time ("Menjadi
/// Guardian" on Profile, Home ⇆, Account mode). "Mulai" turns it on; Back keeps Pribadi.
struct GuardianIntroView: View {
    let onBack: () -> Void
    let onStart: () -> Void

    var body: some View {
        OnboardingFormPage(
            title: "Protect the people\nclosest to you",
            // C4 + F9 (goldfish 21 Nov): what the guardian sees, and that their own protection stays on.
            message: "Help look after the people closest to you. You'll see the sites blocked or warned about on their phones. Your own protection stays on.",
            onBack: onBack
        ) {
            FamilyCardIllustration()
        } content: {
            EmptyView()
        } footer: {
            Button("Get started", action: onStart)
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .accessibilityIdentifier("guardianIntro.start")
        }
        .largeHeadline()
        .headlineInset(45)
        .tealHeader()
    }
}

#Preview {
    GuardianIntroView(onBack: {}, onStart: {})
}
