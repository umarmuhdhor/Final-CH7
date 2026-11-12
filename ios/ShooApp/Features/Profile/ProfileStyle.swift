import SwiftUI
import UIKit

/// Figma "Profile/Pribadi", "Profile/Guardian", "Guardian/Detail Orang Dilindungi" (PF-01): colours,
/// type and the building blocks every Profile screen shares. Values are the Figma ones.
enum ProfileStyle {
    // Light values are Figma's; dark and Increase Contrast values are ours (Figma has light only).
    static let background = Color.dynamic(0xF5F8FC, dark: 0x0E1116)
    static let topWash = Color.dynamic(0xDCECFB, dark: 0x132639)
    /// Cards, the back button, pills.
    static let card = Color.dynamic(0xFFFFFF, dark: 0x1B1F26)
    /// Figma "Profil Card", "Back" and member "Avatar" drop shadow (#1A1C2E 12%, y 6, blur 16).
    static let cardShadow = Color(hex: 0x1A1C2E, opacity: 0.12)
    /// Figma "Profile" avatar on the own profile card (#1F78BF 18%, y 7.68, blur 23).
    static let avatarGlow = Color(hex: 0x1F78BF, opacity: 0.18)
    static let ink = Color.dynamic(0x191D2F, dark: 0xF2F4F8, contrastLight: 0x000000, contrastDark: 0xFFFFFF)
    static let nameInk = Color.dynamic(0x151617, dark: 0xF7F8FA, contrastLight: 0x000000, contrastDark: 0xFFFFFF)
    static let secondary = Color.dynamic(0x6A717E, dark: 0x9EA6B4, contrastLight: 0x474D58, contrastDark: 0xC9CED8)
    static let chevron = Color.dynamic(0xC7C7CE, dark: 0x5B616C, contrastLight: 0x80858F, contrastDark: 0x9EA6B4)
    static let iconFill = Color.dynamic(0xF1F4F8, dark: 0x2A303A, contrastLight: 0xE2E7EE, contrastDark: 0x3A414D)
    static let divider = Color.dynamic(0xEEF1F5, dark: 0x2A303A, contrastLight: 0xC6CDD7, contrastDark: 0x4B5361)
    static let statsDivider = Color.dynamic(0xE3E8EF, dark: 0x343B46, contrastLight: 0xB8C0CC, contrastDark: 0x56606E)
    static let pillStroke = Color.dynamic(0xDCDFE4, dark: 0x3A414D, contrastLight: 0x9AA1AC, contrastDark: 0x6B7380)
    static let link = Color.dynamic(0x186FB9, dark: 0x5EAAF0, contrastLight: 0x0E5592, contrastDark: 0x8CC4F6)
    static let red = Color.dynamic(0xE5483B, dark: 0xFF6B5E, contrastLight: 0xB3261E, contrastDark: 0xFF8F85)
    static let redIconFill = Color.dynamic(0xFDECEA, dark: 0x3A1F1D)
    static let green = Color.dynamic(0x34C759, dark: 0x30D158)
    static let greenText = Color.dynamic(0x1B7F3A, dark: 0x4CD97B, contrastLight: 0x0F5F27, contrastDark: 0x7BE8A0)
    static let greenPill = Color.dynamic(0xE8F8EE, dark: 0x153322)
    static let offDot = Color(hex: 0x8E8E93)
    static let grabber = Color.dynamic(0xD6DAE1, dark: 0x4A515C)
    /// The radio's ring (Figma "Radio" #C7C7CE) and the Mode akun card's selected border.
    static let radioOff = Color.dynamic(0xC7C7CE, dark: 0x5B616C, contrastLight: 0x80858F, contrastDark: 0x9EA6B4)
    /// Disabled button fill (Kelola profil "Simpan nama").
    /// Aksesibilitas text-size slider rail (Figma "Rail").
    static let sliderRail = Color.dynamic(0xE6E8EC, dark: 0x343B46, contrastLight: 0xC6CDD7, contrastDark: 0x4B5361)
    static let disabledFill = Color.dynamic(0xB8C0CC, dark: 0x3A414D)
    /// Primary dark capsule ("Ganti ke Guardian"): ink on light, a light capsule on dark.
    static let primaryFill = Color.dynamic(0x191D2F, dark: 0xF2F4F8)
    static let primaryText = Color.dynamic(0xFFFFFF, dark: 0x0E1116)

    /// Screen side margin for section titles and cards; the profile card sits closer (16).
    static let margin: CGFloat = 24

