import SwiftUI

/// Colours from Figma "Guardian/Home" (node 232:6093). Light only, like the onboarding screens.
enum HomeTheme {
    static let background = Color(red: 0xF3 / 255, green: 0xF6 / 255, blue: 0xF8 / 255)
    static let heroDark = Color(red: 0x1E / 255, green: 0x78 / 255, blue: 0xBE / 255)
    static let heroLight = Color(red: 0x68 / 255, green: 0xCD / 255, blue: 0xFA / 255)
    static let heroGlow = Color(red: 0x8F / 255, green: 0xE9 / 255, blue: 0xEC / 255)
    static let navy = Color(red: 0x19 / 255, green: 0x1D / 255, blue: 0x2F / 255)
    static let ink = Color(red: 0x15 / 255, green: 0x16 / 255, blue: 0x17 / 255)
    /// Figma #6A717E is 4.6:1 on white.
    static let secondaryInk = Color(red: 0x6A / 255, green: 0x71 / 255, blue: 0x7E / 255)
    static let tileIcon = Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x3B / 255)
    static let tileIconBackground = Color(red: 0xF3 / 255, green: 0xF6 / 255, blue: 0xF8 / 255)
    static let rowStroke = Color(red: 0xE2 / 255, green: 0xE8 / 255, blue: 0xF0 / 255)
    /// Figma #D67D00 is 2.9:1 on its chip; darkened to 4.6:1 for 13 pt text.
    static let warningText = Color(red: 0xA8 / 255, green: 0x5A / 255, blue: 0x00 / 255)
    static let warningFill = Color(red: 0xFF / 255, green: 0xF8 / 255, blue: 0xEF / 255)
    static let warningStroke = Color(red: 0xFF / 255, green: 0xE1 / 255, blue: 0xB6 / 255)
    static let warningRing = Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
    static let dangerText = Color(red: 0xBB / 255, green: 0x16 / 255, blue: 0x16 / 255)
    static let dangerFill = Color(red: 0xFF / 255, green: 0xF4 / 255, blue: 0xF4 / 255)
    static let dangerStroke = Color(red: 0xFF / 255, green: 0xCD / 255, blue: 0xCD / 255)
    /// Red that keeps 4.5:1 on the navy status strip.
    static let dangerOnNavy = Color(red: 0xFF / 255, green: 0x7A / 255, blue: 0x70 / 255)
}

