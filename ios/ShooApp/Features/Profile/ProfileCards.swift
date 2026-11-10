import SwiftUI
import UIKit

/// PF-01 cards from the updated Figma: the Protected "Terhubung" pill, the Pribadi "Mode Guardian"
/// card and the Guardian "Belum ada yang Anda lindungi" card. Values are the Figma ones.

/// Orange capsule on the Protected profile card (Figma "Bagikan Undangan" → "Terhubung").
struct ConnectedPillButtonStyle: ButtonStyle {
    static let gradient = LinearGradient(
        stops: [
            .init(color: Color(hex: 0xF5B94D), location: 0),
            .init(color: Color(hex: 0xFC9C7F), location: 0.37),
            .init(color: Color(hex: 0xFD8F7F), location: 0.68),
            .init(color: Color(hex: 0xFF6F5B), location: 0.99),
        ],
        // Figma's transform stretches the gradient to 2.67 × the pill (x scale 0.374): only its
        // orange-to-salmon start shows.
        startPoint: .leading, endPoint: UnitPoint(x: 1 / 0.37387, y: 0.5)
    )

    /// Figma 455:10289, 138.6 × 41: 5 / 15 inside a 3.5 pt white ring that counts in the layout,
    /// "Terhubung" in SF Pro Rounded 17 on a 140 % line.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .profileValue()
            .foregroundStyle(.white)
            .padding(.horizontal, 18.5)
            .padding(.vertical, 8.5)
            .background(Self.gradient, in: Capsule())
            .overlay(Capsule().strokeBorder(ProfileStyle.card, lineWidth: 3.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    /// Figma's glyph (455:10401), exported from the design: a phone beside a stack.
    static var glyph: some View {
        Image("ProfileConnectedGlyph")
            .renderingMode(.template)
            .resizable()
            .frame(width: 44 / 3, height: 47 / 3)
            .frame(width: 19, height: 18)
            .accessibilityHidden(true)
    }
}

/// The guardian's initial at the avatar's lower right (Figma "Avatar/S", 42 pt, white ring).
struct GuardianBadge: View {
    let name: String
    let avatarId: String

    var body: some View {
        InitialsAvatar(name: name, avatarId: avatarId, size: 42)
            .overlay(Circle().stroke(ProfileStyle.card, lineWidth: 2.5))
    }
}

// MARK: Mode Guardian (Pribadi)

/// Figma "CTA Jadi Guardian" (1205:6288): invites a Pribadi user to protect their family. X hides it for good.
struct GuardianModeCard: View {
    let onBecomeGuardian: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ModeOfferCard(
            eyebrow: "GUARDIAN MODE",
            title: "Protect the people closest to you",
            message: "Help check suspicious sites your family opens.",
            action: "Become a Guardian",
            identifier: "profile.guardianCard",
            onAction: onBecomeGuardian,
            onDismiss: onDismiss
        )
        .padding(.horizontal, ProfileStyle.margin)
        .padding(.top, 32)
    }
}

/// Figma "Mode Terawasi" (Home Pribadi 1253:8803, Guardian Home 1279:9544): connect to a guardian, who then
/// double-checks risky sites. On Home Pribadi X hides it for good; the Guardian Home one has no X.
struct BecomeSupervisedCard: View {
    /// "Hubungkan" on Home Pribadi, "Menjadi yang Terawasi" on the empty Guardian Home.
    var action: LocalizedStringKey = "Connect"
    let onConnect: () -> Void
    var onDismiss: (() -> Void)?

    var body: some View {
        ModeOfferCard(
            eyebrow: "SUPERVISED MODE",
            title: "Not sure?",
            message: "Connect so someone you love can double-check for you",
            action: action,
            identifier: "home.becomeSupervised",
            onAction: onConnect,
            onDismiss: onDismiss
        )
    }
}

/// The card both offers share: eyebrow, title, two lines, a dark pill, the teal glass shield on the right.
struct ModeOfferCard: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let action: LocalizedStringKey
    let identifier: String
    let onAction: () -> Void
    var onDismiss: (() -> Void)?

