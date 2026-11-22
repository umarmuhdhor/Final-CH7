import SwiftUI

/// Figma "alief notif" section 4, "Banner · Anda Belum Terlindungi" (2439:13500), Alief's option B (22 Nov 2026): on
/// Home with Shoo off, the hero keeps its headline and loses its "Nyalakan sekarang" link; this card, with Shoo in the
/// Cemas pose, carries the button instead and stays until Shoo is on. Pribadi and Dilindungi Home.
/// Points are Figma's at 1x (the frame is drawn at 2x).
struct HomeOffBanner: View {
    /// On for some sites only (C10) is not the same as off.
    let someSitesOnly: Bool
    let turnOnIdentifier: String
    let onTurnOn: () -> Void

    enum Style {
        static let fill = Color(hex: 0xFFF7EC)
        static let stroke = Color(hex: 0xF6C98B)
        static let title = Color(hex: 0x111111)
        static let message = Color(hex: 0x4B5563)
        static let link = Color(hex: 0x0A66D9)
        static let radius: CGFloat = 22
        static let minHeight: CGFloat = 96
        /// The Cemas pose: 92 pt tall, 6 pt in from the left, 14 pt above the card's top edge.
        static let poseHeight: CGFloat = 92
        static let poseLeading: CGFloat = 6
        static let poseOverhang: CGFloat = 14
        /// The text starts 84 pt in (Figma 168 at 2x).
        static let textLeading: CGFloat = 84
    }

    var title: LocalizedStringKey { someSitesOnly ? "Not fully protected yet" : "You're not protected yet" }
    var message: LocalizedStringKey { someSitesOnly ? "Shoo is on for some sites only" : "Shoo isn't on in Safari yet." }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .onboardingFont(16, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(Style.title)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .onboardingFont(13, relativeTo: .footnote)
                    .foregroundStyle(Style.message)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            Button(action: onTurnOn) {
                Text("Turn on now")
                    .onboardingFont(14, weight: .semibold, relativeTo: .subheadline)
                    .foregroundStyle(Style.link)
                    // 44 pt to tap, the text where Figma has it (8 under the message).
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, -6)
            .padding(.bottom, -10)
            .accessibilityHint(Text("Shows how to switch Shoo on in Safari"))
            .accessibilityIdentifier(turnOnIdentifier)
        }
        .frame(maxWidth: .infinity, minHeight: Style.minHeight, alignment: .leading)
        .padding(.leading, Style.textLeading)
        .padding(.trailing, 16)
        .padding(.vertical, 16)
        .background(Style.fill, in: RoundedRectangle(cornerRadius: Style.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Style.radius, style: .continuous).strokeBorder(Style.stroke, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            MascotImage(pose: .nervous, height: Style.poseHeight)
                .offset(x: Style.poseLeading, y: -Style.poseOverhang)
                .allowsHitTesting(false)
        }
        // Room for the pose above the card.
        .padding(.top, Style.poseOverhang)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.offBanner")
    }
}

#Preview {
    VStack(spacing: 24) {
        HomeOffBanner(someSitesOnly: false, turnOnIdentifier: "a") {}
        HomeOffBanner(someSitesOnly: true, turnOnIdentifier: "b") {}
    }
    .padding(24)
    .background(Color(hex: 0xF3F6F8))
}
