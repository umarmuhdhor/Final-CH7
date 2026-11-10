import SwiftUI

/// Protected Home (PR-04, Figma "protected/Home"): the blue hero with "Terhubung dengan …" under the headline, then on
/// the page the newest risky site of the last day with what the guardian decided, recent activity and the latest scams.
/// Frames: nothing today 1115:17162; blocked 1115:17294; warning 1363:12167; marked dangerous 1373:13100 / 1382:2227;
/// marked safe 1373:12376 / 1373:12752; no guardian yet 1382:2393 (the "Mode Terawasi" card instead of the pill).
struct ProtectedShieldView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var model: ShieldModel
    /// Bumped when Shoo turns on while the page is up (back from Settings): one success tap.
    @State private var turnedOn = 0
    /// The hero is scrolled out from under the status bar: the top scrim takes over as its backdrop.
    @State private var isHeroHidden = false

    init(repository: any ShooRepository, extensionStatus: @escaping () async -> ExtensionStatus) {
        _model = State(initialValue: ShieldModel(repository: repository, extensionStatus: extensionStatus))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }
    private var scrim: Color { colorScheme == .dark ? HomeTheme.navy : HomeTheme.background }
    private var isLoaded: Bool { model.state == .loaded }
    /// Loaded and nobody looks after this phone: no pill, the "Mode Terawasi" card (1382:2393).
    private var hasNoGuardian: Bool { isLoaded && model.guardian == nil }
    private var showsSupervisedCard: Bool { hasNoGuardian && !env.settings.supervisedCardDismissed }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    // Off ↔ on (back from Settings): the headline cross-fades and the shield eases over, not a jump.
                    // Not on the first load: the status is read before the page counts as loaded.
                    .animation(
                        isLoaded ? (reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35)) : nil,
                        value: model.extensionStatus.isActive
                    )
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .global).maxY < 140 } action: { isHeroHidden = $0 }
                // Figma "Status": the page itself rounds up over the hero; one 354 pt column, 24 from the edges.
                VStack(spacing: 0) {
                    content
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
                .background(HomeTheme.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            // Light only, like the Figma; scoped to the page so the bars keep their own scheme.
            .environment(\.colorScheme, .light)
        }
        // No navigation bar (see HomeTopBar): the page starts where the bar's bottom edge would be.
        .safeAreaPadding(.top, HomeTopBar.barHeight)
        .scrollIndicators(.hidden)
        .background(HomeTheme.background)
        .overlay(alignment: .top) {
            LinearGradient(colors: [scrim, scrim.opacity(0.85), scrim.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .ignoresSafeArea(edges: .top)
                .opacity(isHeroHidden ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: isHeroHidden)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        // Figma "Top Bar" 1115:17282: the profile circle only, right under the status bar.
        .overlay(alignment: .top) {
            HomeTopBar(name: model.profileName, onSwitch: nil) { env.router.openProfile() }
        }
        .toolbar(.hidden, for: .navigationBar)
        // App switcher snapshot on disk must not hold scam URLs or names (D-alief-A36).
        .privacyCover()
        .refreshable { await model.refresh() }
        // Coming back from Settings can flip Off → Active: say it (not on the first load).
        .onChange(of: model.extensionStatus.isActive) { _, isActive in
            guard model.state == .loaded else { return }
            if isActive { turnedOn += 1 }
            AccessibilityNotification.Announcement(
                L10n.string(isActive ? "You're protected!" : "You're not protected yet", language: language)
            ).post()
        }
        // Back from Connect (PR-01): show the new guardian.
        .onChange(of: env.router.isConnectPresented) { _, isPresented in
            guard !isPresented else { return }
            Task { await model.refresh() }
        }
        // Status comes from the App Group heartbeat: re-read whenever the app is back in front.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.refresh()
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
        // Only off → on, never the other way round.
        .sensoryFeedback(.success, trigger: turnedOn)
    }

    // MARK: Hero

    private var hero: some View {
        let isActive = model.extensionStatus.isActive
        let showsPill = isLoaded && model.guardian != nil
        var layout = HomeHeroLayout.personal
        // Figma "box": 349…469 with nothing today, 362…482 over the card; 1382:2393 (no pill) moves the gradient
        // up to y −31 and stretches the fade to 141 pt from 317.
        if hasNoGuardian {
            layout.backdrop = HeroBackdrop(imageTop: -31, boxTop: 317.08, boxHeight: 141)
        } else {
            layout.backdrop = HeroBackdrop(boxTop: model.cardScan == nil ? 349 : 362)
        }
        // The sheet starts at 403 under the pill (24.4 below it) and at 379 without one.
        let bottom: CGFloat = showsPill ? 24.38 : 379 - layout.titleBottom
        return HomeHero(
            style: .blue,
            title: isActive ? "You're protected!" : "You're not protected yet",
            titleIdentifier: isActive ? "shield.status.active" : "shield.status.off",
            shieldOn: isActive,
            layout: layout,
            bottomPadding: model.extensionStatus.nextStep != nil ? 20 : bottom
        ) {
            VStack(spacing: 8) {
                if model.extensionStatus.nextStep != nil {
                    Button { env.router.isTurnOnPresented = true } label: {
                        Text(isActive ? "Finish setup" : "Turn on now")
                            .onboardingFont(15, weight: .medium, relativeTo: .subheadline)
                            .underline()
                            .foregroundStyle(.white)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Shows how to switch Shoo on in Safari"))
                    .accessibilityIdentifier("shield.turnOn")
                }
                if showsPill, let guardian = model.guardian {
                    ConnectedPill(name: guardian.name)
                }
            }
            // Figma: the pill 12 under the headline's text box (13 here: SwiftUI's 28 pt box ends 1 pt higher).
            .padding(.top, model.extensionStatus.nextStep != nil ? 4 : (showsPill ? 13 : 0))
        }
    }

    // MARK: The page

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding(.top, 24)
                .accessibilityLabel(Text("Loading"))
        case .failed:
            VStack(spacing: 12) {
                Text("Couldn't load your Shield").font(.headline)
                Text("Check your connection and try again.").foregroundStyle(.primary)
                Button { Task { await model.retry() } } label: { Text("Try again").frame(minHeight: 44) }
                    .buttonStyle(.borderedProminent)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(16)
            .padding(.top, 24)
        case .loaded:
            loaded
        }
    }

    /// Figma's gaps per frame: the card 24 under the sheet's top; then 38 to "Aktivitas Terakhir" and 32 to the scams
    /// (1115:17294). Nothing today: the list 32 under the top, the scams 58 under it (1115:17162). No guardian: the
    /// "Mode Terawasi" card 29 under the site card, the list 16 under it, the scams 29 (1382:2393); without a site
    /// card it sits 31 under the top with 37 to the list and the scams, as on Pribadi (1382:10567).
    @ViewBuilder
    private var loaded: some View {
        let card = model.cardScan
        let cta = showsSupervisedCard
        let gaps: (top: CGFloat, list: CGFloat, scams: CGFloat) = switch (card != nil, cta) {
        case (true, true): (24, 16, 29)
        case (true, false): (24, 38, 32)
        case (false, true): (31, 37, 37)
        case (false, false): (32, 0, 58)
        }
        Color.clear.frame(height: gaps.top)
        if let card {
            ProtectedSiteCard(scan: card, guardian: model.guardian, language: language) {
                env.router.showDetail(scanId: card.id)
            }
            .padding(.bottom, cta ? 29 : gaps.list)
        }
        if cta {
            SupervisedModeCard(onConnect: { env.router.isConnectPresented = true }) {
                withAnimation(.easeOut(duration: 0.2)) { env.settings.supervisedCardDismissed = true }
            }
            .padding(.bottom, card == nil ? gaps.list : 16)
            .transition(.opacity)
        }
        RecentActivity(
            scans: model.recent,
            language: language,
            hasSitesAbove: card != nil,
            onOpen: { env.router.showDetail(scanId: $0.id) },
            onSeeAll: { env.router.selectedTab = .activity }
        )
        if !model.scamCases.isEmpty {
            LatestScamsCard(cases: model.scamCases)
                .padding(.top, gaps.scams)
        }
    }
}

// MARK: - Guardian

/// Figma "Card Perlindungan" (1373:13094): a 42.6 pt glass capsule, white 28 % with a 1 pt white 90 % ring;
/// a green 8.9 pt dot, 4 pt, "Terhubung dengan Virellia" in SF Pro Display 13 (-1 %, #1A1A1A); 17 pt sides.
private struct ConnectedPill: View {
    let name: String
    @Environment(\.shooReduceGlass) private var reduceGlass

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(HomeTheme.success)
                .frame(width: 8.88, height: 8.88)
                .accessibilityHidden(true)
            Text("Connected with \(name)")
                .onboardingFont(13, tracking: -0.13, relativeTo: .footnote)
                .foregroundStyle(HomeTheme.glassInk)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16.98)
        .padding(.vertical, 8)
        .frame(minHeight: 42.62)
        .background(.white.opacity(reduceGlass ? 1 : 0.28), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1.06))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("shield.guardian")
    }
}