/// Guardian Home (GD-01): hero with the glowing shield, security status, the family's numbers or the site
/// that waits for a verdict, and recent activity. Family mode off; the pill switches to the family (GD-02/03).
struct GuardianHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var model: GuardianHomeModel
    @State private var isTurnOffPresented = false
    /// The hero is scrolled out from under the bar: the top scrim takes over as the dark backdrop.
    @State private var isHeroHidden = false

    init(
        repository: any ShooRepository,
        settings: AppSettings,
        extensionStatus: @escaping () async -> ExtensionStatus
    ) {
        _model = State(initialValue: GuardianHomeModel(repository: repository, settings: settings, extensionStatus: extensionStatus))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HomeHero(
                    isActive: model.extensionStatus.isActive,
                    onLink: {
                        if model.extensionStatus.isActive { isTurnOffPresented = true } else { env.router.isTurnOnPresented = true }
                    }
                )
                .onGeometryChange(for: Bool.self) { $0.frame(in: .global).maxY < 140 } action: { isHeroHidden = $0 }
                VStack(spacing: 0) {
                    StatusStrip(level: model.level)
                    VStack(spacing: 24) {
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .background(HomeTheme.background, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
                    .padding(.top, -22)
                }
                .padding(.top, -44)
            }
            // Light only, like the Figma; scoped to the page so the bars keep their own scheme.
            .environment(\.colorScheme, .light)
        }
        .scrollIndicators(.hidden)
        .background(HomeTheme.background)
        // Pill and profile live in the (see-through) navigation bar, so the status bar turns white on the hero.
        .toolbar {
            FamilySwitchToolbarItem(members: model.members, action: switchToFamily)
            HomeProfileToolbarItem(name: model.profile?.name) { env.router.openProfile() }
        }
        // Once the hero is gone, a navy scrim keeps the white status bar and pill readable over light content.
        .overlay(alignment: .top) {
            LinearGradient(colors: [HomeTheme.navy, HomeTheme.navy.opacity(0.85), HomeTheme.navy.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .ignoresSafeArea(edges: .top)
                .opacity(isHeroHidden ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: isHeroHidden)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // App switcher snapshot on disk must not hold scam URLs or names (D-alief-A36).
        .privacyCover()
        .refreshable { await model.refresh() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.refresh()
        }
        .onChange(of: model.extensionStatus.isActive) { _, isActive in
            guard model.state == .loaded else { return }
            AccessibilityNotification.Announcement(
                L10n.string(isActive ? "You're protected!" : "You're not protected yet", language: language)
            ).post()
        }
        .sheet(
            isPresented: Binding(get: { env.router.isTurnOnPresented }, set: { env.router.isTurnOnPresented = $0 }),
            onDismiss: {
                env.router.sheetDismissed()
                Task { await model.refresh() }
            }
        ) {
            TurnOnExtensionSheet()
        }
        .sheet(isPresented: $isTurnOffPresented, onDismiss: { Task { await model.refresh() } }) {
            TurnOffExtensionSheet()
                .environment(\.locale, locale)
        }
    }

    private func switchToFamily() {
        env.settings.familyModeOn = true
        AccessibilityNotification.Announcement(
            L10n.string("Family mode on. Showing your family.", language: env.settings.language)
        ).post()
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 216)
                .accessibilityLabel(Text("Loading"))
        case .failed:
            VStack(spacing: 12) {
                Text("Couldn't load your Shield").font(.headline)
                Text("Check your connection and try again.").foregroundStyle(.primary)
                Button { Task { await model.retry() } } label: { Text("Try again").frame(minHeight: 44) }
                    .buttonStyle(.borderedProminent)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 216)
        case .loaded:
            if let scan = model.pendingScan {
                PendingSiteCard(
                    scan: scan,
                    level: model.level,
                    language: language,
                    canDecide: model.canDecide,
                    failed: model.verdictFailed,
                    notAllowed: model.verdictNotAllowed,
                    onOpen: { env.router.showDetail(scanId: scan.id) },
                    onClose: model.dismissPending,
                    onDecide: { value in Task { await model.decide(value) } }
                )
                .id(scan.id)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                StatsGrid(stats: model.stats)
            }
            RecentActivity(
                scans: model.recent,
                language: language,
                avatarId: model.avatarId(for:),
                onOpen: { env.router.showDetail(scanId: $0.id) },
                onSeeAll: { env.router.selectedTab = .activity }
            )
        }
    }
}

// MARK: - Hero

private struct HomeHero: View {
    let isActive: Bool
    let onLink: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GlowingShield(isActive: isActive)
                .padding(.top, 24)

            VStack(spacing: 12) {
                Text(isActive ? "You're protected!" : "You're not protected yet")
                    .onboardingFont(27, weight: .bold, relativeTo: .title)
                    .tracking(-0.27)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: HomeTheme.heroDark.opacity(0.35), radius: 6, y: 2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(isActive ? "home.status.active" : "home.status.off")
                Button(action: onLink) {
                    Text(isActive ? "Disconnect?" : "Turn on now")
                        .onboardingFont(15, weight: .medium, relativeTo: .subheadline)
                        .tracking(-0.15)
                        .underline()
                        .foregroundStyle(HomeTheme.navy)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(isActive ? "Shows how to switch Shoo off in Safari" : "Shows how to switch Shoo on in Safari"))
                .accessibilityIdentifier(isActive ? "home.disconnect" : "home.turnOn")
            }
            .padding(.top, 28)
            .padding(.horizontal, 24)
            .padding(.bottom, 64)
        }
        .frame(maxWidth: .infinity)
        // Reaches up under the navigation bar, the status bar and the pull-to-refresh overscroll.
        .background { HeroBackground().padding(.top, -400) }
    }
}

