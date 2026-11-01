import SwiftUI

/// Guardian Home, both sides of the ⇆ switch (GD-01/02/03, Figma HOME page).
/// `personal` (Family mode off, "Pribadi/Home" 435:20058): blue hero, security status, four tiles, own recent sites.
/// `family` ("Guardian/Home" 435:20373): teal hero, the people looked after, the site that waits for a verdict
/// (435:20899), the family's recent sites; nobody yet → the invite code and how it works (435:20630).
struct GuardianHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var model: GuardianHomeModel
    /// The hero is scrolled out from under the bar: the top scrim takes over as the dark backdrop.
    @State private var isHeroHidden = false

    init(
        repository: any ShooRepository,
        settings: AppSettings,
        scope: GuardianHomeModel.Scope,
        extensionStatus: @escaping () async -> ExtensionStatus
    ) {
        _model = State(initialValue: GuardianHomeModel(repository: repository, settings: settings, scope: scope, extensionStatus: extensionStatus))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }
    private var isFamily: Bool { model.scope == .family }
    /// Dark headline on the teal hero ("Keluarga Terlindungi!"), white everywhere else.
    private var hasDarkHero: Bool { isFamily && !model.hasNoFamily && model.pendingScan == nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .global).maxY < 140 } action: { isHeroHidden = $0 }
                VStack(spacing: 0) {
                    strip
                    sheet.homeSheet()
                }
                VStack(spacing: 24) {
                    below
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 32)
            }
            // Light only, like the Figma; scoped to the page so the bars keep their own scheme.
            .environment(\.colorScheme, .light)
        }
        .scrollIndicators(.hidden)
        .background(HomeTheme.background)
        // Switch and profile live in the (see-through) navigation bar.
        .toolbar {
            HomeSwitchToolbarItem(isFamilyShown: isFamily, action: switchSide)
            HomeProfileToolbarItem(name: model.profile?.name) { env.router.openProfile() }
        }
        // Once the hero is gone, a navy scrim keeps the white status bar readable over light content.
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
        .toolbarColorScheme(hasDarkHero && !isHeroHidden ? .light : .dark, for: .navigationBar)
        // App switcher snapshot on disk must not hold scam URLs or names (D-alief-A36).
        .privacyCover()
        .refreshable { await model.refresh() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.refresh()
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
        env.settings.familyModeOn = !isFamily
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
            HomeHero(
                style: .blue,
                title: isActive ? "You're protected!" : "You're not protected yet",
                titleIdentifier: isActive ? "home.status.active" : "home.status.off",
                shieldOn: isActive,
                bottomPadding: isActive ? 38 : 20
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
        } else if model.hasNoFamily {
            HomeHero(style: .blue, title: "Protect your loved ones", titleIdentifier: "home.family.empty",
                     subtitle: "No one to protect yet", shieldTint: .teal)
        } else if model.pendingScan != nil {
            HomeHero(style: .teal, title: "Family needs confirmation", titleIdentifier: "home.family.pending", shieldTint: .orange)
        } else {
            HomeHero(style: .teal, title: "Family protected!", titleColor: Color(red: 0x00 / 255, green: 0x38 / 255, blue: 0x3C / 255),
                     titleIdentifier: "home.family.protected", shieldTint: .teal)
        }
    }

    @ViewBuilder
    private var strip: some View {
        if !isFamily {
            StatusStrip(title: "Security status:", value: model.extensionStatus.isActive ? "Good!" : "Danger!", fill: StatusStrip.personal)
        } else if model.hasNoFamily {
            StatusStrip(title: "Family status:", value: "No members yet", fill: HomeTheme.navy)
        } else {
            StatusStrip(title: "Family status:", value: model.pendingScan != nil ? "needs confirmation" : "All safe!", fill: StatusStrip.family)
        }
    }

    // MARK: Sheet

    @ViewBuilder
    private var sheet: some View {
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
            .padding(16)
        case .loaded:
            if !isFamily {
                StatsGrid(stats: model.stats)
            } else if model.hasNoFamily {
                InviteCodeCard(repository: env.repository) { Task { await model.refresh() } }
                    .padding(24)
            } else if let scan = model.pendingScan {
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
                MembersRow(members: model.shownMembers) { env.router.show(.member(deviceId: $0.deviceId)) }
            }
        }
    }

    @ViewBuilder
    private var below: some View {
        if model.state == .loaded {
            if model.hasNoFamily {
                HowItWorks()
            } else {
                RecentActivity(
                    scans: model.recent,
                    language: language,
                    showsOwner: isFamily,
                    onOpen: { env.router.showDetail(scanId: $0.id) },
                    onSeeAll: { env.router.selectedTab = .activity }
                )
            }
        }
    }
}

// MARK: - Personal: four tiles