    /// Initials avatars on member rows and the member detail (Figma gradients, picked by avatar id).
    static let initialsGradients: [[Color]] = [
        [Color(hex: 0x7DE49C), Color(hex: 0x54CAE8)],
        [Color(hex: 0xFFBE8C), Color(hex: 0xFF7896)],
        [Color(hex: 0xAFA5FF), Color(hex: 0x6E8CFA)],
    ]

    static func initialsGradient(avatarId: String) -> LinearGradient {
        let number = Int(avatarId.filter(\.isNumber)) ?? 0
        let colors = initialsGradients[(max(number, 1) - 1) % initialsGradients.count]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// `arrow.left.arrow.right` stands in for Figma's "icon/switch".
    static let switchSymbol = "arrow.left.arrow.right"

    /// Figma's Safari extension glyph (`macwindow.stack`) is iOS 26+; older systems get `macwindow`.
    static var extensionSymbol: String {
        UIImage(systemName: "macwindow.stack") != nil ? "macwindow.stack" : "macwindow"
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: Type

/// Figma sizes that still follow Dynamic Type (shared `FigmaFont`: the SF Pro Display widths Figma uses).
extension View {
    func profileFont(
        _ size: CGFloat, _ weight: Font.Weight = .regular, rounded: Bool = false, tracking: CGFloat = 0
    ) -> some View {
        let style: Font.TextStyle = switch size {
        case ..<14: .footnote
        case ..<16: .subheadline
        case ..<19: .body
        case ..<21: .title3
        case ..<23: .title2
        default: .title
        }
        return figmaFont(size, weight: weight, design: rounded ? .rounded : .default, tracking: tracking, relativeTo: style)
    }

    /// Figma (1115:14392) row titles, section titles, "Hapus Akun": SF Pro Rounded 17, -1 %, 22 pt line.
    func profileBody(_ weight: Font.Weight = .regular) -> some View {
        profileFont(17, weight, rounded: true, tracking: -0.17)
            .figmaLineHeight(22, relativeTo: .body)
    }

    /// Row values ("Pribadi", "Indonesia"), the handle, "Ingatkan": SF Pro Rounded 17 at 140 %.
    func profileValue() -> some View {
        profileFont(17, rounded: true)
            .figmaLineHeight(23.8, relativeTo: .body)
    }

    /// Subtitles, captions and the stats labels: SF Pro Rounded 13, -0.08, 18 pt line.
    func profileCaption() -> some View {
        profileFont(13, rounded: true, tracking: -0.08)
            .figmaLineHeight(18, relativeTo: .footnote)
    }
}

// MARK: Screen

/// The grey page with the blue top wash and the round back button + centred title (Figma "Back", "Judul").
/// The navigation bar is hidden; the swipe back still works (`SwipeBackEnabler`).
struct ProfileScreen<Content: View>: View {
    let title: String.LocalizationValue
    /// Figma "Judul": 20 pt on Profile and Pengaturan, 17 on the member detail.
    var titleSize: CGFloat = 20
    @ViewBuilder var content: Content
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale

    /// Figma puts the back button 48 pt from the top of the frame, inside the 62 pt status bar area of
    /// a Dynamic Island iPhone. Other iPhones keep it 4 pt under the status bar.
    private static func headerTop(safeTop: CGFloat) -> CGFloat {
        safeTop >= 54 ? 48 : safeTop + 4
    }

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let headerTop = Self.headerTop(safeTop: safeTop)
            ScrollView {
                VStack(spacing: 0) {
                    header
                    content
                }
                .padding(.top, headerTop)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .top)
            // Content scrolling under the status bar stays readable; the band stops above the back button.
            .overlay(alignment: .top) {
                ProfileStyle.topWash.opacity(0.96)
                    .frame(height: min(safeTop, headerTop))
                    // The overlay is laid out under the status bar; move it up to the screen's top edge.
                    .offset(y: -safeTop)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        // The reader itself stays inside the safe area, so `safeAreaInsets.top` reports the status bar.
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                ProfileStyle.background
                LinearGradient(colors: [ProfileStyle.topWash, ProfileStyle.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 340)
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .background(SwipeBackEnabler())
        .accessibilityAction(.escape) { env.router.pop() }
    }

    private var header: some View {
        ZStack {
            Text(verbatim: L10n.string(title, language: AppLanguage(locale: locale)))
                // Figma: SF Pro Display Semibold 20, -0.45, 25 pt line (17 / 0 / 22 on the member detail).
                .profileFont(titleSize, .semibold, tracking: titleSize >= 20 ? -0.45 : 0)
                .figmaLineHeight(titleSize >= 20 ? 25 : 22, relativeTo: titleSize >= 20 ? .title3 : .body)
                .foregroundStyle(ProfileStyle.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 60)
            HStack {
                Button { env.router.pop() } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ProfileStyle.ink)
                        .frame(width: 44, height: 44)
                        .background(ProfileStyle.card, in: Circle())
                        .shadow(color: ProfileStyle.cardShadow, radius: 8, y: 6)
                }
                .accessibilityLabel(Text("Back"))
                .accessibilityIdentifier("profile.back")
                Spacer()
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, ProfileStyle.margin)
        .padding(.bottom, 16)
    }
}

/// Keeps the edge swipe back with the navigation bar hidden.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = self
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

// MARK: Sections and cards

/// "Perlindungan", "Akun", "Preferensi": grey title above a card.
struct ProfileSection<Content: View>: View {
    let title: LocalizedStringKey
    var trailing: AnyView?
    /// Space above the title: 28 on most screens, 15 between the Protected profile's sections (Figma).
    var top: CGFloat = 28
    /// Title to card: 10 under the 22 pt title line (Figma 1115:14392), 24 above the Protected
    /// profile's "Terhubung" card (Figma 455:10275).
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .profileBody()
                    .foregroundStyle(ProfileStyle.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                trailing
            }
            ProfileCard { content }
        }
        .padding(.horizontal, ProfileStyle.margin)
        .padding(.top, top)
    }
}

/// White rounded card (r 24) with 5 pt above and below its rows.
struct ProfileCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(ProfileStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(ProfileStyle.card.opacity(0.9)))
            .figmaCardShadow()
    }
}