/// Figma "Gradient-classic-2 lighter": deep blue top left, light cyan bottom right, film grain.
private struct HeroBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [HomeTheme.heroDark, HomeTheme.heroLight, HomeTheme.heroGlow.opacity(0.9)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse()
                    .fill(HomeTheme.heroDark)
                    .frame(width: proxy.size.width * 1.7, height: proxy.size.height * 0.9)
                    .offset(x: -proxy.size.width * 0.3, y: -proxy.size.height * 0.3)
                    .blur(radius: 70)
                Image("HeroTexture")
                    .resizable(resizingMode: .tile)
                    .blendMode(.multiply)
                    .opacity(0.35)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

/// Top-left glass pill: up to 3 family avatars and ⇆ (GD-02). Also shown in Family view to come back.
struct FamilySwitchPill: View {
    let members: [FamilyMember]
    let action: () -> Void
    var isFamilyShown = false
    /// White symbols over the hero, dark ones over light content.
    var onDarkBackground = true

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if members.isEmpty {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    HStack(spacing: -12) {
                        ForEach(members.prefix(FamilyShieldModel.maxMembers)) { member in
                            AvatarView(id: member.avatarId, size: 24)
                                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                        }
                    }
                }
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(onDarkBackground ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(minWidth: 88, minHeight: 44)
            .modifier(GlassCapsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Family mode"))
        .accessibilityValue(Text(isFamilyShown ? "On" : "Off"))
        .accessibilityAddTraits(.isToggle)
        .accessibilityHint(Text("Switches between your own Shield and your family's"))
        .accessibilityIdentifier("familyModeToggle")
    }
}

/// The pill as a navigation bar item. On iOS 26 the bar's own glass is turned off: the pill brings its own.
struct FamilySwitchToolbarItem: ToolbarContent {
    let members: [FamilyMember]
    let action: () -> Void
    var isFamilyShown = false
    var onDarkBackground = true

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { pill }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { pill }
        }
    }

    private var pill: some View {
        FamilySwitchPill(members: members, action: action, isFamilyShown: isFamilyShown, onDarkBackground: onDarkBackground)
    }
}

private struct HomeProfileToolbarItem: ToolbarContent {
    let name: String?
    let action: () -> Void

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarTrailing) { ProfileInitialButton(name: name, action: action) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { ProfileInitialButton(name: name, action: action) }
        }
    }
}

/// Liquid Glass on iOS 26, frosted material before.
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

/// Top-right circle with the guardian's initial; opens Profile (PF-01).
private struct ProfileInitialButton: View {
    let name: String?
    let action: () -> Void

