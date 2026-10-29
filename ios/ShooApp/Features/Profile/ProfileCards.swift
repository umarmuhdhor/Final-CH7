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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .profileFont(15, .medium, tracking: -0.15)
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 7)
            .background(Self.gradient, in: Capsule())
            .overlay(Capsule().stroke(ProfileStyle.card, lineWidth: 3.5))
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

/// Figma "CTA Jadi Guardian": invites a Pribadi user to protect their family. X hides it for good.
struct GuardianModeCard: View {
    let onBecomeGuardian: () -> Void
    let onDismiss: () -> Void

    private static let fill = LinearGradient(
        colors: [Color.dynamic(0xF3F8FF, dark: 0x16222E), Color.dynamic(0xE2F8F5, dark: 0x12302E)],
        startPoint: .leading, endPoint: .trailing
    )
    private static let eyebrow = Color.dynamic(0x0D8F93, dark: 0x4FD1D1, contrastLight: 0x08686B, contrastDark: 0x7FE3E3)
    private static let button = LinearGradient(colors: [Color(hex: 0x191C25), Color(hex: 0x3C435A)], startPoint: .leading, endPoint: .trailing)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("GuardianShield")
                .resizable()
                .frame(width: 145, height: 169)
                .padding(.top, 19.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("GUARDIAN MODE")
                    .profileFont(11, .semibold, tracking: 0.66)
                    .foregroundStyle(Self.eyebrow)
                Text("Protect the people closest to you")
                    .profileFont(20, .semibold, tracking: -0.2)
                    .foregroundStyle(ProfileStyle.nameInk)
                    // One line in Figma; may reach under the shield's glow rather than wrap early.
                    .frame(width: 230, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 7)
                Text("Help check suspicious sites your family opens.")
                    .profileFont(14)
                    .foregroundStyle(ProfileStyle.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 206, alignment: .leading)
                    .padding(.top, 6)
                Spacer(minLength: 18)
                Button(action: onBecomeGuardian) {
                    Text("Become a Guardian")
                        .profileFont(15, .semibold, tracking: -0.15)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 38)
                        .background(Self.button, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.guardianCard.become")
            }
            .padding(.leading, 20)
            .padding(.top, 22)
            .padding(.bottom, 17)

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
            .accessibilityIdentifier("profile.guardianCard.close")
            .frame(maxWidth: .infinity, alignment: .topTrailing)
            .padding(.top, 4)
            .padding(.trailing, 4)
        }
        .frame(minHeight: 188)
        .background(Self.fill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(ProfileStyle.card.opacity(0.9)))
        .padding(.horizontal, ProfileStyle.margin)
        .padding(.top, 32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.guardianCard")
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
                    Circle().strokeBorder(Self.teal, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Self.teal)
                }
                .frame(width: 60, height: 60)
                slot
            }
            .accessibilityHidden(true)
            .padding(.top, 1)
            Text("No one protected yet")
                .profileFont(18, .semibold, tracking: -0.18)
                .foregroundStyle(ProfileStyle.nameInk)
                .multilineTextAlignment(.center)
                .padding(.top, 15)
            Text("Send an invite to your family. Once they join, their status shows up here.")
                .profileFont(14)
                .foregroundStyle(ProfileStyle.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)
                .padding(.top, 6)
            Button(action: onInvite) {
                Text("Invite family")
                    .profileFont(15, .semibold, tracking: -0.19)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
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
        .padding(.horizontal, 24)
        .padding(.top, 21)
        .padding(.bottom, 19)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.members.empty")
    }

    private var slot: some View {
        ZStack {
            Circle().fill(ProfileStyle.background)
            Circle().strokeBorder(Self.slotStroke, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            Image(systemName: "person.fill")
                .font(.system(size: 17))
                .foregroundStyle(Self.slotPerson)
        }
        .frame(width: 48, height: 48)
    }
}
