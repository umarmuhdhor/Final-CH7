import SwiftUI

/// Protected Home (PR-04, Figma "protected/Home" 441:3063 / 441:3800): blue hero with the shield, who looks
/// after me, the site blocked in the last 24 h with its gauge, Diblokir / Waspada counts, and recent activity.
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
                // Figma 441:3800: one 26 pt column, 21 pt from the screen edges.
                VStack(spacing: 26) {
                    content
                }
                .padding(.horizontal, 21)
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
        // Figma protected/Home keeps only the shield's glow; Off still shows the dimmed shield.
        var layout = HomeHeroLayout.personal
        layout.showsShield = !isActive
        // The background's fade ends where the next card starts (Figma y 443).
        layout.backgroundOverhang = 0
        return HomeHero(
            style: .blue,
            title: isActive ? "You're protected!" : "You're not protected yet",
            titleIdentifier: isActive ? "shield.status.active" : "shield.status.off",
            shieldOn: isActive,
            layout: layout,
            bottomPadding: 26
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
                        .padding(.horizontal, 21)
                }
            }
            // Figma: the card 32 under the headline's text box.
            .padding(.top, model.extensionStatus.nextStep != nil ? 4 : 31.7)
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
            }
            CountTiles(counts: model.counts, guardianName: model.guardian?.name)
            RecentActivity(
                scans: model.recent,
                language: language,
                seeAllStyle: .trailingLink,
                onOpen: { env.router.showDetail(scanId: $0.id) },
                onSeeAll: { env.router.selectedTab = .activity }
            )
            // Figma: 356 wide at x 23, 2 in from the cards above.
            .padding(.horizontal, 2)
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
                    InitialAvatar(name: guardian.name, size: 33, fontSize: 13.5)
                    Text("Connected with \(guardian.name)")
                        .onboardingFont(17, relativeTo: .body)
                        .tracking(-0.17)
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
        .frame(minHeight: 65)
        .homeCard()
        .accessibilityIdentifier("shield.guardian")
    }
}

// MARK: - Blocked card

/// Figma 441:4059: the site, ↗ to Detail, a "Diblokir" chip over the gauge, and the guardian's note.
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: scan.domain)
                            .onboardingFont(17, relativeTo: .body)
                            .tracking(-0.17)
                            .foregroundStyle(HomeTheme.navy)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text(verbatim: Formatters.dayAndTime(scan.detectedAt, language: language))
                            .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                            .foregroundStyle(HomeTheme.rowSubtitle)
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Figma "Status Badge": 40 pt white circle, 20 pt in from the card's top and right.
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 22.3))
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
                            (Text(verbatim: guardian.name).fontWeight(.bold) + Text(verbatim: " ") + Text("will check it again"))
                                .onboardingFont(11.5, relativeTo: .caption)
                            // One line as in Figma. With the SF Pro Display widths it fits in Figma's copy ("anda");
                            // the id copy's "Anda" is ~1 pt too wide, so it may still shrink a hair.
                            Text("but you still shouldn't open this link")
                                .onboardingFont(11.5, relativeTo: .caption)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                .minimumScaleFactor(0.85)
                        }
                        .tracking(-0.115)
                        .foregroundStyle(HomeTheme.bodyInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16.7)
                    .padding(.vertical, 15.6)
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

// MARK: - Counts

/// Figma 441:4021: "4 Diblokir" and "7 Waspada", each with how many the guardian verified.
private struct CountTiles: View {
    let counts: ShieldModel.Counts
    let guardianName: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 18.4))
        layout {
            CountTile(value: counts.blocked, title: "Blocked", color: HomeTheme.tileIcon,
                      verified: counts.blockedVerified, guardianName: guardianName)
            CountTile(value: counts.warnings, title: "Caution", color: HomeTheme.warningNumber,
                      verified: counts.warningsVerified, guardianName: guardianName)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shield.stats")
    }
}

private struct CountTile: View {
    let value: Int
    let title: LocalizedStringKey
    let color: Color
    let verified: Int
    let guardianName: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Figma 441:4021: 27.7 bold number, 15.7 label, the verified line 7.7 under it.
        VStack(alignment: .leading, spacing: -3.4) {
            Text(verbatim: "\(value)")
                .onboardingFont(27.7, weight: .bold, relativeTo: .title)
                .monospacedDigit()
                .foregroundStyle(color)
            Text(title)
                .onboardingFont(15.7, relativeTo: .callout)
                .foregroundStyle(.black)
            if let guardianName {
                Label {
                    // Figma sets this at 9.2 pt; 11 is the smallest legible size, shrunk only to stay on one line.
                    Text("\(verified) verified by \(guardianName)")
                        .onboardingFont(11, relativeTo: .caption2)
                        .foregroundStyle(HomeTheme.successText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .minimumScaleFactor(0.84)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(HomeTheme.success)
                }
                .labelStyle(TightLabelStyle())
                .padding(.top, 11.1)
            }
        }
        .padding(.leading, 15.7)
        .padding(.trailing, 8)
        .padding(.vertical, 15.6)
        .frame(maxWidth: .infinity, minHeight: 97.7, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 23.6, style: .continuous))
        // Figma: #000 25 %, y 4.7, blur 9.2, spread −3.5: an inset shape casts it (no spread in SwiftUI).
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
                .padding(3.5)
                .shadow(color: .black.opacity(0.25), radius: 4.6, y: 4.7)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3.7) {
            configuration.icon
            configuration.title
        }
    }
}

#Preview {
    NavigationStack {
        ProtectedShieldView(repository: MockRepository(mode: .protected, latency: .zero), extensionStatus: { .active(lastSeen: Date()) })
    }
    .environment(AppEnvironment.preview(mode: .protected))
}