private struct StatsGrid: View {
    let stats: GuardianHomeModel.Stats
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)]
        LazyVGrid(columns: columns, spacing: 0) {
            StatTile(systemImage: "network.badge.shield.half.filled", value: stats.blocked, title: "Threats blocked")
            StatTile(systemImage: "lock.open.fill", value: stats.warnings, title: "Security risks")
            StatTile(systemImage: "hand.raised.fill", value: stats.suspiciousHosts, title: "Suspicious hosts")
            StatTile(systemImage: "tray.full.fill", value: stats.recentScans, title: "Recent scans")
        }
        .overlay {
            if !dynamicTypeSize.isAccessibilitySize {
                // Figma dividers: a vertical and a horizontal hairline that fade at the ends.
                ZStack {
                    LinearGradient(colors: [HomeTheme.divider, HomeTheme.divider.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(width: 1)
                    FadingDivider()
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
                .accessibilityHidden(true)
            }
        }
        .padding(8)
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

// MARK: - Family: the people looked after

/// Figma "Frame 1618872221": up to three people side by side, a dot for whether Shoo is on for them.
private struct MembersRow: View {
    let members: [FamilyMember]
    let onOpen: (FamilyMember) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                if index > 0 {
                    FadingDivider(axis: dynamicTypeSize.isAccessibilitySize ? .horizontal : .vertical)
                        .padding(.vertical, 8)
                }
                Button { onOpen(member) } label: {
                    MemberCell(member: member, gradient: InitialAvatar.gradient(at: index))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("family.member.\(member.deviceId)")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("family.header")
    }
}

private struct MemberCell: View {
    let member: FamilyMember
    let gradient: [Color]

    var body: some View {
        VStack(spacing: 8) {
            InitialAvatar(name: member.name, size: 44, gradient: gradient, fontSize: 18)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(member.isConnected ? HomeTheme.success : HomeTheme.offline)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 1))
                        .offset(x: 2, y: 2)
                }
            VStack(spacing: 2) {
                Text(verbatim: member.name)
                    .onboardingFont(17, weight: .medium, relativeTo: .headline)
                    .tracking(-0.17)
                    .foregroundStyle(HomeTheme.ink)
                    .lineLimit(1)
                Text(member.isConnected ? "Active" : "Not connected")
                    .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                    .foregroundStyle(HomeTheme.secondaryInk)
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

/// Figma "Kartu Situs" (435:21036): who opened it and when, the site, the risk gauge, the reason in plain words,
/// then Bahaya / Aman under the card.
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

    private var title: String { scan.pageTitle?.isEmpty == false ? scan.pageTitle! : scan.domain }
    private var reason: String? {
        Evidence.top(scan.signals, mode: .guardian, language: language, limit: 1).first?.text
    }
    private var eyebrow: String {
        let opened = L10n.string("Opened by \(scan.ownerName)", language: language)
        return "\(opened) · \(Formatters.dateTime(scan.detectedAt, language: language))".uppercased(with: language.locale)
    }

    private var titleText: some View {
        Text(verbatim: title)
            .onboardingFont(17, weight: .semibold, relativeTo: .headline)
            .foregroundStyle(HomeTheme.bodyInk)
    }

    private var domainChip: some View {
        Text(verbatim: scan.domain)
            .onboardingFont(13, relativeTo: .footnote)
            .foregroundStyle(HomeTheme.bodyInk)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color(red: 0xE4 / 255, green: 0xE9 / 255, blue: 0xED / 255), in: Capsule())
    }

    var body: some View {
        VStack(spacing: 16) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: eyebrow)
                            .onboardingFont(11, relativeTo: .caption)
                            .tracking(1.3)
                            .foregroundStyle(Color(red: 0x6B / 255, green: 0x70 / 255, blue: 0x78 / 255))
                        // Title and site side by side when both fit; otherwise the site goes under the title.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                titleText.fixedSize()
                                domainChip
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                titleText.lineLimit(2)
                                domainChip
                            }
                        }
                    }
                    .padding(.trailing, 44)
                    .padding(.horizontal, 16)
                    FittedScoreGauge(scan: scan)
                        .frame(maxWidth: .infinity)
                    if let reason {
                        Text(verbatim: reason)
                            .onboardingFont(15, relativeTo: .subheadline)
                            .lineSpacing(7)
                            .foregroundStyle(HomeTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 24)
                .padding(.horizontal, 8)
                .background(
                    LinearGradient(colors: [Color(red: 0xFE / 255, green: 0xFE / 255, blue: 1), Color(red: 0xF9 / 255, green: 0xFA / 255, blue: 0xFC / 255)],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 32, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(.white, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Opens the details"))
            .accessibilityIdentifier("home.pending")
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HomeTheme.bodyInk)
                        .frame(width: 32, height: 32)
                        .background(HomeTheme.tileIconBackground, in: Circle())
                        .overlay(Circle().stroke(HomeTheme.rowStroke, lineWidth: 0.86))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                .padding(.trailing, 18)
                .accessibilityLabel(Text("Close"))
                .accessibilityHint(Text("Hides this site from Home"))
                .accessibilityIdentifier("home.pending.close")
            }

            if canDecide {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    DecisionButton(title: "Danger", systemImage: "exclamationmark.circle.fill", color: HomeTheme.dangerButton) { onDecide(.notSafe) }
                        .accessibilityIdentifier("home.verdict.notSafe")
                    DecisionButton(title: "Safe", systemImage: "checkmark.circle.fill", color: HomeTheme.navy) { onDecide(.safe) }
                        .accessibilityIdentifier("home.verdict.safe")
                }
                .padding(.horizontal, 16)
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
        .padding(8)
        .padding(.bottom, 16)
    }
}

