import SwiftUI

/// Figma "To be guardian" (1229:1904): shown before Family mode turns on for the first time ("Menjadi
/// Guardian" on Profile, Home ⇆, Account mode). "Mulai" turns it on; Back keeps Pribadi.
struct GuardianIntroView: View {
    let onBack: () -> Void
    let onStart: () -> Void

    var body: some View {
        OnboardingFormPage(
            title: "Protect the people\nclosest to you",
            message: "Protect them by double-checking what Shoo finds for the people closest to you!",
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
