import SwiftUI
import UIKit

/// Figma "Profile/Pribadi", "Profile/Guardian", "Guardian/Detail Orang Dilindungi" (PF-01): colours,
/// type and the building blocks every Profile screen shares. Values are the Figma ones.
enum ProfileStyle {
    static let background = Color(hex: 0xF5F8FC)
    static let topWash = Color(hex: 0xDCECFB)
    static let ink = Color(hex: 0x191D2F)
    static let nameInk = Color(hex: 0x151617)
    static let secondary = Color(hex: 0x6A717E)
    static let chevron = Color(hex: 0xC7C7CE)
    static let iconFill = Color(hex: 0xF1F4F8)
    static let divider = Color(hex: 0xEEF1F5)
    static let statsDivider = Color(hex: 0xE3E8EF)
    static let pillStroke = Color(hex: 0xDCDFE4)
    static let link = Color(hex: 0x186FB9)
    static let red = Color(hex: 0xE5483B)
    static let redIconFill = Color(hex: 0xFDECEA)
    static let green = Color(hex: 0x34C759)
    static let greenText = Color(hex: 0x1B7F3A)
    static let greenPill = Color(hex: 0xE8F8EE)
    static let offDot = Color(hex: 0x8E8E93)
    static let grabber = Color(hex: 0xD6DAE1)

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

/// Figma sizes that still follow Dynamic Type: the size scales with `relativeTo`, tracking with it.
private struct ProfileFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let base: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let tracking: CGFloat

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, tracking: CGFloat, relativeTo: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        base = size
        self.weight = weight
        self.design = design
        self.tracking = tracking
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight, design: design))
            .tracking(tracking * size / base)
    }
}

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
        return modifier(ProfileFont(
            size: size, weight: weight, design: rounded ? .rounded : .default, tracking: tracking, relativeTo: style
        ))
    }
}

// MARK: Screen

/// The grey page with the blue top wash and the round back button + centred title (Figma "Back", "Judul").
/// The navigation bar is hidden; the swipe back still works (`SwipeBackEnabler`).
struct ProfileScreen<Content: View>: View {
    let title: String.LocalizationValue
    @ViewBuilder var content: Content
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                content
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        // Content scrolling under the status bar stays readable.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 0)
                .background(ProfileStyle.topWash.opacity(0.96).ignoresSafeArea(edges: .top))
        }
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
                .profileFont(17, .semibold, tracking: -0.17)
                .foregroundStyle(ProfileStyle.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 60)
            HStack {
                Button { env.router.pop() } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ProfileStyle.ink)
                        .frame(width: 44, height: 44)
                        .background(.white, in: Circle())
                }
                .accessibilityLabel(Text("Back"))
                .accessibilityIdentifier("profile.back")
                Spacer()
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, ProfileStyle.margin)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }
}

/// Keeps the edge swipe back with the navigation bar hidden.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
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
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .profileFont(17, .medium, tracking: -0.17)
                    .foregroundStyle(ProfileStyle.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                trailing
            }
            ProfileCard { content }
        }
        .padding(.horizontal, ProfileStyle.margin)
        .padding(.top, 28)
    }
}

/// White rounded card (r 24) with 5 pt above and below its rows.
struct ProfileCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.9)))
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
                Text(verbatim: "Aa").profileFont(14, .semibold)
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
}

/// One 58 pt row: icon, title (+ optional grey subtitle), value / chevron.
struct ProfileRow: View {
    let symbol: String
    let title: Text
    var subtitle: Text?
    var accessory: ProfileRowAccessory = .chevron
    var titleColor: Color = ProfileStyle.ink
    var titleWeight: Font.Weight = .regular
    var iconTint: Color = ProfileStyle.ink
    var iconFill: Color = ProfileStyle.iconFill

