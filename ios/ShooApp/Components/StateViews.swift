import SwiftUI

// Error, empty and loading pieces shared by the state frames of the Figma board "alief state" (section 1685:5288).
// Motion stays short (≤ 0.35 s) and turns into a plain fade with "Kurangi gerakan" / Reduce Motion.

// MARK: - Motion

enum StateMotion {
    /// A state card or banner arriving.
    static func enter(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.32, bounce: 0.18)
    }

    /// Insertion / removal for a card or banner: a short rise with the fade; only the fade with Reduce Motion.
    static func transition(reduceMotion: Bool, edge: Edge = .bottom) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: edge)).combined(with: .scale(scale: 0.98))
    }
}

/// Rises 10 pt and fades in once, when it first appears. Reliable where `.transition` on a loader → content swap
/// can hard-cut on heavy screens (motion recipe 2026-11-12).
struct StateEntrance: ViewModifier {
    var delay: Double = 0
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                withAnimation(StateMotion.enter(reduceMotion: reduceMotion).delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// See `StateEntrance`.
    func stateEntrance(delay: Double = 0) -> some View { modifier(StateEntrance(delay: delay)) }
}

// MARK: - Notice card

/// Figma "Pesan verdict" (1665:3122 "Gagal memuat", 1665:3183 "Gagal menyimpan", 1665:3387 "Belum bisa ditandai"):
/// white 90 % with a #C81414 28 % ring, a 40 pt tile (#B73C13 12 %, 8 pt corners) with the symbol in #BB1616 70 %,
/// the title (SF Pro Rounded Semibold 17) over the line (13, #6A717E), the action in #136CB7 on the right.
/// The symbol wiggles (error) or bounces (info) once when the card arrives; the action shows a spinner while it runs.
struct StateNoticeCard: View {
    enum Tone {
        /// "Gagal memuat", "Gagal menyimpan": a circular arrow with a "!".
        case error
        /// "Belum bisa ditandai": an "i".
        case info

        var symbol: String {
            switch self {
            case .error: "exclamationmark.arrow.circlepath"
            case .info: "info.circle"
            }
        }
    }

    var tone: Tone = .error
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var cornerRadius: CGFloat = 12
    var action: (() async -> Void)?

    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var isRunning = false
    /// Bumped on appear and on every failed retry: the symbol's one-shot effect.
    @State private var nudge = 0

