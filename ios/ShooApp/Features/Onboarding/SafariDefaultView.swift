import SwiftUI

/// Figma "Jadikan Safari Default". Shoo only runs in Safari, but no API says which browser is the default,
/// so this asks instead of checking. Settings paths per iOS version are BELUM DIVERIFIKASI on device.
enum SafariDefaultSetup {
    enum Step: Equatable, CaseIterable {
        case tapOpen
        case tapBrowserApp
        case openDefaultApps
        case openAppsSafari
        case openSafariLegacy
        case comeBack
    }

    static func steps(for version: OperatingSystemVersion) -> [Step] {
        let pick: Step
        switch (version.majorVersion, version.minorVersion) {
        case (18, 3...), (19..., _): pick = .tapBrowserApp
        case (18, 2): pick = .openDefaultApps
        case (18, _): pick = .openAppsSafari
        default: pick = .openSafariLegacy
        }
        return [.tapOpen, pick, .comeBack]
    }

    /// iOS 18.3+ opens the Default Apps page; before that only Shoo's own page in Settings exists.
    @MainActor
    static func openSettings() async {
        let address: String
        if #available(iOS 18.3, *) {
            address = UIApplication.openDefaultApplicationsSettingsURLString
        } else {
            address = UIApplication.openSettingsURLString
        }
        if let url = URL(string: address) {
            await UIApplication.shared.open(url)
        }
    }
}

extension SafariDefaultSetup.Step {
    var text: LocalizedStringKey {
        switch self {
        case .tapOpen: "Tap the button below to open Settings."
        case .tapBrowserApp: "Tap Browser App, then choose Safari."
        case .openDefaultApps: "Go to Apps › Default Apps › Browser App, then choose Safari."
        case .openAppsSafari: "Go to Apps › Safari › Default Browser App, then choose Safari."
        case .openSafariLegacy: "Go to Safari › Default Browser App, then choose Safari."
        case .comeBack: "Go back to Shoo, then tap Keep going."
        }
    }
}

/// The button opens Settings; once the user is back it turns into "Keep going".
struct SafariDefaultView: View {
    let onBack: () -> Void
    let onContinue: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var openedSettings = false
    @State private var cameBack = false
    @State private var isVideoPresented = false

    private let steps = SafariDefaultSetup.steps(for: ProcessInfo.processInfo.operatingSystemVersion)

    var body: some View {
        OnboardingFormPage(title: "Set Safari as default", onBack: onBack) {
            // Figma "image 1" at y 72.5, the headline right under it at 373.
            OnboardingHeroImage(name: "SafariDefaultIllustration", top: 10.5, bottom: 0.5)
        } content: {
            // Figma "stack": 16 between rows, 40 under the headline.
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    OnboardingStepRow(number: index + 1, text: step.text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 40)
        } footer: {
            if cameBack {
                Button("Keep going", action: onContinue)
                    .buttonStyle(OnboardingCapsuleButtonStyle())
                    .accessibilityIdentifier("safariDefault.continue")
            } else {
                Button("Make Safari default") {
                    openedSettings = true
                    Task { await SafariDefaultSetup.openSettings() }
                }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .accessibilityIdentifier("safariDefault.open")
            }
            OnboardingTutorialLink { isVideoPresented = true }
                .accessibilityIdentifier("safariDefault.video")
        }
        .footerEndsWithLink()
        .largeHeadline()
        // Figma "Frame 2": 354 wide, one line.
        .headlineInset(24)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, openedSettings { cameBack = true }
        }
        .fullScreenCover(isPresented: $isVideoPresented) {
            TutorialVideoPlayer()
        }
    }
}

#Preview {
    SafariDefaultView(onBack: {}, onContinue: {})
}
