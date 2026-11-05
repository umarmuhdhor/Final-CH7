import SwiftUI

/// Apple 5.1.1(ii) and 5.1.2(i): says what leaves the phone, and that a third-party AI gets some of it, and
/// asks before the first check. Shown once in onboarding, and to a device registered before the question
/// existed. `DataConsent` holds the answer; Profile changes it later.
struct DataConsentView: View {
    /// `nil` for a registered device: there is no step to go back to.
    let onBack: (() -> Void)?
    let onAnswer: (DataConsent) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    var body: some View {
        OnboardingFormPage(
            title: "Before you start",
            message: "Shoo checks the pages you open in Safari. This is what leaves your iPhone.",
            onBack: onBack
        ) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                row(
                    "doc.text.magnifyingglass", title: "Pages you open",
                    text: "With the online check on, Shoo's server reads the page's text, form field names and address without the part after “?”. Text you type is not sent. Pages scored under 30 are not stored."
                )
                row(
                    "exclamationmark.shield", title: "Risky pages",
                    text: "Shoo keeps the address, a copy of the page and the flagged parts. You and your Guardian can see them. Some of this stays after you delete your account."
                )
                row(
                    "sparkles", title: "AI check by DeepSeek",
                    text: "With the online check on, Shoo's server may send DeepSeek, an AI company in China, a short summary of a suspicious page: site name, page title and form field names."
                )
                Button("Read the privacy policy") {
                    openURL(AppConfig.legalPage("privacy", language: AppLanguage(locale: locale)))
                }
                .buttonStyle(OnboardingLinkButtonStyle(weight: .semibold))
                .accessibilityIdentifier("consent.privacy")
            }
            .padding(.top, 20)
        } footer: {
            Button("Allow online check") { onAnswer(.granted) }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .accessibilityIdentifier("consent.allow")
            Button("Continue without it") { onAnswer(.declined) }
                .buttonStyle(OnboardingLinkButtonStyle(weight: .semibold))
                .accessibilityIdentifier("consent.decline")
            Text("Without it, Shoo checks pages on your iPhone only and protects you less. Risky pages are still reported. You can change this in Profile.")
                .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                .foregroundStyle(OnboardingTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .footerEndsWithLink()
        .largeHeadline()
    }

    private func row(_ symbol: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .onboardingFont(16, weight: .semibold, design: .rounded, relativeTo: .body)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .onboardingFont(14, design: .rounded, relativeTo: .subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    DataConsentView(onBack: {}) { _ in }
}
