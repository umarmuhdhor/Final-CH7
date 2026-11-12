import SwiftUI

/// Guardian Home, both sides of the ⇆ switch (GD-01/02/03, Figma HOME page).
/// `personal` (Family mode off, "Pribadi/Home" 435:20058, Waspada 955:10369, Bahaya 955:10467): the hero says how
/// the last day went, then own recent sites and the latest scams; with nobody to look after, the "Mode Terawasi"
/// card first (1382:10567).
/// `family` ("Guardian/Home/ no recently blocked or warning" 435:20373): teal hero, the people looked after, the site
/// that waits for a verdict (warning 1382:2599, blocked 1382:10314), the family's recent sites; nobody yet → the invite
/// code and how it works (1382:10466). No status strip any more: the white sheet sits right on the hero.
struct GuardianHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var model: GuardianHomeModel
    /// Someone joined from the invite card: the refresh that follows hands the sheet over with an animation.
    @State private var joinAnimates = false
    /// Bumped when that refresh shows the family: one success tap, the guardian's "connected" moment.
    @State private var joined = 0
    /// The hero is scrolled out from under the status bar: the top scrim takes over as its backdrop.
    @State private var isHeroHidden = false
    /// "Aman" on the pending card opens SafeReasonSheet for that site (its id, kept while the sheet is open).
    @State private var safeReasonScanId: String?

    init(
        repository: any ShooRepository,
        settings: AppSettings,
        scope: GuardianHomeModel.Scope,
        extensionStatus: @escaping () async -> ExtensionStatus,
        onVerdictSaved: @escaping @MainActor () -> Void = {}
    ) {
        _model = State(initialValue: GuardianHomeModel(
            repository: repository, settings: settings, scope: scope, extensionStatus: extensionStatus,
            onVerdictSaved: onVerdictSaved
        ))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }
    private var isFamily: Bool { model.scope == .family }
    /// Card to card, card to members, invite to family: a soft ease; a short cross-fade with Reduce Motion.
    private var handOver: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3) }
    private var scrim: Color { colorScheme == .dark ? HomeTheme.navy : HomeTheme.background }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .global).maxY < 140 } action: { isHeroHidden = $0 }
                if isFamily {
                    sheet.homeSheet()
                    VStack(spacing: 24) {
                        below
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, belowGap)
                    .padding(.bottom, 32)
                } else {
                    // Figma "Status" 957:10957: no strip, the page itself rounds up over the hero.
                    sheet
                        .padding(.horizontal, 24)
                        .padding(.top, 30)
                        .padding(.bottom, 32)
                        .frame(maxWidth: .infinity)
                        .background(HomeTheme.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
            // A verdict from the pending card: the next card (or the members row) and the headline ease in instead of
            // jumping. Keyed on the saved verdict, so loads and refreshes stay instant.
            .animation(handOver, value: model.verdictSaves)
            // Someone joined from the invite card: the family replaces the invite the same way. Only that refresh.
            .animation(joinAnimates ? handOver : nil, value: model.hasNoFamily)
            // Light only, like the Figma; scoped to the page so the bars keep their own scheme.
            .environment(\.colorScheme, .light)
        }
        // No navigation bar (see HomeTopBar): the page starts where the bar's bottom edge would be.
        .safeAreaPadding(.top, HomeTopBar.barHeight)
        .scrollIndicators(.hidden)
        .background(HomeTheme.background)
        // Once the hero is gone, a scrim keeps the status bar readable over the page: light behind dark text,
        // navy behind white text (dark appearance).
        .overlay(alignment: .top) {
            LinearGradient(colors: [scrim, scrim.opacity(0.85), scrim.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .ignoresSafeArea(edges: .top)
                .opacity(isHeroHidden ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: isHeroHidden)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        // Switch and profile right under the status bar, where the (hidden) navigation bar would be.
        .overlay(alignment: .top) {
            // The cached avatar until `GET /devices/me` answers, so the circle never waits for the network.
            HomeTopBar(isFamilyShown: isFamily, avatarId: model.profile?.avatarId ?? env.session?.avatarId, onSwitch: switchSide) {
                env.router.openProfile()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // App switcher snapshot on disk must not hold scam URLs or names (D-alief-A36).
        .privacyCover()
        .refreshable { await model.refresh() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.refresh()
        }
        .onChange(of: model.hasNoFamily) { hadNoFamily, hasNoFamily in
            if joinAnimates, hadNoFamily, !hasNoFamily { joined += 1 }
            joinAnimates = false
        }
        // Same haptic as a verdict saved on Detail (DetailView).
        .sensoryFeedback(.success, trigger: model.verdictSaves)
        // "Couldn't save" under Aman / Bahaya is felt too, not only read.
        .sensoryFeedback(.error, trigger: model.verdictFailed) { _, now in now }
        .sensoryFeedback(.success, trigger: joined)
        // A push while Home is open (new scan, verdict, member change): reload, not just the banner.
        .onChange(of: env.pushesWhileOpen) {
            Task { await model.refresh() }
        }
        .onChange(of: model.extensionStatus.isActive) { _, isActive in
            guard model.state == .loaded, !isFamily else { return }
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
    }

    private func switchSide() {
        if isFamily { env.settings.familyModeOn = false } else { env.requestFamilyMode() }
        AccessibilityNotification.Announcement(
            L10n.string(isFamily ? "Family mode off. Showing your Shield." : "Family mode on. Showing your family.",
                        language: env.settings.language)
        ).post()
    }

    // MARK: Hero and status

    @ViewBuilder
    private var hero: some View {
        if !isFamily {
            let isActive = model.extensionStatus.isActive
            // The level reads the last day's sites: while they load (or never loaded) the hero only says Shoo is
            // on, never "You're protected!" without the data behind it.
            let isChecking = isActive && model.state != .loaded
            // Shoo being off outranks what it saw while it was on.
            let level = isActive && !isChecking ? model.level : .normal
            HomeHero(
                style: level.heroStyle,
                title: !isActive ? "You're not protected yet" : isChecking ? "Shoo is on" : level.title,
                titleIdentifier: !isActive ? "home.status.off" : isChecking ? "home.status.checking" : level.titleIdentifier,
                shieldOn: isActive,
                shieldTint: level.shieldTint,
                bottomPadding: isActive ? nil : 20
            ) {
                if !isActive {
                    Button { env.router.isTurnOnPresented = true } label: {
                        Text("Turn on now")
                            .onboardingFont(15, weight: .medium, relativeTo: .subheadline)
                            .underline()
                            .foregroundStyle(.white)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Shows how to switch Shoo on in Safari"))
                    .accessibilityIdentifier("home.turnOn")
                }
            }
        } else if model.state == .failed {
            // Figma "Guardian/Home · Gagal memuat" (1665:3038): nothing loaded, so no "Family protected!".
            HomeHero(style: .teal, title: "Status not available yet", titleIdentifier: "home.family.unavailable",
                     shieldTint: .teal, layout: .family)
        } else if model.hasNoFamily {
            // Figma 1382:10466: the teal hero, white headline and line.
            HomeHero(style: .teal, title: "Protect your loved ones", titleIdentifier: "home.family.empty",
                     subtitle: "No one to protect yet", shieldTint: .teal, layout: .familyEmpty)
        } else if model.pendingScan != nil {
            // Figma 1382:2599 / 1382:10314: the hero stays teal; the card below carries the colour.
            HomeHero(style: .teal, title: model.level == .danger ? "Family under threat" : "Family needs confirmation",
                     titleIdentifier: "home.family.pending", shieldTint: .teal, layout: .familyPending)
        } else {
            HomeHero(style: .teal, title: "Family protected!", titleIdentifier: "home.family.protected", shieldTint: .teal,
                     layout: .family)
        }
    }

    /// From the bottom of the sheet to "Aktivitas Terakhir" / "Cara Kerja": 32 (435:20373), 7 (1382:2599),
    /// 22 (1382:10466).
    private var belowGap: CGFloat {
        guard model.state == .loaded else { return 24 }
        if model.hasNoFamily { return 22 }
        return model.pendingScan != nil ? 7 : 32
    }

    // MARK: Sheet

    @ViewBuilder
    private var sheet: some View {
        switch model.state {
        case .loading:
            // The rows that are coming, sweeping while they load.
            SkeletonActivity(rows: 3, animating: true)
                .padding(isFamily ? 24 : 0)
                .frame(maxWidth: .infinity, minHeight: 216, alignment: .top)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Loading"))
        case .failed:
            // Figma "Guardian/Home · Gagal memuat" (1665:3038): the card, "Aktivitas Terakhir", three grey rows.
            VStack(alignment: .leading, spacing: 22) {
                StateNoticeCard(title: "Couldn't load", message: "Check your connection.", actionTitle: "Try again") {
                    await model.retry()
                }
                .accessibilityIdentifier("home.loadError")
                .stateEntrance()
                SkeletonActivity(rows: 3)
            }
            .padding(.horizontal, isFamily ? 24 : 0)
            .padding(.vertical, isFamily ? 24 : 0)
        case .loaded:
            if !isFamily {
                // Figma 435:20058: the list, 35 pt, the scams; 1382:10567 puts the "Mode Terawasi" card first and
                // 37 pt between the three.
                let showsCard = model.showsSupervisedCard
                VStack(spacing: 0) {
                    if showsCard {
                        // "Hubungkan": joining a family as protected lives in Profile › Account mode
                        // ("Have an invite code?"), which checks that nobody is looked after first.
                        SupervisedModeCard(onConnect: { env.router.show(.profilePage(.mode)) }) {
                            withAnimation(.easeOut(duration: 0.2)) { model.dismissSupervisedCard() }
                        }
                        .padding(.top, 1)
                        .padding(.bottom, 37)
                        .transition(.opacity)
                    }
                    RecentActivity(
                        scans: model.recent,
                        language: language,
                        onOpen: { env.router.showDetail(scanId: $0.id) },
                        onSeeAll: { env.router.selectedTab = .activity }
                    )
                    // Figma: the title 32 under the sheet's top (the card sits 31 under it).
                    .padding(.top, showsCard ? 0 : 3)
                    if !model.scamCases.isEmpty {
                        LatestScamsCard(cases: model.scamCases)
                            .padding(.top, showsCard ? 37 : 35)
                    }
                }
            } else if model.hasNoFamily {
                // Figma "Konten" 1382:10499: the card 16 under the sheet's top, 24 from its sides, 20 above its bottom.
                InviteCodeCard(repository: env.repository) {
                    joinAnimates = true
                    Task { await model.refresh() }
                }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
            } else if let scan = model.pendingScan {
                PendingSiteCard(
                    scan: scan,
                    ownerAvatarId: model.avatarId(forOwner: scan.ownerDeviceId),
                    language: language,
                    canDecide: model.canDecide,
                    failed: model.verdictFailed,
                    notAllowed: model.verdictNotAllowed,
                    onOpen: { env.router.showDetail(scanId: scan.id) },
                    onDecide: { value in
                        // "Aman" overrides Shoo, so it asks why first; "Bahaya" applies at once.
                        if value == .safe { safeReasonScanId = scan.id } else { Task { await model.decide(value, scanId: scan.id) } }
                    },
                    onRetry: { await model.retryDecision() }
                )
                .sheet(isPresented: Binding(get: { safeReasonScanId != nil }, set: { if !$0 { safeReasonScanId = nil } })) {
                    SafeReasonSheet { notes in
                        guard let scanId = safeReasonScanId else { return true }
                        return await model.decide(.safe, notes: notes, scanId: scanId)
                    }
                }
                .id(scan.id)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            } else {
                // Figma "Status" 435:20432: the title 24 under the sheet's top, the row 8 under it, 16 above the bottom.
                VStack(alignment: .leading, spacing: 8) {
                    HomeSectionTitle("People you protect")
                    MembersRow(members: model.shownMembers) { env.router.show(.member(deviceId: $0.deviceId)) }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var below: some View {
        if model.state == .loaded {
            if model.hasNoFamily {
                HowItWorks()
                // Figma "Guardian/Home · Belum ada orang" (1253:2381): 42 under How it works.
                BecomeSupervisedCard(action: "Become supervised") { env.router.isJoinFamilyPresented = true }
                    .padding(.top, 18)
            } else {
                RecentActivity(
                    scans: model.recent,
                    language: language,
                    showsOwner: true,
                    seeAllPlacement: .below,
                    onOpen: { env.router.showDetail(scanId: $0.id) },
                    onSeeAll: { env.router.selectedTab = .activity }
                )
            }
        }
    }
}

// MARK: - Personal: the hero per level

private extension GuardianHomeModel.Level {
    var heroStyle: HomeHeroStyle {
        switch self {
        case .normal: .blue
        case .warning: .amber
        case .danger: .red
        }
    }

    var shieldTint: HalftoneShield.Tint {
        switch self {
        case .normal: .blue
        case .warning: .amber
        case .danger: .red
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .normal: "You're protected!"
        case .warning: "Stay alert!"
        case .danger: "Danger detected!"
        }
    }

    var titleIdentifier: String {
        switch self {
        case .normal: "home.status.active"
        case .warning: "home.status.warning"
        case .danger: "home.status.danger"
        }
    }
}

// MARK: - Family: the people looked after

/// Figma "Frame 1618872221": up to three people side by side, a dot for whether Shoo is on for them.
private struct MembersRow: View {
    let members: [FamilyMember]
    let onOpen: (FamilyMember) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        layout {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                if index > 0 {
                    if dynamicTypeSize.isAccessibilitySize {
                        FadingDivider()
                    } else {
                        // Figma Line 13 / 14: 100 pt, solid for the top half, fading out below, 9 pt under the row top;
                        // 16 pt either side.
                        LinearGradient(stops: [.init(color: HomeTheme.divider, location: 0), .init(color: HomeTheme.divider, location: 0.5),
                                               .init(color: HomeTheme.divider.opacity(0), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(width: 1, height: 100)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, 9)
                            .padding(.horizontal, 16)
                            .accessibilityHidden(true)
                    }
                }
                Button { onOpen(member) } label: {
                    MemberCell(member: member)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("family.member.\(member.deviceId)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("family.header")
    }
}

private struct MemberCell: View {
    let member: FamilyMember

    var body: some View {
        VStack(spacing: 8) {
            // Figma "Avatar": 44 pt, the member's picked avatar (the name is read out below it).
            AvatarView(id: member.avatarId, size: 44)
                .overlay(alignment: .bottomTrailing) {
                    // Figma: 12 pt dot, 1 pt white ring outside, flush with the avatar's bottom right.
                    Circle()
                        .fill(member.isConnected ? HomeTheme.success : HomeTheme.offline)
                        .frame(width: 12, height: 12)
                        .background(Circle().fill(.white).padding(-1))
                }
            VStack(spacing: 2) {
                // Figma "Info": SF Pro Rounded 17 (-1 %, 22 pt lines) #151617, then 13 (-0.08, 18 pt) Labels/Secondary.
                Text(verbatim: member.name)
                    .onboardingFont(17, design: .rounded, tracking: -0.17, relativeTo: .body)
                    .figmaLineHeight(22, relativeTo: .body)
                    .foregroundStyle(HomeTheme.ink)
                    .lineLimit(1)
                Text(member.isConnected ? "Active" : "Not connected")
                    .onboardingFont(13, design: .rounded, tracking: -0.08, relativeTo: .footnote)
                    .figmaLineHeight(18, glyphOffset: 1, relativeTo: .footnote)
                    .foregroundStyle(HomeTheme.memberStatus)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens their activity"))
    }
}

// MARK: - Family: the site that waits

/// Figma "Frame 1618872233" (warning 1382:3072, blocked 1382:10314): a frosted grey card with a soft glow at its
/// foot; the site and when with a ↗ to the details, the risk panel (shield, "Situs Mencurigakan!", the bar), who
/// opened it, the reason, then Aman / Bahaya. Points are from the card's top left.
private struct PendingSiteCard: View {
    let scan: ScanResult
    /// `nil`: the owner is not in the family list (yet); the neutral person is drawn.
    let ownerAvatarId: String?
    let language: AppLanguage
    let canDecide: Bool
    let failed: Bool
    let notAllowed: Bool
    let onOpen: () -> Void
    let onDecide: (Verdict.Value) -> Void
    var onRetry: () async -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.shooReduceMotion) private var reduceMotion

    private var isBlocked: Bool { scan.status == .blocked }
    private var reason: String? {
        Evidence.top(scan.signals, mode: .guardian, language: language, limit: 1).first?.text
    }
    /// Figma "Rectangle 9652": 147 pt from y 317, the colour fading in downwards, the whole fill at 20 %.
    private var glow: LinearGradient {
        let stops: [Color] = isBlocked
            ? [Color(hex: 0xF28D83).opacity(0), Color(hex: 0xF26153)]
            : [Color(hex: 0xFB9E20).opacity(0), Color(hex: 0xFB9E20)]
        return LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onOpen) {
                VStack(spacing: 0) {
                    header
                    // Figma: the panel 16.1 / 11.9 in from the card's sides, i.e. centred on the screen.
                    HomeRiskPanel(scan: scan, isDanger: isBlocked, layered: true)
                        .padding(.leading, 16.1)
                        .padding(.trailing, 11.9)
                        .padding(.top, 11.8)
                    // Centred on the screen too (2.1 right of the card's centre).
                    owner
                        .padding(.leading, 4.2)
                        .padding(.top, 5)
                    if let reason {
                        // Figma: SF Pro Rounded 15.97, 140 % lines, #6A717E; 21 from the left, 16.8 from the right.
                        Text(verbatim: reason)
                            .onboardingFont(15.97, design: .rounded, relativeTo: .subheadline)
                            .figmaLineHeight(22.36, relativeTo: .subheadline)
                            .foregroundStyle(OnboardingTheme.bodyInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 21)
                            .padding(.trailing, 16.8)
                            .padding(.top, 7.5)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Opens the details"))
            .accessibilityIdentifier("home.pending")

            if canDecide {
                // Figma: Aman 150.5, Bahaya 153.4, 9.7 apart.
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 9.7)) : AnyLayout(ProportionalRow(weights: [150.5, 153.4], spacing: 9.7))
                layout {
                    DecisionButton(kind: .safe) { onDecide(.safe) }
                        .accessibilityIdentifier("home.verdict.safe")
                    DecisionButton(kind: .danger) { onDecide(.notSafe) }
                        .accessibilityIdentifier("home.verdict.notSafe")
                }
                // Figma 1665:3387: while the site can't be marked, both buttons go grey and stop taking taps.
                .disabled(notAllowed)
                .grayscale(notAllowed ? 1 : 0)
                .opacity(notAllowed ? 0.5 : 1)
                .padding(.leading, 28.3)
                .padding(.trailing, 24.1)
                .padding(.top, 20)
            }
            // Figma "Pesan verdict" (1665:3183 / 1665:3387): the card's own foot, full width, 26 under the buttons.
            if failed {
                StateNoticeCard(title: "Couldn't save", message: "Check your connection.", actionTitle: "Try again",
                                cornerRadius: 16, action: onRetry)
                    .padding(.top, 26)
                    .transition(StateMotion.transition(reduceMotion: reduceMotion))
                    .accessibilityIdentifier("home.verdictError")
            } else if notAllowed {
                StateNoticeCard(tone: .info, title: "Can't be marked yet", message: "Open this site's details first.",
                                actionTitle: "Open details", cornerRadius: 16) { onOpen() }
                    .padding(.top, 26)
                    .transition(StateMotion.transition(reduceMotion: reduceMotion))
                    .accessibilityIdentifier("home.verdictNotAllowed")
            }
        }
        .animation(StateMotion.enter(reduceMotion: reduceMotion), value: failed)
        .animation(StateMotion.enter(reduceMotion: reduceMotion), value: notAllowed)
        .padding(.bottom, failed || notAllowed ? 0 : (canDecide ? 14.7 : 20))
        .frame(maxWidth: .infinity)
        .background {
            // #EDEDED at 50 % on the white sheet, 20.7 pt corners.
            RoundedRectangle(cornerRadius: 20.7, style: .continuous)
                .fill(Color(hex: 0xEDEDED).opacity(0.5))
                .overlay(alignment: .bottom) {
                    glow.opacity(0.2).frame(height: 143)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20.7, style: .continuous))
        }
        // Figma "Konten": the card 16 under the sheet's top and above its bottom, 16 from the left, 20 from the right.
        .padding(.vertical, 16)
        .padding(.leading, 16)
        .padding(.trailing, 20)
    }

    /// Figma "Frame 1618872182": the 49.6 pt icon, the site (SF Pro Rounded 17.58) and when (13.44) beside it,
    /// a white 41.4 pt circle with ↗ on the right.
    private var header: some View {
        HStack(alignment: .top, spacing: 12.4) {
            SiteIcon(url: scan.faviconUrl, size: 49.6)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: scan.domain)
                    .onboardingFont(17.58, design: .rounded, tracking: -0.18, relativeTo: .body)
                    .figmaLineHeight(22.7, relativeTo: .body)
                    .foregroundStyle(HomeTheme.navy)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.middle)
                    .padding(.vertical, 1)
                Text(verbatim: Formatters.dayAndTime(scan.detectedAt, language: language))
                    .onboardingFont(13.44, design: .rounded, tracking: -0.08, relativeTo: .footnote)
                    .figmaLineHeight(18.6, relativeTo: .footnote)
                    .foregroundStyle(HomeTheme.rowSubtitle)
            }
            .padding(.top, 2.9)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Figma "Status Badge": SF Symbol arrow.up.right (U+100C3E) semibold 15.07, #1A1A1A, on white.
            Image(systemName: "arrow.up.right")
                .font(.system(size: 15.07, weight: .semibold))
                .foregroundStyle(HomeTheme.glassInk)
                .frame(width: 41.4, height: 41.4)
                .background(.white, in: Circle())
                .padding(.top, 6.2)
                .accessibilityHidden(true)
        }
        .padding(.leading, 17.6)
        .padding(.trailing, 14.4)
        .padding(.top, 14.5)
    }

    /// Figma "Frame 1618872332": the person's avatar (20.5 pt) and name in capitals, SF Pro Rounded Semibold 11.88.
    private var owner: some View {
        HStack(spacing: 8.9) {
            AvatarView(id: ownerAvatarId ?? "", size: 20.5)
            Text(verbatim: scan.ownerName.uppercased(with: language.locale))
                .onboardingFont(11.88, weight: .semibold, design: .rounded, tracking: -0.23, relativeTo: .caption)
                .figmaLineHeight(15.6, relativeTo: .caption)
                .foregroundStyle(HomeTheme.ink)
                .lineLimit(1)
        }
    }
}

/// Lays its children side by side at widths in proportion to `weights` (Figma's fixed button widths).
private struct ProportionalRow: Layout {
    let weights: [CGFloat]
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = self.widths(total: proposal.width ?? weights.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0)),
                                 count: subviews.count)
        let height = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: proposal.height)).height }.max() ?? 0
        return CGSize(width: proposal.width ?? widths.reduce(0, +), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(total: bounds.width, count: subviews.count)) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func widths(total: CGFloat, count: Int) -> [CGFloat] {
        let used = Array(weights.prefix(count))
        let sum = used.reduce(0, +)
        let free = max(0, total - spacing * CGFloat(max(count - 1, 0)))
        return used.map { sum > 0 ? free * $0 / sum : free / CGFloat(count) }
    }
}

/// Figma "Aman" (1382:10974) and "Bahaya" (1382:10977): 38.9 pt capsules side by side, a 1 pt #E3E3E3 ring and the
/// small drop shadow; Aman white with ✓ (checkmark.circle.fill, U+100063), Bahaya the red gradient with the alert icon.
private struct DecisionButton: View {
    enum Kind { case safe, danger }

    let kind: Kind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: kind == .safe ? 7.77 : 6.63) {
                if kind == .safe {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16.5, weight: .semibold))
                    Text("Safe")
                        .onboardingFont(16.5, weight: .semibold, relativeTo: .headline)
                        .figmaLineHeight(21.4, relativeTo: .headline)
                } else {
                    Image("HomeAlertCircle")
                        .resizable()
                        .frame(width: 18.2, height: 18.2)
                    Text("Danger")
                        .onboardingFont(14.08, weight: .semibold, relativeTo: .subheadline)
                        .figmaLineHeight(18.2, relativeTo: .subheadline)
                }
            }
            .foregroundStyle(kind == .safe ? HomeTheme.navy : .white)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 38.9)
            .background {
                if kind == .safe {
                    Capsule().fill(.white)
                } else {
                    Capsule().fill(LinearGradient(colors: [Color(hex: 0xF64747), Color(hex: 0xBB1616)], startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay(Capsule().stroke(Color(hex: 0xE3E3E3), lineWidth: 0.97).padding(-0.485))
            .figmaButtonShadow()
            // The capsule is 38.9 pt; the touch area still reaches 44.
            .contentShape(Capsule().inset(by: -2.6))
        }
        .buttonStyle(DecisionPressStyle())
        .accessibilityHint(Text("Applies right away. You can change it later."))
    }
}

/// Aman / Bahaya give under the finger like the Detail verdict buttons (`VerdictButtonStyle`). Reduce Motion:
/// they dim instead of shrinking. The look and hit area are the label's own.
private struct DecisionPressStyle: ButtonStyle {
    @Environment(\.shooReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Family: nobody yet

/// Figma "Kode Undangan" (1382:10500): QR, the code with how long it lasts; Bagikan / Salin centred under the card
/// ("Aksi" 1382:10506) (GD-04).
private struct InviteCodeCard: View {
    let onJoined: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var model: FamilyCodeModel

    init(repository: any ShooRepository, onJoined: @escaping () -> Void) {
        _model = State(initialValue: FamilyCodeModel(repository: repository))
        self.onJoined = onJoined
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                qr
                VStack(alignment: .leading, spacing: 6) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(17)
            .homeCard()
            if case .ready(let code) = model.codeState, model.inviteURL != nil {
                actions(code)
            }
        }
        .task { await model.run() }
        // Someone joined while the code was on screen: Home shows the family.
        .onChange(of: model.members.count) { _, count in
            if count > 0 { onJoined() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.invite")
    }

    @ViewBuilder
    private var qr: some View {
        Group {
            if let url = model.inviteURL, let image = QRCode.image(for: url.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(Text("QR code to join your family"))
                    .accessibilityIdentifier("familyCode.qr")
            } else {
                ProgressView().opacity(model.codeState == .loading ? 1 : 0)
            }
        }
        // Figma "QR": 110 pt, 6 pt padding, 14 pt corners, 1 pt inside stroke.
        .padding(6)
        .frame(width: 110, height: 110)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(HomeTheme.rowStroke, lineWidth: 1))
    }

    /// Figma "Aksi": 34 pt pills 8 apart, SF Pro Rounded 17 (140 %); Bagikan #186FB9, Salin #E6E8EC.
    private func actions(_ code: FamilyCode) -> some View {
        HStack(spacing: 8) {
            ShareLink(item: FamilyCodeModel.inviteText(for: code, language: language)) {
                Text("Share")
                    .onboardingFont(17, design: .rounded, relativeTo: .body)
                    .figmaLineHeight(23.8, relativeTo: .body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 5)
                    .frame(minHeight: 34)
                    .background(HomeTheme.action, in: Capsule())
                    // 34 pt pill; the touch area still reaches 44.
                    .contentShape(Rectangle().inset(by: -5))
            }
            .accessibilityIdentifier("family.invite")
            Button {
                if model.copyInvite(language: language) {
                    AccessibilityNotification.Announcement(L10n.string("Invite link copied", language: language)).post()
                }
            } label: {
                Text(model.copied ? "Copied" : "Copy")
                    .onboardingFont(17, design: .rounded, relativeTo: .body)
                    .figmaLineHeight(23.8, relativeTo: .body)
                    // Copy → Copied cross-fades while the pill eases to its new width (pattern: InviteSheet).
                    .contentTransition(.opacity)
                    .foregroundStyle(HomeTheme.bodyInk)
                    .padding(.horizontal, 16.5)
                    .padding(.vertical, 5)
                    .frame(minHeight: 34)
                    .background(HomeTheme.quietFill, in: Capsule())
                    .contentShape(Rectangle().inset(by: -5))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: model.copied) { _, now in now }
            .accessibilityIdentifier("familyCode.copy")
        }
        // On the row, so "Share" glides aside as the pill widens instead of jumping.
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3), value: model.copied)
    }

    @ViewBuilder
    private var content: some View {
        switch model.codeState {
        case .loading:
            Text("Getting a code")
                .onboardingFont(15, relativeTo: .subheadline)
                .foregroundStyle(HomeTheme.secondaryInk)
        case .ready(let code):
            // Figma "Label": SF Pro Rounded 13, -0.08, 18 pt lines, #6A717E.
            Text("Invite code · valid for \(model.timeLeft)")
                .onboardingFont(13, design: .rounded, tracking: -0.08, relativeTo: .footnote)
                .figmaLineHeight(18, glyphOffset: 1, relativeTo: .footnote)
                .monospacedDigit()
                .foregroundStyle(OnboardingTheme.bodyInk)
                .accessibilityIdentifier("familyCode.countdown")
            // Figma "Kode": SF Pro Display Bold 28, -2 %, 34 pt lines, #151617.
            Text(verbatim: FamilyCodeModel.display(code.code))
                .onboardingFont(28, weight: .bold, tracking: -0.56, relativeTo: .title)
                .figmaLineHeight(34, glyphOffset: -1, relativeTo: .title)
                .monospacedDigit()
                .foregroundStyle(HomeTheme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityLabel(Text("Code \(code.code.map(String.init).joined(separator: " "))"))
                .accessibilityIdentifier("familyCode.code")
        case .unavailable:
            Text("Couldn't get a code")
                .onboardingFont(15, weight: .medium, relativeTo: .subheadline)
                .foregroundStyle(HomeTheme.ink)
            Button { Task { await model.refreshCode() } } label: {
                Text("Try again")
                    .onboardingFont(14, weight: .medium, relativeTo: .subheadline)
                    .foregroundStyle(HomeTheme.action)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("familyCode.retry")
        case .full:
            Text("Your family is full (3 people). Remove someone to invite another person.")
                .onboardingFont(15, relativeTo: .subheadline)
                .foregroundStyle(HomeTheme.secondaryInk)
        }
    }
}

/// Figma "Cara Kerja" (1382:10511): the title, 14 pt, then three numbered steps in one card.
private struct HowItWorks: View {
    private let steps: [LocalizedStringKey] = [
        "Share the code or QR with your family",
        "They install Shoo and enter the code",
        "You hear about it when they open a dangerous site",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionTitle("How it works")
            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 {
                        Rectangle().fill(HomeTheme.stepDivider).frame(height: 1).accessibilityHidden(true)
                    }
                    HStack(spacing: 12) {
                        // Figma "Nomor": 28 pt #EEF4FB circle, SF Pro Rounded Semibold 13 #186FB9.
                        Text(verbatim: "\(index + 1)")
                            .onboardingFont(13, weight: .semibold, design: .rounded, tracking: -0.08, relativeTo: .footnote)
                            .foregroundStyle(HomeTheme.action)
                            .frame(width: 28, height: 28)
                            .background(HomeTheme.actionFill, in: Circle())
                            .accessibilityHidden(true)
                        // Figma: SF Pro Rounded 17, 140 % lines, #191D2F.
                        Text(step)
                            .onboardingFont(17, design: .rounded, relativeTo: .body)
                            .figmaLineHeight(23.8, relativeTo: .body)
                            .foregroundStyle(HomeTheme.navy)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 7)
            .homeCard()
            .accessibilityIdentifier("home.howItWorks")
        }
    }
}

#Preview("Personal") {
    NavigationStack {
        GuardianHomeView(
            repository: MockRepository(mode: .guardian, latency: .zero),
            settings: AppSettings(defaults: UserDefaults(suiteName: "preview.home")!),
            scope: .personal,
            extensionStatus: { .active(lastSeen: Date()) }
        )
    }
    .environment(AppEnvironment.preview())
}

#Preview("Family") {
    NavigationStack {
        GuardianHomeView(
            repository: MockRepository(mode: .guardian, latency: .zero),
            settings: AppSettings(defaults: UserDefaults(suiteName: "preview.home")!),
            scope: .family,
            extensionStatus: { .active(lastSeen: Date()) }
        )
    }
    .environment(AppEnvironment.preview())
}