/// Figma "Button" Red / Secondary: white capsule, 1 pt ring and a small shadow.
private struct DecisionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { Image(systemName: systemImage) }
                .onboardingFont(17, weight: .semibold, relativeTo: .headline)
                .tracking(-0.2)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(.white, in: Capsule())
                .overlay(Capsule().stroke(Color(red: 0xE3 / 255, green: 0xE3 / 255, blue: 0xE3 / 255), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 2.5, y: 3)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Applies right away. You can change it later."))
    }
}

// MARK: - Family: nobody yet

/// Figma "Kode Undangan" (435:20669): QR, the code with how long it lasts, Bagikan / Salin (GD-04).
private struct InviteCodeCard: View {
    let onJoined: () -> Void
    @Environment(\.locale) private var locale
    @State private var model: FamilyCodeModel

    init(repository: any ShooRepository, onJoined: @escaping () -> Void) {
        _model = State(initialValue: FamilyCodeModel(repository: repository))
        self.onJoined = onJoined
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            qr
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(17)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .figmaCardShadow()
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
        .padding(7)
        .frame(width: 110, height: 110)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HomeTheme.rowStroke, lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        switch model.codeState {
        case .loading:
            Text("Getting a code")
                .onboardingFont(15, relativeTo: .subheadline)
                .foregroundStyle(HomeTheme.secondaryInk)
        case .ready(let code):
            Text("Invite code · valid for \(model.timeLeft)")
                .onboardingFont(13, relativeTo: .footnote)
                .monospacedDigit()
                .foregroundStyle(HomeTheme.secondaryInk)
                .accessibilityIdentifier("familyCode.countdown")
            Text(verbatim: FamilyCodeModel.display(code.code))
                .font(.system(size: 30, weight: .semibold, design: .default))
                .tracking(3)
                .monospacedDigit()
                .foregroundStyle(HomeTheme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityLabel(Text("Code \(code.code.map(String.init).joined(separator: " "))"))
                .accessibilityIdentifier("familyCode.code")
            if model.inviteURL != nil {
                HStack(spacing: 8) {
                    ShareLink(item: FamilyCodeModel.inviteText(for: code, language: language)) {
                        Text("Share")
                            .onboardingFont(14, weight: .medium, relativeTo: .subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .frame(minHeight: 34)
                            .background(HomeTheme.action, in: Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Capsule())
                    }
                    .accessibilityIdentifier("family.invite")
                    Button {
                        if model.copyInvite(language: language) {
                            AccessibilityNotification.Announcement(L10n.string("Invite link copied", language: language)).post()
                        }
                    } label: {
                        Text(model.copied ? "Copied" : "Copy")
                            .onboardingFont(14, weight: .medium, relativeTo: .subheadline)
                            .foregroundStyle(HomeTheme.bodyInk)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 34)
                            .background(HomeTheme.quietFill, in: Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("familyCode.copy")
                }
            }
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

/// Figma "Cara Kerja" (435:20681): three numbered steps in one card.
private struct HowItWorks: View {
    private let steps: [LocalizedStringKey] = [
        "Share the code or QR with your family",
        "They install Shoo and enter the code",
        "You hear about it when they open a dangerous site",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeSectionTitle("How it works")
            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 {
                        Rectangle().fill(HomeTheme.divider).frame(height: 1).accessibilityHidden(true)
                    }
                    HStack(spacing: 12) {
                        Text(verbatim: "\(index + 1)")
                            .onboardingFont(13, weight: .semibold, relativeTo: .footnote)
                            .foregroundStyle(HomeTheme.action)
                            .frame(width: 28, height: 28)
                            .background(HomeTheme.actionFill, in: Circle())
                            .accessibilityHidden(true)
                        Text(step)
                            .onboardingFont(15, relativeTo: .subheadline)
                            .tracking(-0.15)
                            .lineSpacing(5)
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
