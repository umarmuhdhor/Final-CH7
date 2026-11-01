import SwiftUI
import UIKit

/// PR-03 (fase 26): "Got a family invite?" with the system Paste button, for an invite link copied on
/// the invite page before installing. Shows only when the pasteboard probably holds a web address; the
/// app reads it only when the user taps Paste (no "Allow Paste" prompt, SECURITY §3 P8).
struct InvitePasteCard: View {
    enum Style {
        /// U1 on the splash: a card with a title and why.
        case splash
        /// U2 on Connect: one line above the button.
        case connect
    }

    let style: Style
    let clipboard: InviteClipboard
    /// U4 under the button, worded by the screen.
    var problem: Text?
    let onPaste: ([String]) -> Void

    @Environment(\.scenePhase) private var scenePhase
    /// At accessibility text sizes only the title (or nothing on Connect) and the button: the card sits
    /// outside any scroll view and must not push the screen's own text away.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Always in the hierarchy (zero size when hidden) so `task` and the observers run.
        VStack(spacing: 0) {
            if clipboard.offersPaste || problem != nil {
                content
            }
        }
        .frame(maxWidth: .infinity)
        .task { await clipboard.refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await clipboard.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            Task { await clipboard.refresh() }
        }
    }

    private var content: some View {
        VStack(alignment: style == .splash ? .leading : .center, spacing: 12) {
            if style == .splash {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "link")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.link)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Got a family invite?")
                            .onboardingFont(17, weight: .semibold, relativeTo: .headline)
                            .foregroundStyle(OnboardingTheme.ink)
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text("Paste the invite link you copied before installing. Shoo only looks at it when you tap Paste.")
                                .onboardingFont(15, relativeTo: .subheadline)
                                .foregroundStyle(OnboardingTheme.secondaryInk)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
            } else if !dynamicTypeSize.isAccessibilitySize {
                Text("Copied an invite link?")
                    .onboardingFont(15, relativeTo: .subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            pasteButton
            if let problem {
                OnboardingErrorLabel(text: problem)
                    .accessibilityIdentifier("invite.paste.error")
            }
        }
        .padding(style == .splash ? 16 : 0)
        .frame(maxWidth: .infinity, alignment: style == .splash ? .leading : .center)
        .background {
            if style == .splash {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(OnboardingTheme.background)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(OnboardingTheme.cardStroke))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("invite.paste.card")
    }

    /// The system control: its label and language come from iOS; it greys out when the pasteboard holds no text.
    /// UI tests tap this same control (fase 26 spike S2, K6 a).
    private var pasteButton: some View {
        PasteButton(payloadType: String.self) { strings in
            Task { @MainActor in onPaste(strings) }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .accessibilityIdentifier("invite.paste.button")
    }
}