    var body: some View {
        HStack(spacing: 12) {
            ProfileIcon(symbol: symbol, tint: iconTint, fill: iconFill)
            VStack(alignment: .leading, spacing: 1) {
                title
                    .profileFont(17, titleWeight, tracking: -0.17)
                    .foregroundStyle(titleColor)
                if let subtitle {
                    subtitle
                        .profileFont(13, rounded: true)
                        .foregroundStyle(ProfileStyle.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessoryView
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 11)
        .frame(minHeight: 58)
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
                    .profileFont(15, tracking: -0.15)
                    .foregroundStyle(color)
                    .multilineTextAlignment(.trailing)
                if showsChevron { chevron }
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

/// A row with a switch (Figma "Toggle", green #34C759).
struct ProfileToggleRow: View {
    let symbol: String
    let title: Text
    var subtitle: Text?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                ProfileIcon(symbol: symbol)
                VStack(alignment: .leading, spacing: 1) {
                    title
                        .profileFont(17, tracking: -0.17)
                        .foregroundStyle(ProfileStyle.ink)
                    if let subtitle {
                        subtitle
                            .profileFont(13, rounded: true)
                            .foregroundStyle(ProfileStyle.secondary)
                    }
                }
            }
        }
        .tint(ProfileStyle.green)
        .padding(.horizontal, 17)
        .padding(.vertical, 11)
        .frame(minHeight: 58)
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
                        .profileFont(20, .semibold, tracking: -0.4)
                        .foregroundStyle(ProfileStyle.nameInk)
                    Text(stat.label)
                        .profileFont(13, rounded: true)
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
    let banner: String
    var bannerHeight: CGFloat = 128
    let name: String
    let handle: String
    let stats: [ProfileStat]
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
                    .background(.white, in: Circle())
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                badge
                    .padding(.bottom, -5)
            }
            .padding(.horizontal, 12)
            .padding(.top, -52)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: name)
                    .profileFont(24, .semibold, tracking: -0.48)
                    .foregroundStyle(ProfileStyle.nameInk)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: handle)
                    .profileFont(14, rounded: true)
                    .foregroundStyle(ProfileStyle.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            if !stats.isEmpty {
                ProfileStatsStrip(stats: stats)
                    .padding(.top, 17)
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(.white.opacity(0.9)))
        .padding(.horizontal, 16)
    }
}

/// White capsule with a grey border ("Bagikan undangan", "Ingatkan").
struct ProfilePillButtonStyle: ButtonStyle {
    var tint: Color = ProfileStyle.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .profileFont(14, .medium, tracking: -0.14)
            .foregroundStyle(tint)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(.white, in: Capsule())
            .overlay(Capsule().stroke(ProfileStyle.pillStroke))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// Figma "QR Icon": three corner squares and four dots, 16 pt.
struct QRGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 16
            for origin in [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 10)] {
                let rect = CGRect(x: origin.x * s + 0.75, y: origin.y * s + 0.75, width: 6 * s - 1.5, height: 6 * s - 1.5)
                context.stroke(Path(roundedRect: rect, cornerRadius: 1.5 * s), with: .color(ProfileStyle.ink), lineWidth: 1.5)
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

    var body: some View {
        Text(verbatim: String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.system(size: size * 0.41, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(ProfileStyle.initialsGradient(avatarId: avatarId), in: Circle())
            .accessibilityHidden(true)
    }
}

/// "Diblokir" / "Waspada" chip on activity rows (Figma "Button" instance).
struct ProfileScanChip: View {
    let status: ScanStatus

    var body: some View {
        let blocked = status == .blocked
        HStack(spacing: 4) {
            Circle().fill(blocked ? Color(hex: 0xBB1616) : Color(hex: 0xD67D00)).frame(width: 6, height: 6)
            Text(blocked ? "Blocked" : "Caution")
                .profileFont(13, tracking: -0.16)
                // Figma's #D67D00 is about 3:1 on its tint; this darker orange keeps the text readable (4.5:1).
                .foregroundStyle(blocked ? Color(hex: 0xBB1616) : Color(hex: 0x9A5A00))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(blocked ? Color(hex: 0xFFF4F4) : Color(hex: 0xFFF8EF), in: Capsule())
        .overlay(Capsule().stroke(blocked ? Color(hex: 0xFFCDCD) : Color(hex: 0xFFE1B6)))
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

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(ProfileStyle.grabber).frame(width: 36, height: 5)
                .padding(.top, 10)
                .accessibilityHidden(true)
            ZStack(alignment: .bottomTrailing) {
                avatar.frame(width: 64, height: 64)
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(ProfileStyle.red, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
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
                .profileFont(15)
                .foregroundStyle(ProfileStyle.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 8)
            VStack(spacing: 10) {
                Button(action: onConfirm) {
                    HStack(spacing: 8) {
                        if isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 18, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        Text(verbatim: confirmTitle).profileFont(17, .semibold, tracking: -0.21)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(
                        LinearGradient(colors: [Color(hex: 0xBB1616), Color(hex: 0xFF4F4F)], startPoint: .leading, endPoint: .trailing),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(Color(hex: 0xBB1616)))
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
        .presentationBackground(.white)
        .interactiveDismissDisabled(isWorking)
    }
}