    private static let fill = LinearGradient(
        colors: [Color.dynamic(0xF3F8FF, dark: 0x16222E), Color.dynamic(0xE2F8F5, dark: 0x12302E)],
        startPoint: .leading, endPoint: .trailing
    )
    private static let eyebrowInk = Color.dynamic(0x0D8F93, dark: 0x4FD1D1, contrastLight: 0x08686B, contrastDark: 0x7FE3E3)
    /// Figma "Tombol / Jadi Guardian" (1115:14386): #446EB4 at the top to #214889 three quarters down.
    static let button = LinearGradient(
        colors: [Color(hex: 0x446EB4), Color(hex: 0x214889)],
        startPoint: UnitPoint(x: 0.5, y: -0.05), endPoint: UnitPoint(x: 0.5, y: 0.75)
    )

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("GuardianShield")
                .resizable()
                .frame(width: 145, height: 169)
                .padding(.top, 19.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .accessibilityHidden(true)

            // Figma 1115:14373: eyebrow, title 7 under it, body 5 under the title, the button 16 under the body.
            VStack(alignment: .leading, spacing: 0) {
                Text(eyebrow)
                    .profileFont(11, .semibold, rounded: true, tracking: 0.06)
                    .figmaLineHeight(13, relativeTo: .caption2)
                    .foregroundStyle(Self.eyebrowInk)
                Text(title)
                    .profileFont(20, .semibold, tracking: -0.45)
                    .figmaLineHeight(25, relativeTo: .title3)
                    .foregroundStyle(ProfileStyle.nameInk)
                    // One line in Figma; may reach under the shield's glow rather than wrap early.
                    .frame(width: 230, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 7)
                Text(message)
                    .profileFont(16, rounded: true, tracking: -0.31)
                    .figmaLineHeight(21, relativeTo: .callout)
                    .foregroundStyle(ProfileStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 206, alignment: .leading)
                    .padding(.top, 5)
                Spacer(minLength: 13)
                Button(action: onAction) {
                    Text(action)
                        .profileFont(17, .semibold)
                        .figmaLineHeight(22, relativeTo: .body)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 38)
                        .background(Self.button, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifier + ".action")
            }
            .padding(.leading, 20)
            .padding(.top, 22)
            .padding(.bottom, 19)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ProfileStyle.secondary)
                        .frame(width: 28, height: 28)
                        .background(ProfileStyle.card.opacity(0.75), in: Circle())
                        .overlay(Circle().stroke(ProfileStyle.card))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
                .accessibilityIdentifier(identifier + ".close")
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(.top, 4)
                .padding(.trailing, 4)
            }
        }
        .frame(minHeight: 205)
        .background(Self.fill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(ProfileStyle.card.opacity(0.9)))
        .figmaCardShadow()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: Nobody protected yet (Guardian)

/// Figma "Orang yang dilindungi · Kosong": three slots, the middle one a teal plus.
struct FamilyEmptyCard: View {
    let onInvite: () -> Void

    private static let slotStroke = Color.dynamic(0xC5CFDA, dark: 0x4B5361)
    private static let slotPerson = Color.dynamic(0xCDD5DF, dark: 0x5B6470)
    private static let teal = Color.dynamic(0x0FB3B5, dark: 0x3FD3D4)
    private static let tealFill = Color.dynamic(0xE6F9F8, dark: 0x123332)
    /// Figma "Button" (1115:14537): #68CDFA at the top to #136CB7 three quarters down.
    private static let button = LinearGradient(
        colors: [Color(hex: 0x68CDFA), Color(hex: 0x136CB7)],
        startPoint: UnitPoint(x: 0.5, y: -0.05), endPoint: UnitPoint(x: 0.5, y: 0.75)
    )

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                slot
                ZStack {
                    Circle().fill(Self.tealFill)
                    Circle().strokeBorder(Self.teal, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    // Figma "Plus": 16 pt, 2 pt teal stroke.
                    Path { path in
                        path.move(to: CGPoint(x: 8, y: 1)); path.addLine(to: CGPoint(x: 8, y: 15))
                        path.move(to: CGPoint(x: 1, y: 8)); path.addLine(to: CGPoint(x: 15, y: 8))
                    }
                    .stroke(Self.teal, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 16, height: 16)
                }
                .frame(width: 60, height: 60)
                slot
            }
            // Figma "Slot Kosong" is 64 pt tall with the circles centred.
            .frame(height: 64)
            .accessibilityHidden(true)
            // Figma 1115:14533: SF Pro Display Semibold 17, then SF Pro Rounded 17 at 140 %.
            Text("No one protected yet")
                .profileFont(17, .semibold)
                .figmaLineHeight(22, relativeTo: .body)
                .foregroundStyle(ProfileStyle.nameInk)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            Text("Send an invite to your family. Once they join, their status shows up here.")
                .profileValue()
                .foregroundStyle(ProfileStyle.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)
                .padding(.top, 6)
            Button(action: onInvite) {
                Text("Invite family")
                    .profileFont(17, .semibold)
                    .figmaLineHeight(22, relativeTo: .body)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 4)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(minHeight: 46)
                    .background(Self.button, in: Capsule())
                    .overlay(Capsule().stroke(Color(hex: 0x0098D7), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .accessibilityIdentifier("profile.members.invite")
        }
        .frame(maxWidth: .infinity)
        // Figma: slot 27 pt and button 25 pt from the card's edges; ProfileCard already adds 5.
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.members.empty")
    }

    private var slot: some View {
        ZStack {
            Circle().fill(ProfileStyle.background)
            Circle().strokeBorder(Self.slotStroke, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            SlotPerson().fill(Self.slotPerson).frame(width: 20, height: 20)
        }
        .frame(width: 48, height: 48)
    }
}

/// Figma "Ikon Orang" (1115:14523), 20 pt: an 8.4 pt head over a 15.2 × 8.8 body (radius 7.6 on top, 1.6 below).
private struct SlotPerson: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 20
        var path = Path(ellipseIn: CGRect(x: 5.8 * s, y: 0.8 * s, width: 8.4 * s, height: 8.4 * s))
        path.addPath(UnevenRoundedRectangle(
            topLeadingRadius: 7.6 * s, bottomLeadingRadius: 1.6 * s, bottomTrailingRadius: 1.6 * s, topTrailingRadius: 7.6 * s
        ).path(in: CGRect(x: 2.4 * s, y: 11.2 * s, width: 15.2 * s, height: 8.8 * s)))
        return path
    }
}
