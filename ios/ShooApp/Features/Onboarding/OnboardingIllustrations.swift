import SwiftUI

/// Figma "Ilustrasi / Keluarga" (871:19612), built in SwiftUI so its text follows the app language.
/// Sample content, nothing here is the user's family. Coordinates are Figma's on the 402 pt frame.
struct FamilyCardIllustration: View {
    /// Figma's status bar and home area are not part of the page: the hero starts under the safe area.
    private static let safeAreaTop: CGFloat = 62

    var body: some View {
        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(Color(hex: 0x51DEDC, opacity: 0.5))
                .frame(width: 170, height: 150)
                .blur(radius: 30)
                .position(x: 155, y: 325)
            Ellipse()
                .fill(Color(hex: 0x2E90FA, opacity: 0.55))
                .frame(width: 190, height: 190)
                .blur(radius: 40)
                .position(x: 331, y: 185)
            // Figma "Ketebalan kaca": the edge of the glass under the card.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0xE6FCF9, opacity: 0.85), location: 0.96),
                        .init(color: Color(hex: 0xA6EEEE, opacity: 0.9), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: 266.4, height: 249.2)
                .rotationEffect(.degrees(-4))
                .position(x: 196.1, y: 269.6)
            card
                .rotationEffect(.degrees(-4))
                .position(x: 194.6, y: 263.6)
            // Figma export of "Perisai 3D", its shadow baked in.
            Image("FamilyShield")
                .position(x: 287, y: 376)
        }
        .frame(width: 402, height: 460, alignment: .topLeading)
        .frame(width: 402, height: 460 - Self.safeAreaTop + 14, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7.2) {
                Text("Family")
                    .font(FigmaFont.font(size: 15.3, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x191D2F))
                Text("2 of 3")
                    .font(.system(size: 10.8, design: .rounded))
                    .foregroundStyle(OnboardingTheme.bodyInk)
                    .padding(.horizontal, 8.1)
                    .padding(.vertical, 2.7)
                    .background(.white.opacity(0.55), in: Capsule())
                    .overlay { Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 0.9) }
            }
            .padding(.horizontal, 1.8)
            .padding(.bottom, 1.8)

            FamilyRow(avatarId: "avatar_01", name: "Mom", status: "Site blocked · 92%", statusColor: Color(hex: 0xE5483B), statusWeight: .semibold) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x9AA1AE))
            }
            FamilyRow(avatarId: "avatar_02", name: "Dad", status: "Nothing suspicious", statusColor: OnboardingTheme.bodyInk, statusWeight: .regular) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 19.8, height: 19.8)
                    .background(Color(hex: 0x34C759), in: Circle())
            }

            HStack(spacing: 10.8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0x186FB9))
                    .frame(width: 28.8, height: 28.8)
                    .background(.white.opacity(0.85), in: Circle())
                    .shadow(color: Color(hex: 0x186FB9, opacity: 0.18), radius: 3.6, y: 2.7)
                Text("Invite your family")
                    .font(.system(size: 14.4, weight: .semibold, design: .rounded))
                    .tracking(-0.28)
                    .foregroundStyle(Color(hex: 0x186FB9))
                Spacer(minLength: 0)
            }
            .padding(.leading, 9)
            .padding(.trailing, 12.6)
            .padding(.vertical, 10.8)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.95), style: StrokeStyle(lineWidth: 1.35, dash: [4, 3]))
            }
        }
        .padding(.top, 14.4)
        .padding([.horizontal, .bottom], 12.6)
        .frame(width: 266.4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.35
                )
        }
    }
}

/// One member in the Figma card: 36 pt avatar, name, status, and an end mark.
private struct FamilyRow<Mark: View>: View {
    let avatarId: String
    let name: LocalizedStringKey
    let status: LocalizedStringKey
    let statusColor: Color
    let statusWeight: Font.Weight
    @ViewBuilder let mark: Mark

    var body: some View {
        HStack(spacing: 10.8) {
            AvatarView(id: avatarId, size: 36)
            VStack(alignment: .leading, spacing: 0.9) {
                Text(name)
                    .font(FigmaFont.font(size: 15.3, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x191D2F))
                Text(status)
                    .font(.system(size: 11.7, weight: statusWeight, design: .rounded))
                    .tracking(-0.07)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            mark
        }
        .padding(.leading, 9)
        .padding(.trailing, 12.6)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white, .white.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.9
                )
        }
        .shadow(color: Color(hex: 0x0B4C8C, opacity: 0.1), radius: 7.2, y: 5.4)
    }
}

/// Figma "Ilustrasi / Orbit" (929:8614) in motion: the two avatars circle the shield and pass in front of
/// and behind it, each with its chip at the ends of the orbit. With Reduce Motion it is the still frame.
struct ConnectedOrbitIllustration: View {
    let guardian: GuardianInfo
    /// nil until `GET /devices/me` answered: the generic avatar shows.
    let ownAvatarId: String?

    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var start = Date()

    private static let size = CGSize(width: 340.7, height: 339)
    /// Figma "Orbit": centre, half axes, and its tilt (rotation read from the node's bounding box).
    private static let center = CGPoint(x: 170.35, y: 186.45)
    private static let radii = CGSize(width: 127.1, height: 49.2)
    private static let tilt = -14 * Double.pi / 180
    private static let shieldCenter = CGPoint(x: 170, y: 176)
    private static let period = 18.0

