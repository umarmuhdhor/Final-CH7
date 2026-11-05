import SwiftUI

/// Protected Home (PR-04, Figma "protected/Home" 957:11102 / 957:11377): blue hero with the shield, who looks
/// after me, the site blocked in the last 24 h with its gauge, recent activity and the latest scams.
struct ProtectedShieldView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var model: ShieldModel
    /// The hero is scrolled out from under the bar: the top scrim takes over as the dark backdrop.
    @State private var isHeroHidden = false

    init(repository: any ShooRepository, extensionStatus: @escaping () async -> ExtensionStatus) {
        _model = State(initialValue: ShieldModel(repository: repository, extensionStatus: extensionStatus))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .global).maxY < 140 } action: { isHeroHidden = $0 }
                // Figma 957:11102: one 24 pt column, 24 pt from the screen edges.
                VStack(spacing: 24) {
                    content
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            // Light only, like the Figma; scoped to the page so the bars keep their own scheme.
            .environment(\.colorScheme, .light)
        }
        .scrollIndicators(.hidden)
        .background(HomeTheme.background)
        .toolbar {
            HomeProfileToolbarItem(name: model.profileName) { env.router.openProfile() }
        }
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
        // Coming back from Settings can flip Off → Active: say it (not on the first load).
        .onChange(of: model.extensionStatus.isActive) { _, isActive in
            guard model.state == .loaded else { return }
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
    }

    // MARK: Hero

    private var hero: some View {
        let isActive = model.extensionStatus.isActive
        var layout = HomeHeroLayout.personal
        // The background's fade ends where the next card starts (Figma y 443).
        layout.backgroundOverhang = 0
        return HomeHero(
            style: .blue,
            title: isActive ? "You're protected!" : "You're not protected yet",
            titleIdentifier: isActive ? "shield.status.active" : "shield.status.off",
            shieldOn: isActive,
            layout: layout,
            bottomPadding: 24
        ) {
            VStack(spacing: 16) {
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
                if model.state == .loaded {
                    GuardianPill(guardian: model.guardian) { env.router.isConnectPresented = true }
                        .padding(.horizontal, 13)
                }
            }
            // Figma: the card 30 under the headline's text box.
            .padding(.top, model.extensionStatus.nextStep != nil ? 4 : 30)
        }
    }

    // MARK: Below the hero

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
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
        case .loaded:
            if let scan = model.recentBlocked {
                BlockedCard(scan: scan, guardian: model.guardian, language: language) {
                    env.router.showDetail(scanId: scan.id)
                }
                // Figma 957:11377: 360 wide, 26 from what is above and below.
                .padding(.horizontal, -3)
                .padding(.vertical, 2)
            }
            RecentActivity(
                scans: model.recent,
                language: language,
                onOpen: { env.router.showDetail(scanId: $0.id) },
                onSeeAll: { env.router.selectedTab = .activity }
            )
            if !model.scamCases.isEmpty {
                LatestScamsCard(cases: model.scamCases)
            }
        }
    }
}

// MARK: - Guardian

/// Figma "Card Perlindungan": "Terhubung dengan Virellia"; no guardian → a way to connect (PR-01).
private struct GuardianPill: View {
    let guardian: GuardianInfo?
    let onConnect: () -> Void

    var body: some View {
        Group {
            if let guardian {
                HStack(spacing: 12) {
                    InitialAvatar(name: guardian.name, size: 35, fontSize: 14.3)
                    Text("Connected with \(guardian.name)")
                        .onboardingFont(18, relativeTo: .body)
                        .tracking(-0.18)
                        .foregroundStyle(HomeTheme.navy)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            } else {
                Button(action: onConnect) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 22))
                            .foregroundStyle(HomeTheme.action)
                            .frame(width: 33, height: 33)
                            .accessibilityHidden(true)
                        Text("Connect to your guardian")
                            .onboardingFont(17, weight: .medium, relativeTo: .body)
                            .foregroundStyle(HomeTheme.action)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(HomeTheme.secondaryInk)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shield.connect")
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .frame(minHeight: 69)
        .homeCard(cornerRadius: 21)
        .accessibilityIdentifier("shield.guardian")
    }
}

// MARK: - Blocked card

/// Figma 957:11415: the site, ↗ to Detail, a "Diblokir" chip over the gauge, and the guardian's note.
private struct BlockedCard: View {
    let scan: ScanResult
    let guardian: GuardianInfo?
    let language: AppLanguage
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    SiteIcon(url: scan.faviconUrl)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: scan.domain)
                            .onboardingFont(20, relativeTo: .title3)
                            .tracking(-0.45)
                            .foregroundStyle(HomeTheme.navy)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text(verbatim: Formatters.dayAndTime(scan.detectedAt, language: language))
                            .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                            .tracking(-0.08)
                            .foregroundStyle(HomeTheme.rowSubtitle)
                    }
                    .padding(.top, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Figma "Status Badge": 40 pt white circle, 20 pt in from the card's top and right.
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14.6, weight: .semibold))
                        .foregroundStyle(Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255))
                        .frame(width: 40, height: 40)
                        .background(.white, in: Circle())
                        .padding(.top, 6)
                        .padding(.trailing, 3)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 5)

                // Figma "Frame 1618872237": 338 × 226, the chip then the 242 pt gauge; the frame trims the
                // gauge's empty bottom 4.6 pt.
                VStack(spacing: 0) {
                    HomeStatusChip(badge: .blocked, large: true)
                    FittedScoreGauge(scan: scan, maxWidth: 242)
                }
                .padding(.top, 18.3)
                .padding(.bottom, 13.7)
                .padding(.horizontal, 29.8)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 22.9, style: .continuous))

                if let guardian, scan.verdict == nil {
                    // Figma "Frame 1618872238": two lines, the guardian's name bold on the first.
                    HStack(spacing: 6.3) {
                        InitialAvatar(name: guardian.name, size: 29.2, fontSize: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            (Text(verbatim: guardian.name).fontWeight(.semibold) + Text(verbatim: " ") + Text("will check this link"))
                                .onboardingFont(15, relativeTo: .subheadline)
                                .foregroundStyle(HomeTheme.navy)
                            Text("Don't open it for now")
                                .onboardingFont(17, design: .rounded, relativeTo: .subheadline)
                                .foregroundStyle(HomeTheme.secondaryInk)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16.7)
                    .padding(.vertical, 16)
                    .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20.9, style: .continuous))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 14.5)
            .background {
                // Glass grey card that blushes red towards the bottom (Figma "Rectangle 9652").
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(red: 0xED / 255, green: 0xED / 255, blue: 0xED / 255).opacity(0.5))
                    .overlay(
                        LinearGradient(colors: [Color(red: 0xF2 / 255, green: 0x8D / 255, blue: 0x83 / 255).opacity(0),
                                                Color(red: 0xF2 / 255, green: 0x61 / 255, blue: 0x53 / 255).opacity(0.2)],
                                       startPoint: .init(x: 0.5, y: 0.79), endPoint: .init(x: 0.5, y: 0.99))
                            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the details"))
        .accessibilityIdentifier("shield.lastBlocked")
    }
}

#Preview {
    NavigationStack {
        ProtectedShieldView(repository: MockRepository(mode: .protected, latency: .zero), extensionStatus: { .active(lastSeen: Date()) })
    }
    .environment(AppEnvironment.preview(mode: .protected))
}