    private var initial: String {
        name?.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? ""
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(LinearGradient(colors: [HomeTheme.heroLight, HomeTheme.heroDark],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                if initial.isEmpty {
                    Image(systemName: "person.fill").font(.system(size: 20, weight: .semibold))
                } else {
                    Text(verbatim: initial).font(.system(size: 20, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Profile"))
        .accessibilityIdentifier("profileButton")
    }
}

// MARK: - Status

private struct StatusStrip: View {
    let level: GuardianHomeModel.Level

    private var value: LocalizedStringKey {
        switch level {
        case .normal: "Good!"
        case .warning: "Under watch!"
        case .danger: "Danger!"
        }
    }

    private var valueColor: Color {
        level == .danger ? HomeTheme.dangerOnNavy : HomeTheme.heroGlow
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.grid.3x3.fill")
                .font(.system(size: 13))
                .accessibilityHidden(true)
            (Text("Security status:") + Text(verbatim: " ") + Text(value).foregroundStyle(valueColor))
                .onboardingFont(15, relativeTo: .subheadline)
                .tracking(-0.15)
        }
        .foregroundStyle(Color(red: 0xFA / 255, green: 0xF9 / 255, blue: 0xFB / 255))
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 34)
        .background(HomeTheme.navy, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.securityStatus")
    }
}

// MARK: - Normal: four tiles

private struct StatsGrid: View {
    let stats: GuardianHomeModel.Stats
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)]
        LazyVGrid(columns: columns, spacing: 0) {
            StatTile(systemImage: "network.badge.shield.half.filled", value: stats.blocked, title: "Threats blocked")
            StatTile(systemImage: "lock.open.fill", value: stats.warnings, title: "Security risks")
            StatTile(systemImage: "hand.raised.fill", value: stats.suspiciousHosts, title: "Suspicious hosts")
            StatTile(systemImage: "tray.full.fill", value: stats.scansToday, title: "Scans today")
        }
        .overlay {
            if !dynamicTypeSize.isAccessibilitySize {
                // Figma dividers: a vertical and a horizontal hairline that fade at the ends.
                ZStack {
                    LinearGradient(colors: [HomeTheme.rowStroke, HomeTheme.rowStroke.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(width: 1)
                    LinearGradient(colors: [HomeTheme.rowStroke.opacity(0), HomeTheme.rowStroke, HomeTheme.rowStroke.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(height: 1)
                }
                .padding(.vertical, 8)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("home.stats")
    }
}

private struct StatTile: View {
    let systemImage: String
    let value: Int
    let title: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(HomeTheme.tileIcon)
                    .frame(width: 30, height: 30)
                    .background(HomeTheme.tileIconBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                Spacer()
                Text(verbatim: "\(value)")
                    .onboardingFont(23, weight: .bold, relativeTo: .title2)
                    .monospacedDigit()
                    .foregroundStyle(HomeTheme.ink)
            }
            Text(title)
                .textCase(.uppercase)
                .onboardingFont(13, weight: .medium, relativeTo: .footnote)
                .foregroundStyle(HomeTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: "\(value)"))
    }
}

// MARK: - Warning / Danger: the site that waits

private struct PendingSiteCard: View {
    let scan: ScanResult
    let level: GuardianHomeModel.Level
    let language: AppLanguage
    let canDecide: Bool
    let failed: Bool
    let notAllowed: Bool
    let onOpen: () -> Void
    let onClose: () -> Void
    let onDecide: (Verdict.Value) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isDanger: Bool { level == .danger }
    private var accent: Color { isDanger ? HomeTheme.tileIcon : HomeTheme.warningRing }
    private var riskTitle: LocalizedStringKey { isDanger ? "Very high risk" : "High risk" }
    private var title: String { scan.pageTitle?.isEmpty == false ? scan.pageTitle! : scan.domain }
    private var reason: String? {
        Evidence.top(scan.signals, mode: .guardian, language: language, limit: 1).first?.text
    }

    private var titleText: some View {
        Text(verbatim: title)
            .onboardingFont(20, weight: .medium, relativeTo: .title3)
            .foregroundStyle(HomeTheme.navy)
    }

    private var domainChip: some View {
        Text(verbatim: scan.domain)
            .onboardingFont(13, relativeTo: .footnote)
            .foregroundStyle(HomeTheme.navy)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color(red: 0xE4 / 255, green: 0xE9 / 255, blue: 0xED / 255), in: Capsule())
    }

    var body: some View {
        VStack(spacing: 16) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: Formatters.dateTime(scan.detectedAt, language: language).uppercased(with: language.locale))
                            .onboardingFont(13, relativeTo: .footnote)
                            .tracking(1.3)
                            .foregroundStyle(HomeTheme.secondaryInk)
                        // Title and site side by side when both fit; otherwise the site goes under the title.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                titleText.fixedSize()
                                domainChip
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                titleText.lineLimit(2)
                                domainChip
                            }
                        }
                        .padding(.trailing, 48)
                    }
                    VStack(spacing: 20) {
                        RiskRing(score: scan.score, color: accent, language: language)
                        Text(riskTitle)
                            .textCase(.uppercase)
                            .onboardingFont(19, weight: .semibold, relativeTo: .headline)
                            .tracking(2)
                            .foregroundStyle(isDanger ? HomeTheme.dangerText : HomeTheme.warningText)
                    }
                    .frame(maxWidth: .infinity)
                    if let reason {
                        Text(verbatim: reason)
                            .onboardingFont(15, relativeTo: .subheadline)
                            .lineSpacing(6)
                            .foregroundStyle(HomeTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .background(HomeTheme.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Opens the details"))
            .accessibilityIdentifier("home.pending")
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HomeTheme.navy)
                        .frame(width: 40, height: 40)
                        .background(.white, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(14)
                .accessibilityLabel(Text("Close"))
                .accessibilityHint(Text("Hides this site from Home"))
                .accessibilityIdentifier("home.pending.close")
            }

            if canDecide {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    DecisionButton(title: "Danger", systemImage: "exclamationmark.circle.fill", tint: HomeTheme.tileIcon,
                                   textColor: HomeTheme.dangerText) { onDecide(.notSafe) }
                        .accessibilityIdentifier("home.verdict.notSafe")
                    DecisionButton(title: "Safe", systemImage: "checkmark.circle.fill", tint: HomeTheme.navy,
                                   textColor: HomeTheme.navy) { onDecide(.safe) }
                        .accessibilityIdentifier("home.verdict.safe")
                }
            }
            if failed {
                Label("Couldn't save. Check your connection and try again.", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("home.verdictError")
            }
            if notAllowed {
                Label("This site can't be marked yet. Open the details to see more.", systemImage: "info.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("home.verdictNotAllowed")
            }
        }
        .padding(10)
        .padding(.bottom, canDecide ? 6 : 0)
        .background(.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

/// Figma ring: thick arc in the risk colour on a pale track, soft glow, big number in the middle.
private struct RiskRing: View {
    let score: Int
    let color: Color
    let language: AppLanguage
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 200

    private var side: CGFloat { min(size, 260) }
    private var progress: CGFloat { CGFloat(min(max(score, 0), 100)) / 100 }

    var body: some View {
        ZStack {
            Circle().fill(.white).shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            Circle()
                .stroke(Color(red: 0xEC / 255, green: 0xEE / 255, blue: 0xF0 / 255), lineWidth: side * 0.12)
                .padding(side * 0.06)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: side * 0.12, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .padding(side * 0.06)
                .shadow(color: color.opacity(0.55), radius: 10)
            Circle()
                .fill(.white)
                .padding(side * 0.17)
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            Text(verbatim: Formatters.percent(score, language: language))
                .font(.system(size: side * 0.22, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(HomeTheme.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Risk score"))
        .accessibilityValue(Text(verbatim: Formatters.percent(score, language: language)))
    }
}

private struct DecisionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let textColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title).foregroundStyle(textColor)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(tint)
            }
            .onboardingFont(19, weight: .medium, relativeTo: .headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(.white, in: Capsule())
            .overlay(Capsule().stroke(HomeTheme.rowStroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Applies right away. You can change it later."))
    }
}

// MARK: - Recent activity

private struct RecentActivity: View {
    let scans: [ScanResult]
    let language: AppLanguage
    let avatarId: (ScanResult) -> String?
    let onOpen: (ScanResult) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent activity")
                .onboardingFont(17, weight: .medium, relativeTo: .headline)
                .foregroundStyle(HomeTheme.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            if scans.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.shield",
                    title: "No risky sites yet",
                    message: "When Shoo warns about or blocks a site, you'll see it here."
                )
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    ForEach(scans) { scan in
                        Button { onOpen(scan) } label: {
                            RecentRow(scan: scan, avatarId: avatarId(scan), language: language)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.recent.\(scan.id)")
                    }
                }
                Button(action: onSeeAll) {
                    Text("See all")
                        .onboardingFont(17, weight: .medium, relativeTo: .headline)
                        .foregroundStyle(Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255))
                        .padding(.horizontal, 20)
                        .frame(minWidth: 130, minHeight: 50)
                        .modifier(GlassCapsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("home.seeAll")
            }
        }
    }
}

private struct RecentRow: View {
    let scan: ScanResult
    let avatarId: String?
    let language: AppLanguage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let avatarId {
                    AvatarView(id: avatarId, size: 48)
                } else {
                    Circle().fill(HomeTheme.tileIconBackground).overlay(Circle().stroke(HomeTheme.rowStroke, lineWidth: 1))
                        .frame(width: 48, height: 48)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: scan.domain)
                    .onboardingFont(17, relativeTo: .body)
                    .tracking(-0.17)
                    .foregroundStyle(HomeTheme.navy)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.middle)
                Text(verbatim: Formatters.dayAndTime(scan.detectedAt, language: language))
                    .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                    .foregroundStyle(HomeTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HomeStatusChip(badge: ScanBadge(scan: scan))
        }
        .padding(17)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the details"))
    }
}

/// Figma chip: pale fill, thin border, coloured text. Words always there, never colour only.
private struct HomeStatusChip: View {
    let badge: ScanBadge

    private var colors: (text: Color, fill: Color, stroke: Color) {
        switch badge {
        case .warning: (HomeTheme.warningText, HomeTheme.warningFill, HomeTheme.warningStroke)
        case .blocked, .verifiedScam: (HomeTheme.dangerText, HomeTheme.dangerFill, HomeTheme.dangerStroke)
        case .markedSafe: (Color(red: 0x1B / 255, green: 0x6E / 255, blue: 0x35 / 255), Color(red: 0xEF / 255, green: 0xFA / 255, blue: 0xF2 / 255),
                           Color(red: 0xC4 / 255, green: 0xEB / 255, blue: 0xCF / 255))
        }
    }

    private var title: LocalizedStringKey { badge == .warning ? "Caution" : badge.title }

    var body: some View {
        let colors = colors
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 11)).accessibilityHidden(true)
            Text(title).onboardingFont(13, relativeTo: .footnote).lineLimit(1)
        }
        .foregroundStyle(colors.text)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(colors.fill, in: Capsule())
        .overlay(Capsule().stroke(colors.stroke, lineWidth: 1))
        .fixedSize()
    }
}

#Preview {
    NavigationStack {
        GuardianHomeView(
            repository: MockRepository(mode: .guardian, latency: .zero),
            settings: AppSettings(defaults: UserDefaults(suiteName: "preview.home")!),
            extensionStatus: { .active(lastSeen: Date()) }
        )
    }
    .environment(AppEnvironment.preview())
}