// MARK: - The site card

/// Figma "Frame 1618872233" (1115:17294): #EDEDED 50 %, 20 pt corners, 354 wide. The site and when with a ↗ to the
/// details; the risk panel (red "Situs Berbahaya!" when blocked or marked dangerous, else orange "Situs
/// Mencurigakan!"); then who checks it: "Virellia akan mengecek kembali", or what they decided with a red ! or a
/// blue ✓ on their avatar. A warm or red glow at the foot; marked dangerous blushes the whole card.
private struct ProtectedSiteCard: View {
    let scan: ScanResult
    let guardian: GuardianInfo?
    let language: AppLanguage
    let onOpen: () -> Void
    @Environment(\.shooReduceMotion) private var reduceMotion

    private static let space = "protectedSiteCard"

    private var decision: Verdict.Value? { scan.verdict?.value }
    private var isDanger: Bool { decision == .notSafe || (decision == nil && scan.status == .blocked) }
    /// Who the line under the panel names: who decided, else the guardian who will.
    private var checker: String? { scan.verdict?.byName ?? guardian?.name }

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 0) {
                header
                HomeRiskPanel(scan: scan, isDanger: isDanger)
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                if let checker {
                    footer(checker)
                        .padding(.horizontal, 8)
                        .padding(.top, 12)
                }
            }
            .padding(.bottom, 13.79)
            .background { background }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .coordinateSpace(.named(Self.space))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The guardian's answer arrives while the card is up: badge, line and colour ease over instead of jumping.
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3), value: decision)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the details"))
        .accessibilityIdentifier("shield.lastBlocked")
    }

    /// Figma "Frame 1618872182": the 48 pt icon 17 / 14 in, the site (SF Pro Rounded 17, 22 pt line) and when (13,
    /// 18 pt) 3 under its top; "Status Badge" 40 pt white (its #FFCDCD ring is hidden), 20 from the top and 14 from
    /// the right.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            SiteIcon(url: scan.faviconUrl)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: scan.domain)
                    .onboardingFont(17, design: .rounded, tracking: -0.17, relativeTo: .body)
                    .figmaLineHeight(22, relativeTo: .body)
                    .foregroundStyle(HomeTheme.navy)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.vertical, 1)
                Text(verbatim: Formatters.dayAndTime(scan.detectedAt, language: language))
                    .onboardingFont(13, design: .rounded, tracking: -0.08, relativeTo: .footnote)
                    .figmaLineHeight(18, glyphOffset: 1, relativeTo: .footnote)
                    .foregroundStyle(HomeTheme.rowSubtitle)
            }
            .padding(.top, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            // SF Symbol arrow.up.right (U+100C3E) semibold 14.58, #1A1A1A.
            Image(systemName: "arrow.up.right")
                .font(.system(size: 14.58, weight: .semibold))
                .foregroundStyle(HomeTheme.glassInk)
                .frame(width: 40, height: 40)
                .background(.white, in: Circle())
                .overlay { if decision == .notSafe { Self.blush.clipShape(Circle()) } }
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .padding(.leading, 17)
        .padding(.trailing, 14)
        .padding(.top, 14)
    }

    /// Figma "Frame 1618872238": white 70 %, 20.9 pt corners, 16 / 17 padding; the 29.2 pt avatar, 6.3 pt, then
    /// the line in SF Pro Display 17 (#3A3D42), the name semibold.
    private func footer(_ name: String) -> some View {
        HStack(spacing: 6.26) {
            avatar(name)
            Group {
                switch decision {
                case nil: Text("\(Text(verbatim: name).fontWeight(.semibold)) will check it again")
                case .notSafe: Text("\(Text(verbatim: name).fontWeight(.semibold)) marked it dangerous")
                case .safe: Text("\(Text(verbatim: name).fontWeight(.semibold)) marked it safe")
                }
            }
            .onboardingFont(17, relativeTo: .body)
            .foregroundStyle(HomeTheme.bodyInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20.86, style: .continuous))
    }

    /// Figma "Avatar/S" with "Group 36523": a red ! (11.6 pt, #E5483B) or a blue ✓ (11 pt, #2E90FA) with a white ring,
    /// 18.3 / 19 from the avatar's corner.
    private func avatar(_ name: String) -> some View {
        InitialAvatar(name: name, size: 29.21, fontSize: 11.95)
            .overlay(alignment: .topLeading) {
                if let decision {
                    let size: CGFloat = decision == .notSafe ? 11.55 : 11
                    Image(systemName: decision == .notSafe ? "exclamationmark" : "checkmark")
                        .font(.system(size: decision == .notSafe ? 5.43 : 5.17, weight: .heavy, design: .rounded))
                        // Safe ↔ dangerous: the mark morphs (a cross-fade with Reduce Motion).
                        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                        .foregroundStyle(.white)
                        .frame(width: size, height: size)
                        .background(Color(hex: decision == .notSafe ? 0xE5483B : 0x2E90FA), in: Circle())
                        .background(Circle().fill(.white).padding(-0.96))
                        .offset(x: 18.31, y: 19)
                }
            }
            .padding(.trailing, decision == nil ? 0 : 0.65)
            .padding(.bottom, decision == nil ? 0 : (decision == .notSafe ? 1.34 : 0.79))
    }

    /// #EDEDED 50 % with Figma "Rectangle 9652": a red or warm glow from 63.5 pt above the foot (clear) to 14.5 under
    /// it (full), at 20 %; marked dangerous, the whole card blushes instead.
    private var background: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(hex: 0xEDEDED).opacity(0.5))
            .overlay {
                if decision == .notSafe {
                    Self.blush
                } else {
                    GeometryReader { proxy in
                        let height = proxy.size.height
                        let colors = isDanger ? [Color(hex: 0xF28D83).opacity(0), Color(hex: 0xF26153)]
                            : [Color(hex: 0xFB9E20).opacity(0), Color(hex: 0xFB9E20)]
                        LinearGradient(colors: colors, startPoint: UnitPoint(x: 0.5, y: (height - 63.5) / height),
                                       endPoint: UnitPoint(x: 0.5, y: (height + 14.5) / height))
                            .opacity(0.2)
                    }
                }
            }
    }

    /// Figma "Rectangle 9652" on the marked-dangerous frames (1373:13100): over the card and the badge, under the panel
    /// (measured: the panel is plain white 70 % over the blushed card); #F28D83 20 % at 4.6 pt to #F26153 at 173.6 pt from the card's top, all at 20 %.
    private static var blush: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(space))
            LinearGradient(colors: [Color(hex: 0xF28D83).opacity(0.2), Color(hex: 0xF26153)],
                           startPoint: UnitPoint(x: 0.5, y: (4.6 - frame.minY) / frame.height),
                           endPoint: UnitPoint(x: 0.5, y: (173.6 - frame.minY) / frame.height))
                .opacity(0.2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        ProtectedShieldView(repository: MockRepository(mode: .protected, latency: .zero), extensionStatus: { .active(lastSeen: Date()) })
    }
    .environment(AppEnvironment.preview(mode: .protected))
}