    /// Where each avatar starts, so the first frame is Figma's. The guardian rides slightly further out.
    private struct Rider: Identifiable {
        let id: Int
        let startAngle: Double
        let reach: Double
        let chipOffset: CGSize
    }

    private static let you = Rider(id: 0, startAngle: .pi, reach: 1, chipOffset: CGSize(width: 20, height: 56))
    private static let them = Rider(id: 1, startAngle: 32.6 * .pi / 180, reach: 1.13, chipOffset: CGSize(width: -3, height: -60))

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let turn = reduceMotion ? 0 : context.date.timeIntervalSince(start) / Self.period * 2 * .pi
            ZStack {
                glow
                rings
                riders(turn: turn, front: false)
                shield
                riders(turn: turn, front: true)
            }
            .frame(width: Self.size.width, height: Self.size.height)
        }
        .onAppear { start = Date() }
        .accessibilityHidden(true)
    }

    private var glow: some View {
        ZStack {
            Ellipse()
                .fill(Color(hex: 0x51DEDC, opacity: 0.34))
                .frame(width: 178, height: 144)
                .blur(radius: 24)
                .position(x: 53, y: 241)
            Ellipse()
                .fill(Color(hex: 0x94DBFE, opacity: 0.33))
                .frame(width: 178, height: 161)
                .blur(radius: 24)
                .position(x: 287, y: 152)
        }
    }

    private var rings: some View {
        ZStack {
            Ellipse()
                .strokeBorder(.white.opacity(0.22), lineWidth: 1.27)
                .frame(width: 293.2, height: 127.1)
                .opacity(0.47)
            Ellipse()
                .strokeBorder(
                    LinearGradient(colors: [Color(hex: 0x8FE9EC), .white.opacity(0.95)], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 2.12
                )
                .frame(width: 254.25, height: 98.3)
                .opacity(0.19)
        }
        .rotationEffect(.radians(Self.tilt))
        .position(Self.center)
    }

    private var shield: some View {
        ZStack {
            // Figma export of "Perisai 3D": its baked shadow reaches lower, so the picture centre is 13.6 down.
            Image("OrbitShield")
                .position(x: Self.shieldCenter.x, y: Self.shieldCenter.y + 13.6)
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 27, height: 27)
                .background(Color(hex: 0x34C759), in: Circle())
                .overlay { Circle().strokeBorder(.white, lineWidth: 2.5) }
                .shadow(color: Color(hex: 0x1B7F3A, opacity: 0.4), radius: 6.8, y: 5)
                .position(x: 203.6, y: 201.6)
        }
    }

    @ViewBuilder
    private func riders(turn: Double, front: Bool) -> some View {
        ForEach([Self.you, Self.them]) { rider in
            let angle = rider.startAngle + turn
            // The ends of the orbit count as behind, so the first frame keeps Figma's order.
            if (sin(angle) > 0.001) == front {
                let spot = position(of: rider, angle: angle)
                avatar(for: rider)
                    .scaleEffect(1 + 0.1 * (sin(angle) - sin(rider.startAngle)))
                    .position(spot)
                chip(for: rider)
                    // Only near the ends of the orbit, where nothing covers it.
                    .opacity(min(max((abs(cos(angle)) - 0.55) / 0.25, 0), 1))
                    .position(x: spot.x + rider.chipOffset.width, y: spot.y + rider.chipOffset.height)
            }
        }
    }

    private func position(of rider: Rider, angle: Double) -> CGPoint {
        let x = Self.radii.width * rider.reach * cos(angle)
        let y = Self.radii.height * rider.reach * sin(angle)
        return CGPoint(
            x: Self.center.x + x * cos(Self.tilt) - y * sin(Self.tilt),
            y: Self.center.y + x * sin(Self.tilt) + y * cos(Self.tilt)
        )
    }

    private func avatar(for rider: Rider) -> some View {
        AvatarView(id: rider.id == Self.you.id ? ownAvatarId ?? "" : guardian.avatarId, size: 66)
            .overlay { Circle().strokeBorder(.white, lineWidth: 2.5) }
            .shadow(color: Color(hex: 0x062F5C, opacity: 0.28), radius: 9.3, y: 8.5)
    }

    @ViewBuilder
    private func chip(for rider: Rider) -> some View {
        HStack(spacing: 4.2) {
            if rider.id == Self.you.id {
                Text("You").fontWeight(.semibold).foregroundStyle(Color(hex: 0x191D2F))
                Text("· Protected").foregroundStyle(OnboardingTheme.bodyInk)
            } else {
                Text(verbatim: guardian.name)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(hex: 0x191D2F))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 76)
                    .fixedSize(horizontal: true, vertical: false)
                Text(verbatim: "· Guardian").fontWeight(.semibold).foregroundStyle(Color(hex: 0x186FB9))
            }
        }
        .font(.system(size: 11, design: .rounded))
        .tracking(-0.07)
        .padding(.leading, 9.3)
        .padding(.trailing, 11)
        .padding(.vertical, 5.9)
        .background(.white.opacity(0.78), in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.95), lineWidth: 0.85) }
        .shadow(color: Color(hex: 0x062F5C, opacity: 0.16), radius: 6.8, y: 5)
        .fixedSize()
    }
}
