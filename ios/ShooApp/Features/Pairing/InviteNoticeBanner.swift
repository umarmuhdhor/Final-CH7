import SwiftUI

/// PR-03: what Home says about an invite link opened after onboarding (Figma "Flow · Protected buka link
/// undangan", "Notif undangan"). A card at the top of Home; nothing joins until the Hubungkan tap (T11).
struct InviteNoticeBanner: View {
    let notice: InviteNotice
    let router: Router

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image("ShooLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            buttons
        }
        .padding(16)
        // Near solid, so the text keeps its contrast over the blue hero (Figma "Notif undangan": white 97 %).
        .background(Color(.systemBackground).opacity(0.97), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("invite.notice")
    }

    private var title: LocalizedStringKey {
        switch notice {
        case .invited: "You've got a family invite"
        case .hasMembers: "You can't join another family yet"
        case .alreadyProtected(let guardian): "You're already protected by \(guardian)"
        }
    }

    private var message: LocalizedStringKey {
        switch notice {
        case .invited: "Join as Protected so your guardian can help check suspicious sites."
        case .hasMembers: "You still protect someone. Disconnect them in Profile first, then open the link again."
        case .alreadyProtected(let guardian): "Only \(guardian) can disconnect you. This invite won't be used."
        }
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 10) {
            switch notice {
            case .invited:
                secondary("Not now", id: "invite.notice.later") { router.dismissInviteNotice() }
                primary("View", id: "invite.notice.view") { router.acceptInvite() }
            case .hasMembers:
                secondary("Close", id: "invite.notice.close") { router.dismissInviteNotice() }
                primary("Open Profile", id: "invite.notice.profile") { router.openProfileFromInviteNotice() }
            case .alreadyProtected:
                primary("OK", id: "invite.notice.ok") { router.dismissInviteNotice() }
            }
        }
    }

    /// The app's navy pill (`OnboardingTheme.buttonGradient`), 44 pt tall to fit the card.
    private func primary(_ title: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(OnboardingTheme.onButton)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(OnboardingTheme.buttonGradient))
                .contentShape(Capsule())
        }
        .buttonStyle(OnboardingPressButtonStyle())
        .accessibilityIdentifier(id)
    }

    private func secondary(_ title: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
                .contentShape(Capsule())
        }
        .buttonStyle(OnboardingPressButtonStyle())
        .accessibilityIdentifier(id)
    }
}

#Preview("Invited") {
    ZStack(alignment: .top) {
        Color.blue.opacity(0.3).ignoresSafeArea()
        InviteNoticeBanner(notice: .invited, router: Router())
    }
}

#Preview("Already protected") {
    ZStack(alignment: .top) {
        Color.blue.opacity(0.3).ignoresSafeArea()
        InviteNoticeBanner(notice: .alreadyProtected(guardian: "Nisrina"), router: Router())
    }
}
