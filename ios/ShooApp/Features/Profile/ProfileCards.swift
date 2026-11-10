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
        startPoint: .leading, endPoint: .trailing
    )

    /// Figma 131 × 35: 5 / 15 inside a 3.5 pt white ring that counts in the layout.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .profileFont(15, .medium, tracking: -0.15)
            .foregroundStyle(.white)
            .padding(.horizontal, 18.5)
            .padding(.vertical, 8.5)
            .background(Self.gradient, in: Capsule())
            .overlay(Capsule().strokeBorder(ProfileStyle.card, lineWidth: 3.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    /// Figma's glyph is a phone beside a stack; `iphone.motion` is the closest SF Symbol on iOS 17.
    static var symbol: String {
        UIImage(systemName: "iphone.motion") != nil ? "iphone.motion" : "iphone"
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
    /// Figma style "Gradient/Dark Button".
    private static let button = LinearGradient(colors: [Color(hex: 0x214889), Color(hex: 0x446EB4)], startPoint: .leading, endPoint: .trailing)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("GuardianShield")
                .resizable()
                .frame(width: 145, height: 169)
                .padding(.top, 19.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(eyebrow)
                    .profileFont(11, .semibold, tracking: 0.66)
                    .foregroundStyle(Self.eyebrowInk)
                Text(title)
                    .profileFont(20, .semibold, tracking: -0.2)
                    .foregroundStyle(ProfileStyle.nameInk)
                    // One line in Figma; may reach under the shield's glow rather than wrap early.
                    .frame(width: 230, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 7)
                Text(message)
                    .profileFont(16)
                    .foregroundStyle(ProfileStyle.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 206, alignment: .leading)
                    .padding(.top, 5)
                Spacer(minLength: 10)
                Button(action: onAction) {
                    Text(action)
                        .profileFont(17, .semibold)
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
    private static let button = LinearGradient(colors: [Color(hex: 0x136CB7), Color(hex: 0x68CDFA)], startPoint: .leading, endPoint: .trailing)

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
            Text("No one protected yet")
                .profileFont(18, .semibold, tracking: -0.18)
                .foregroundStyle(ProfileStyle.nameInk)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            Text("Send an invite to your family. Once they join, their status shows up here.")
                .profileFont(14)
                .foregroundStyle(ProfileStyle.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                // Figma's 140 % line height also pads above the first and below the last line.
                .padding(.vertical, 1.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)
                .padding(.top, 6)
            Button(action: onInvite) {
                Text("Invite family")
                    .profileFont(15, .semibold, tracking: -0.19)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 4)
                    .padding(.horizontal, 20)
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
            Image(systemName: "person.fill")
                .font(.system(size: 17))
                .foregroundStyle(Self.slotPerson)
        }
        .frame(width: 48, height: 48)
    }
}