/// 1 pt line between rows, from the text column (Figma x 89 in a 354 card) to 17 pt from the right.
struct ProfileDivider: View {
    var leading: CGFloat = 65

    var body: some View {
        ProfileStyle.divider
            .frame(height: 1)
            .padding(.leading, leading)
            .padding(.trailing, 17)
            .accessibilityHidden(true)
    }
}

/// The 36 pt grey circle with a 16 pt symbol.
struct ProfileIcon: View {
    let symbol: String
    var tint: Color = ProfileStyle.ink
    var fill: Color = ProfileStyle.iconFill
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 36

    var body: some View {
        Group {
            if symbol == "Aa" {
                Text(verbatim: "Aa").profileFont(15, .semibold, rounded: true, tracking: -0.23)
            } else {
                Image(systemName: symbol).font(.system(size: 16 * size / 36, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(tint)
        .frame(width: size, height: size)
        .background(fill, in: Circle())
        .accessibilityHidden(true)
    }
}

/// What sits at the right of a row.
enum ProfileRowAccessory {
    case none
    case chevron
    case value(String, color: Color = ProfileStyle.secondary, chevron: Bool = true)
    /// Figma "Status" on Ekstensi Safari: an 8 pt dot and the word, no chevron ("● Terhubung").
    case status(String, dot: Color, color: Color)
}

/// One 58 pt row: icon, title (+ optional grey subtitle), value / chevron. No icon when `symbol` is nil.
struct ProfileRow: View {
    let symbol: String?
    let title: Text
    var subtitle: Text?
    var accessory: ProfileRowAccessory = .chevron
    var titleColor: Color = ProfileStyle.ink
    var titleWeight: Font.Weight = .regular
    var iconTint: Color = ProfileStyle.ink
    var iconFill: Color = ProfileStyle.iconFill
    /// 58 for icon rows; 44 for the plain text rows of "Tentang Shoo" (Figma 455:9858).
    var minHeight: CGFloat = 58
    /// `.settings`: the Pengaturan pages' look (12 pt padding, SF Pro 13 pt subtitle at 135 %).
    var style: ProfileToggleRow.Style = .profile

    var body: some View {
        HStack(spacing: 12) {
            if let symbol { ProfileIcon(symbol: symbol, tint: iconTint, fill: iconFill) }
            // Figma: title and subtitle 2 pt apart, both SF Pro Rounded.
            VStack(alignment: .leading, spacing: 2) {
                title
                    .profileBody(titleWeight)
                    .foregroundStyle(titleColor)
                if let subtitle {
                    subtitle
                        .profileCaption()
                        .foregroundStyle(ProfileStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessoryView
        }
        .padding(.horizontal, 17)
        .padding(.vertical, minHeight < 58 || style == .settings ? 12 : 11)
        .frame(minHeight: minHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var accessoryView: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .chevron:
            chevron
        case .value(let text, let color, let showsChevron):
            HStack(spacing: 12) {
                Text(verbatim: text)
                    .profileValue()
                    .foregroundStyle(color)
                    .multilineTextAlignment(.trailing)
                if showsChevron { chevron }
            }
        case .status(let text, let dot, let color):
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(verbatim: text)
                    .profileBody()
                    .foregroundStyle(color)
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(ProfileStyle.chevron)
            .accessibilityHidden(true)
    }
}

/// A row with a switch (Figma "Toggle", green #34C759). No icon when `symbol` is nil.
struct ProfileToggleRow: View {
    /// Figma draws two kinds: the Profile cards' rows (58 pt, rounded 13 pt subtitle on a 20 pt line,
    /// e.g. "Kabari saya") and the Pengaturan pages' rows (60 pt, SF Pro 13 pt subtitle at 135 %).
    enum Style {
        case profile
        case settings
    }

    let symbol: String?
    let title: Text
    var subtitle: Text?
    var style: Style = .profile
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                if let symbol { ProfileIcon(symbol: symbol) }
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .profileBody()
                        .foregroundStyle(ProfileStyle.ink)
                    if let subtitle {
                        subtitle
                            .profileCaption()
                            .foregroundStyle(ProfileStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(ProfileStyle.green)
        .padding(.horizontal, 17)
        .padding(.vertical, style == .settings ? 12 : 11)
        // Figma: 60 with an icon, 55 without ("Jam tenang").
        .frame(minHeight: style == .settings ? (symbol == nil ? 55 : 60) : 58)
    }
}

// MARK: Profile card

/// One number of the stats strip.
struct ProfileStat: Identifiable {
    let value: String
    let label: LocalizedStringKey
    var id: String { "\(label)" }
}

/// The grey strip of 2–3 numbers at the bottom of the profile card (Figma "Statistik").
struct ProfileStatsStrip: View {
    let stats: [ProfileStat]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    ProfileStyle.statsDivider.frame(width: 1, height: 32).accessibilityHidden(true)
                }
                VStack(spacing: 2) {
                    Text(verbatim: stat.value)
                        .profileFont(20, .semibold, tracking: -0.45)
                        .figmaLineHeight(25, relativeTo: .title3)
                        .foregroundStyle(ProfileStyle.nameInk)
                    Text(stat.label)
                        .profileCaption()
                        .foregroundStyle(ProfileStyle.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
            }
        }
        .background(ProfileStyle.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// The white card with banner, avatar, name, handle and stats (Figma "Profil Card", r 32, 12 pt inset).
struct ProfileHeaderCard<Avatar: View, Badge: View>: View {
    /// The avatar's drop shadow. Figma: none on the Guardian / Pribadi memoji and on the member
    /// detail; a blue glow on the Protected profile ("Profile", #1F78BF 18 %, y 7.68, blur 23).
    enum AvatarShadow {
        case none
        case glow
    }

    let banner: String
    var bannerHeight: CGFloat = 128
    var avatarShadow: AvatarShadow = .none
    /// The badge's bottom edge against the avatar's: 5 pt below for "Bagikan undangan", 26 pt above for
    /// the Protected "Terhubung" pill, 1 pt above for a member's "Perlindungan aktif" (Figma).
    var badgeBottom: CGFloat = 5
    let name: String
    let handle: String
    let stats: [ProfileStat]
    /// Figma "Pesan ekstensi mati" (1681:6718): a strip across the card's foot.
    var attachment: AnyView?
    @ViewBuilder var avatar: Avatar
    @ViewBuilder var badge: Badge

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(banner)
                .resizable()
                .scaledToFill()
                .frame(height: bannerHeight)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityHidden(true)
            HStack(alignment: .bottom) {
                avatar
                    .frame(width: 88, height: 88)
                    .padding(4)
                    .background(ProfileStyle.card, in: Circle())
                    .shadow(color: avatarShadow == .glow ? ProfileStyle.avatarGlow : .clear, radius: 11.5, y: 7.7)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                badge
                    .padding(.bottom, -badgeBottom)
            }
            .padding(.horizontal, 12)
            .padding(.top, -52)
            // Figma (1115:14392): SF Pro Display Bold 22 on a 28 pt line, the handle 4 pt under it.
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: name)
                    .profileFont(22, .bold, tracking: -0.26)
                    .figmaLineHeight(28, relativeTo: .title2)
                    .foregroundStyle(ProfileStyle.nameInk)
                    .accessibilityAddTraits(.isHeader)
                if !handle.isEmpty {
                    Text(verbatim: handle)
                        .profileValue()
                        .foregroundStyle(ProfileStyle.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            if !stats.isEmpty {
                // Figma: 10 under the handle; 12 under the name when there is no handle (Protected).
                ProfileStatsStrip(stats: stats)
                    .padding(.top, handle.isEmpty ? 12 : 10)
            }
            if let attachment {
                // Edge to edge at the card's foot, under the stats (Figma: 12 under them).
                attachment
                    .padding(.horizontal, -12)
                    .padding(.top, 12)
                    .padding(.bottom, -(stats.isEmpty ? 10 : 9))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        // Figma: 9 under the stats, 10 under the handle when the stats are hidden.
        .padding(.bottom, stats.isEmpty ? 10 : 9)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(ProfileStyle.card)
                .shadow(color: ProfileStyle.cardShadow, radius: 8, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(ProfileStyle.card.opacity(0.9)))
        .padding(.horizontal, 16)
    }
}

/// White capsule with a grey border ("Bagikan undangan", "Ingatkan").
struct ProfilePillButtonStyle: ButtonStyle {
    var tint: Color = ProfileStyle.ink
    /// Figma "Ingatkan": 6 / 12 inside its 1 pt border (78 × 31). "Bagikan Undangan": 9 top and bottom,
    /// 12 leading, 16 trailing inside the border (165 × 37). Figma counts the border in the layout.
    var padding = EdgeInsets(top: 7, leading: 13, bottom: 7, trailing: 13)

    static let invitePadding = EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 17)

    /// Figma 1115:14655 "Ingatkan": SF Pro Rounded 17 at 140 % (88 × 38). `false`: the older 14 pt pills.
    var large = false

    @Environment(\.shooReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        label(configuration)
            .foregroundStyle(tint)
            .padding(padding)
            .background(ProfileStyle.card, in: Capsule())
            .overlay(Capsule().strokeBorder(ProfileStyle.pillStroke))
            .opacity(configuration.isPressed ? 0.6 : 1)
            // Gives under the finger like the onboarding pill; Reduce Motion: the dim alone.
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    @ViewBuilder private func label(_ configuration: Configuration) -> some View {
        if large {
            configuration.label.profileValue()
        } else {
            configuration.label.profileFont(14, .medium, tracking: -0.14)
        }
    }
}

/// Figma "QR Icon": three corner squares and four dots, 16 pt.
struct QRGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 16
            for origin in [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 10)] {
                let rect = CGRect(x: origin.x * s + 0.8, y: origin.y * s + 0.8, width: 6 * s - 1.6, height: 6 * s - 1.6)
                context.stroke(Path(roundedRect: rect, cornerRadius: 1.5 * s), with: .color(ProfileStyle.ink), lineWidth: 1.6)
            }
            for (x, y) in [(10.0, 10.0), (13.5, 13.5), (13.5, 10.0), (10.0, 13.5)] {
                let rect = CGRect(x: x * s, y: y * s, width: 2.5 * s, height: 2.5 * s)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.6 * s), with: .color(ProfileStyle.ink))
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

/// A member's initial on its gradient (Figma "Inisial").
struct InitialsAvatar: View {
    let name: String
    let avatarId: String
    var size: CGFloat = 44

    /// Figma: SF Pro Rounded Semibold 17 on the 44 pt member rows (1115:14626), 41 % of larger avatars.
    private var fontSize: CGFloat { size == 44 ? 17 : size * 0.41 }

    var body: some View {
        Text(verbatim: String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(FigmaFont.font(size: fontSize, weight: .semibold, design: .rounded))
            .tracking(size == 44 ? -0.43 : 0)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(ProfileStyle.initialsGradient(avatarId: avatarId), in: Circle())
            .accessibilityHidden(true)
    }
}

/// "Diblokir" / "Waspada" chip on activity rows (Figma "Button" instance).
struct ProfileScanChip: View {
    let status: ScanStatus

    private static let blockedInk = Color.dynamic(0xBB1616, dark: 0xFF7A7A)
    private static let cautionInk = Color.dynamic(0x9A5A00, dark: 0xF5B04A)
    private static let blockedFill = Color.dynamic(0xFFF4F4, dark: 0x3A1D1D)
    private static let cautionFill = Color.dynamic(0xFFF8EF, dark: 0x382A14)
    private static let blockedStroke = Color.dynamic(0xFFCDCD, dark: 0x5C2A2A)
    private static let cautionStroke = Color.dynamic(0xFFE1B6, dark: 0x5A4220)

    var body: some View {
        let blocked = status == .blocked
        HStack(spacing: 4) {
            // Figma: an 11 pt frame holding an 8.9 pt filled "!" circle.
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(blocked ? Self.blockedInk : Color(hex: 0xD67D00))
                .frame(width: 11, height: 11)
                .accessibilityHidden(true)
            Text(blocked ? "Blocked" : "Caution")
                .profileFont(13, tracking: -0.16)
                // Figma's #D67D00 is about 3:1 on its tint; this darker orange keeps the text readable (4.5:1).
                .foregroundStyle(blocked ? Self.blockedInk : Self.cautionInk)
        }
        // Figma: 6 / 8 around an 11 pt line (23 pt tall); SwiftUI's 13 pt line is ~16 pt.
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(blocked ? Self.blockedFill : Self.cautionFill, in: Capsule())
        .overlay(Capsule().strokeBorder(blocked ? Self.blockedStroke : Self.cautionStroke, lineWidth: 0.75))
    }
}

// MARK: Confirm sheet

/// Figma "Sheet": avatar with a red minus badge, title, message, a red gradient button and Cancel.
/// Used for "Putuskan koneksi" and "Hapus akun".
struct ProfileConfirmSheet<Avatar: View>: View {
    let title: String
    let message: String
    let confirmTitle: String
    let confirmIdentifier: String
    let isWorking: Bool
    @ViewBuilder var avatar: Avatar
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 420

    /// Figma "Putuskan": #FF4F4F near the top to #BB1616 three quarters down (its gradient runs vertically).
    private var dangerGradient: LinearGradient { LinearGradient(
        stops: [.init(color: Color(hex: 0xFF4F4F), location: 0.05), .init(color: Color(hex: 0xBB1616), location: 0.75)],
        startPoint: .top, endPoint: .bottom
    ) }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(ProfileStyle.grabber).frame(width: 36, height: 5)
                .padding(.top, 10)
                .accessibilityHidden(true)
            ZStack(alignment: .bottomTrailing) {
                avatar.frame(width: 64, height: 64)
                // Figma "Minus": 24 pt red circle, 2.5 pt white ring, a 10 × 3 white bar.
                RoundedRectangle(cornerRadius: 1.25)
                    .fill(.white)
                    .frame(width: 10, height: 3)
                    .frame(width: 24, height: 24)
                    .background(ProfileStyle.red, in: Circle())
                    .overlay(Circle().strokeBorder(ProfileStyle.card, lineWidth: 2.5))
                    .offset(x: 4, y: 4)
            }
            .accessibilityHidden(true)
            .padding(.top, 22)
            Text(verbatim: title)
                .profileFont(22, .semibold, tracking: -0.44)
                .foregroundStyle(ProfileStyle.nameInk)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 18)
            Text(verbatim: message)
                .profileFont(15, tracking: -0.15)
                .foregroundStyle(ProfileStyle.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 8)
            VStack(spacing: 10) {
                Button(action: onConfirm) {
                    HStack(spacing: 8) {
                        if isWorking {
                            ProgressView().tint(.white)
                                .transition(.opacity)
                        } else {
                            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 19, weight: .semibold))
                                .frame(width: 22, height: 22)
                                .accessibilityHidden(true)
                                .transition(.opacity)
                        }
                        Text(verbatim: confirmTitle).profileFont(17, .semibold, tracking: -0.21)
                    }
                    // Icon ↔ spinner: a 0.2 s cross-fade like "Remind".
                    .animation(.easeInOut(duration: 0.2), value: isWorking)
                    .foregroundStyle(.white)
                    // Figma: icon and label cast black 20 %, y 4, blur 4.
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 4)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(dangerGradient, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(hex: 0xBB1616), lineWidth: 1.5))
                }
                .disabled(isWorking)
                .accessibilityIdentifier(confirmIdentifier)
                Button { dismiss() } label: {
                    Text("Cancel")
                        .profileFont(17, .semibold, tracking: -0.17)
                        .foregroundStyle(ProfileStyle.ink)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(ProfileStyle.iconFill, in: Capsule())
                }
                .disabled(isWorking)
                .accessibilityIdentifier("profile.confirm.cancel")
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(ProfileStyle.card)
        .interactiveDismissDisabled(isWorking)
    }
}