    static let ink = Color(hex: 0x151617)
    static let line = Color(hex: 0x6A717E)
    static let actionInk = Color(hex: 0x136CB7)
    static let red = Color(hex: 0xC81414)

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .onboardingFont(17, weight: .semibold, design: .rounded, tracking: -0.43, relativeTo: .body)
                    .figmaLineHeight(22, relativeTo: .body)
                    .foregroundStyle(Self.ink)
                Text(message)
                    .onboardingFont(13, design: .rounded, tracking: -0.08, relativeTo: .footnote)
                    .figmaLineHeight(18, relativeTo: .footnote)
                    .foregroundStyle(Self.line)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            if let actionTitle, let action {
                Button {
                    guard !isRunning else { return }
                    Task {
                        isRunning = true
                        await action()
                        isRunning = false
                        nudge += 1
                    }
                } label: {
                    ZStack {
                        Text(actionTitle)
                            .onboardingFont(16.5, weight: .semibold, relativeTo: .headline)
                            .opacity(isRunning ? 0 : 1)
                        if isRunning {
                            ProgressView().controlSize(.small).tint(Self.actionInk)
                        }
                    }
                    .foregroundStyle(Self.actionInk)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .animation(.easeOut(duration: 0.15), value: isRunning)
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(isRunning)
                .accessibilityIdentifier("state.notice.action")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Self.red.opacity(0.28)))
        .onAppear { nudge += 1 }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var icon: some View {
        let image = Image(systemName: tone.symbol)
            .font(.system(size: 21.67, weight: .regular, design: .rounded))
            .foregroundStyle(Color(hex: 0xBB1616).opacity(0.7))
            .frame(width: 40, height: 40)
            .background(Color(hex: 0xB73C13).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
        if reduceMotion {
            image
        } else if #available(iOS 18, *), tone == .error {
            image.symbolEffect(.wiggle.byLayer, options: .nonRepeating, value: nudge)
        } else {
            image.symbolEffect(.bounce, options: .nonRepeating, value: nudge)
        }
    }
}

/// A light press: 97 % and back, for text actions inside cards.
struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.shooReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Centred message

/// A centred state: an 80 pt tile with the symbol, the title (SF Pro Semibold 20) and the line (SF Pro Rounded 17,
/// #6A717E). Figma "Kirim Undangan · Gagal mengambil kode / Keluarga penuh" (tile = the tint at 12 %) and
/// "Detail Orang Dilindungi · Sudah tidak terhubung / Gagal memuat" (white tile). Settles in with a spring; the
/// symbol bounces once.
struct StateMessage: View {
    let systemImage: String
    /// Figma: 34 for the error symbol, 27 for the people.
    var symbolSize: CGFloat = 34
    let tint: Color
    /// nil: the tint at 12 %.
    var tileFill: Color?
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : shown)
                .frame(width: 80, height: 80)
                .background(tileFill ?? tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .scaleEffect(shown || reduceMotion ? 1 : 0.85)
                .accessibilityHidden(true)
            Text(title)
                .onboardingFont(20, weight: .semibold, relativeTo: .title3)
                .foregroundStyle(Color(hex: 0x151617))
                .padding(.top, 24)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .onboardingFont(17, design: .rounded, relativeTo: .body)
                .figmaLineHeight(22, relativeTo: .body)
                .foregroundStyle(Color(hex: 0x6A717E))
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.top, 52)
        .opacity(shown ? 1 : 0)
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.3)) { shown = true }
        }
    }
}

// MARK: - Skeleton

/// A soft highlight that sweeps across while something loads; still with Reduce Motion.
struct Shimmer: ViewModifier {
    var active = true
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.6)
                            .offset(x: phase * proxy.size.width * 1.6)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
                    }
                }
            }
    }
}

extension View {
    /// See `Shimmer`.
    func shimmering(_ active: Bool = true) -> some View { modifier(Shimmer(active: active)) }
}

/// Figma "Skeleton row" (1666:3717): #F3F6FA, 16 pt corners, 74 pt; a 44 pt disc, bars of 150 × 12 and 96 × 10,
/// a 62 × 24 chip on the right.
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(Color(hex: 0xE2E7EE)).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 10) {
                Capsule().fill(Color(hex: 0xE2E7EE)).frame(width: 150, height: 12)
                Capsule().fill(Color(hex: 0xEAEEF3)).frame(width: 96, height: 10)
            }
            Spacer(minLength: 0)
            Capsule().fill(Color(hex: 0xEAEEF3)).frame(width: 62, height: 24)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(height: 74)
        .background(Color(hex: 0xF3F6FA), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// "Aktivitas Terakhir" with grey rows: what the list will hold once it loads.
struct SkeletonActivity: View {
    var rows = 3
    /// Sweeps while the next try runs; still when the load has failed.
    var animating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionTitle("Recent activity")
            VStack(spacing: 10) {
                ForEach(0..<rows, id: \.self) { _ in SkeletonRow() }
            }
            .shimmering(animating)
        }
        .accessibilityElement(children: .ignore)
    }
}

#Preview {
    VStack(spacing: 20) {
        StateNoticeCard(title: "Couldn't load", message: "Check your connection.", actionTitle: "Try again") {
            try? await Task.sleep(for: .seconds(1))
        }
        StateNoticeCard(tone: .info, title: "Can't be marked yet", message: "Open this site's details first.",
                        actionTitle: "Open details") {}
        SkeletonActivity(animating: true)
    }
    .padding(24)
    .background(HomeTheme.background)
}
