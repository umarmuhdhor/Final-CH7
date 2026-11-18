import SwiftUI

/// A whole-screen state with the blue hero, a shield on the dashed rings, then a white sheet (32 pt corners) with a
/// chip, the headline, the line, optional content and the button pinned at the foot.
/// Figma "Sesi berakhir" (1665:2991), "Detail Aktivitas · Sudah tidak ada" (1665:3006) and "· Gagal memuat"
/// (1665:3023). Motion: the shield settles in, then chip, text, content and button rise in one after the other.
struct StateHeroPage<Shield: View, Content: View, Footer: View>: View {
    enum ChipTone {
        case blue, red
        /// "Kedaluwarsa" (1665:3006): #4F6074 on itself at 10 %.
        case slate
        /// "Gangguan koneksi" (1665:3023): #B85A05 on #EF871C at 14 %.
        case orange

        var ink: Color {
            switch self {
            case .blue: Color(hex: 0x136CB7)
            case .red: Color(hex: 0xBB1616)
            case .slate: Color(hex: 0x4F6074)
            case .orange: Color(hex: 0xB85A05)
            }
        }

        var fill: Color {
            switch self {
            case .orange: Color(hex: 0xEF871C).opacity(0.14)
            case .blue, .red, .slate: ink.opacity(0.1)
            }
        }
    }

    /// The hero behind the shield: Home's blue, or a Figma export ("HeroGradientSlate", "HeroGradientOrange").
    enum Background {
        case blue
        case image(String)
    }

    var chip: LocalizedStringKey?
    var chipTone: ChipTone = .blue
    var background: Background = .blue
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var titleIdentifier: String?
    var onBack: (() -> Void)?
    var backIdentifier = "onboarding.back"
    @ViewBuilder let shield: Shield
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var shieldShown = false

    /// Figma: the rings' centre and the shield's top on the 402 × 874 frame; the sheet starts at y 380.
    private static var ringCenter: CGFloat { 225 }
    private static var sheetTop: CGFloat { 380 }
    /// The top safe area on the 402 × 874 Figma iPhone.
    private static var safeTop: CGFloat { 62 }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    HeroPulse()
                    shield
                        .scaleEffect(shieldShown || reduceMotion ? 1 : 0.86)
                        .opacity(shieldShown ? 1 : 0)
                }
                .frame(height: 236)
                .padding(.top, Self.ringCenter - 118 - Self.safeTop)
                .accessibilityHidden(true)

                sheet
                    .padding(.top, Self.sheetTop - (Self.ringCenter + 118))
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .contentMargins(.bottom, 104, for: .scrollContent)
        .background(alignment: .top) {
            Group {
                switch background {
                case .blue:
                    HeroBackground(style: .blue)
                case .image(let name):
                    // Figma "Gradient-classic-2 lighter" (402 × 449 at y −9) with its grain, then the "box" fade to white.
                    Image(name).resizable()
                        .overlay(alignment: .bottom) {
                            LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom)
                                .frame(height: 140)
                        }
                }
            }
            .frame(height: 450 + Self.safeTop)
            .ignoresSafeArea(edges: .top)
        }
        .background(Color.white.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            if let onBack {
                OnboardingBackButton(identifier: backIdentifier, action: onBack)
                    .padding(.leading, 24)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 16) { footer }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 34)
                .background {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom).frame(height: 24)
                        Color.white
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                .stateEntrance(delay: 0.24)
        }
        .onAppear {
            guard !shieldShown else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.3)) { shieldShown = true }
        }
        .environment(\.colorScheme, .light)
    }

    /// Figma "Sheet": 28 / 20 / 24 padding, 18 between the chip, the text and the content.
    private var sheet: some View {
        VStack(spacing: 18) {
            if let chip {
                // Figma "Chip": the ink at 10 %, 6 / 8 padding, SF Pro Rounded Semibold 11.88 in capitals.
                Text(chip)
                    .textCase(.uppercase)
                    .onboardingFont(11.88, weight: .semibold, design: .rounded, tracking: -0.23, relativeTo: .caption)
                    .figmaLineHeight(15.6, relativeTo: .caption)
                    .foregroundStyle(chipTone.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(chipTone.fill, in: Capsule())
                    .stateEntrance(delay: 0.06)
            }
            // Figma "Frame 2": SF Pro Display Medium 28 (120 %, −2 %), 8, SF Pro Rounded 17 (140 %) #6A717E.
            VStack(spacing: 8) {
                Text(title)
                    .onboardingFont(28, weight: .medium, relativeTo: .title)
                    .tracking(-0.56)
                    .figmaLineHeight(33.6, glyphOffset: -2, relativeTo: .title)
                    .foregroundStyle(Color(hex: 0x151617))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(titleIdentifier ?? "state.title")
                Text(message)
                    .onboardingFont(17, design: .rounded, relativeTo: .body)
                    .figmaLineHeight(23.8, relativeTo: .body)
                    .foregroundStyle(Color(hex: 0x6A717E))
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .stateEntrance(delay: 0.1)
            content
                .stateEntrance(delay: 0.16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 494, alignment: .top)
        .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
    }
}

/// Figma "Info" (1666:3648): #F5F8FC, 20 pt corners, 14 pt padding; rows of a 40 pt tile (the ink at 12 %, 12 pt
/// corners, the symbol bold 24) and SF Pro Rounded 17 at 70 %.
struct StateInfoList: View {
    struct Row: Identifiable {
        let id = UUID()
        let systemImage: String
        let text: LocalizedStringKey
    }

    let rows: [Row]
    var tint = Color(hex: 0x136CB7)
    /// Figma "Info" sits on #F5F8FC; Detail "Sudah tidak ada" lists its rows on the sheet itself.
    var boxed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    Image(systemName: row.systemImage)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .frame(width: 40, height: 40)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                    Text(row.text)
                        .onboardingFont(17, design: .rounded, tracking: -0.17, relativeTo: .body)
                        .figmaLineHeight(22, relativeTo: .body)
                        .foregroundStyle(Color(hex: 0x151617).opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(boxed ? 14 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(boxed ? Color(hex: 0xF5F8FC) : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
