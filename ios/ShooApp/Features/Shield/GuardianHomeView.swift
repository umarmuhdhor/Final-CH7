import SwiftUI

/// Guardian Home, both sides of the ⇆ switch (GD-01/02/03, Figma HOME page).
/// `personal` (Family mode off, "Pribadi/Home" 957:10924, Waspada 955:10369, Bahaya 955:10467): the hero says how
/// the last day went, then own recent sites and the latest scams.
/// `family` ("Guardian/Home" 435:20373): teal hero, the people looked after, the site that waits for a verdict
/// (957:11002, Bahaya 955:10565), the family's recent sites; nobody yet → the invite code and how it works (435:20630).
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
                if isFamily {
                    VStack(spacing: 0) {
                        strip
                        sheet.homeSheet()
                    }
                    VStack(spacing: 24) {
                        below
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
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
            // Shoo being off outranks what it saw while it was on.
            let level = isActive ? model.level : .normal
            HomeHero(
                style: level.heroStyle,
                title: isActive ? level.title : "You're not protected yet",
                titleIdentifier: isActive ? level.titleIdentifier : "home.status.off",
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
        } else if model.hasNoFamily {
            HomeHero(style: .empty, title: "Protect your loved ones", titleIdentifier: "home.family.empty",
                     subtitle: "No one to protect yet", shieldTint: .teal, layout: .familyEmpty)
        } else if model.pendingScan != nil {
            let isDanger = model.level == .danger
            HomeHero(style: isDanger ? .crimson : .teal, title: isDanger ? "Family in danger" : "Family needs confirmation",
                     titleIdentifier: "home.family.pending", shieldTint: isDanger ? .crimson : .orange, layout: .familyPending)
        } else {
            HomeHero(style: .teal, title: "Family protected!", titleColor: Color(red: 0x00 / 255, green: 0x38 / 255, blue: 0x3C / 255),
                     titleIdentifier: "home.family.protected", shieldTint: .teal, layout: .family)
        }
    }

    @ViewBuilder
    private var strip: some View {
        if model.hasNoFamily {
            StatusStrip(title: "Family status:", value: "No members yet", fill: HomeTheme.navy, valueColor: StatusStrip.mutedValue)
        } else if model.level == .danger {
            StatusStrip(title: "Family status:", value: "in danger", fill: StatusStrip.danger)
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
                VStack(spacing: 24) {
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
            } else if model.hasNoFamily {
                // Figma "Konten" 435:20630: the card 16 under the sheet's top, 24 from its sides, 20 above its bottom.
                InviteCodeCard(repository: env.repository) { Task { await model.refresh() } }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
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
                    showsOwner: true,
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
                        // Figma Line 13 / 14: 100 pt, solid for the top half, fading out below, 7 pt under the row top;
                        // 16 pt either side.
                        LinearGradient(stops: [.init(color: HomeTheme.divider, location: 0), .init(color: HomeTheme.divider, location: 0.5),
                                               .init(color: HomeTheme.divider.opacity(0), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(width: 1, height: 100)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, 7)
                            .padding(.horizontal, 16)
                            .accessibilityHidden(true)
                    }
                }
                Button { onOpen(member) } label: {
                    MemberCell(member: member, gradient: InitialAvatar.gradient(at: index))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("family.member.\(member.deviceId)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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
                    // Figma: 12 pt dot, 1 pt white ring outside, flush with the avatar's bottom right.
                    Circle()
                        .fill(member.isConnected ? HomeTheme.success : HomeTheme.offline)
                        .frame(width: 12, height: 12)
                        .background(Circle().fill(.white).padding(-1))
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

/// Figma "Kartu Situs" (957:11077): who opened what, the site and when, the risk gauge, the reason in plain words,
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
    private var domainChip: some View {
        // Figma "Tag": 11 pt rounded, 9 × 3 padding, #E6E8EC, 1 pt stroke.
        Text(verbatim: scan.domain)
            .onboardingFont(11, design: .rounded, relativeTo: .caption)
            .tracking(0.06)
            .foregroundStyle(HomeTheme.bodyInk)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(HomeTheme.quietFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color(red: 0xDC / 255, green: 0xDF / 255, blue: 0xE4 / 255), lineWidth: 1))
    }

    var body: some View {
        // Figma "Konten" (435:20899): the card 5 pt under the sheet's top, 8 from its sides; the buttons 12 under it.
        VStack(spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Figma: "Syahnaz" semibold, the rest regular, "Title 3".
                        (Text(verbatim: scan.ownerName).fontWeight(.semibold) + Text(verbatim: " ") + Text("opened \(title)"))
                            .onboardingFont(20, relativeTo: .title3)
                            .tracking(-0.45)
                            .foregroundStyle(HomeTheme.navy)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            domainChip
                            Text(verbatim: Formatters.dayAndTime(scan.detectedAt, language: language, compact: true))
                                .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                                .tracking(-0.08)
                                .foregroundStyle(HomeTheme.secondaryInk)
                                .fixedSize()
                        }
                    }
                    .padding(.trailing, 44)
                    .padding(.horizontal, 16)
                    // Figma: the gauge (370 × 237) right under the header, the reason 8 under it, 150 % lines.
                    FittedScoreGauge(scan: scan, reservesBlockedHeight: true)
                        .frame(maxWidth: .infinity)
                    if let reason {
                        Text(verbatim: reason)
                            .onboardingFont(17, design: .rounded, relativeTo: .subheadline)
                            .lineSpacing(3.5)
                            .foregroundStyle(HomeTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
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
                        .font(.system(size: 14.4, weight: .semibold))
                        .foregroundStyle(HomeTheme.bodyInk)
                        .frame(width: 32, height: 32)
                        .background(HomeTheme.tileIconBackground, in: Circle())
                        .overlay(Circle().stroke(HomeTheme.rowStroke, lineWidth: 0.86))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                // Figma: the 32 pt circle 24 pt in from the card's top and right.
                .padding(.top, 18)
                .padding(.trailing, 18)
                .accessibilityLabel(Text("Close"))
                .accessibilityHint(Text("Hides this site from Home"))
                .accessibilityIdentifier("home.pending.close")
            }

            if canDecide {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    DecisionButton(title: "Danger", systemImage: "exclamationmark.circle.fill", colors: DecisionButton.danger) { onDecide(.notSafe) }
                        .accessibilityIdentifier("home.verdict.notSafe")
                    DecisionButton(title: "Safe", systemImage: "checkmark.circle.fill", colors: DecisionButton.safe) { onDecide(.safe) }
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
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, 20)
    }
}

/// Figma "Button" (957:11090, 957:11091): a filled gradient capsule, 1 pt ring and a small shadow.
private struct DecisionButton: View {
    static let danger = [Color(red: 0xF6 / 255, green: 0x47 / 255, blue: 0x47 / 255), Color(red: 0xBB / 255, green: 0x16 / 255, blue: 0x16 / 255)]
    static let safe = [Color(red: 0x2F / 255, green: 0x84 / 255, blue: 0xCC / 255), HomeTheme.action]

    let title: LocalizedStringKey
    let systemImage: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { Image(systemName: systemImage) }
                .onboardingFont(17, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom), in: Capsule())
                .overlay(Capsule().stroke(Color(red: 0xE3 / 255, green: 0xE3 / 255, blue: 0xE3 / 255), lineWidth: 1))
                .figmaButtonShadow()
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
        // Figma "QR": 110 pt, 6 pt padding, 14 pt corners, 1 pt inside stroke.
        .padding(6)
        .frame(width: 110, height: 110)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(HomeTheme.rowStroke, lineWidth: 1))
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
                .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                .monospacedDigit()
                // Figma: a 20 pt line (153.8 %).
                .padding(.vertical, 2.25)
                .foregroundStyle(HomeTheme.secondaryInk)
                .accessibilityIdentifier("familyCode.countdown")
            Text(verbatim: FamilyCodeModel.display(code.code))
                .font(FigmaFont.font(size: 30, weight: .semibold))
                .tracking(1.2)
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
                            .tracking(-0.14)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .frame(minHeight: 34)
                            .background(HomeTheme.action, in: Capsule())
                            // 34 pt pill (Figma "Aksi"); the touch area still reaches 44.
                            .contentShape(Rectangle().inset(by: -5))
                    }
                    .accessibilityIdentifier("family.invite")
                    Button {
                        if model.copyInvite(language: language) {
                            AccessibilityNotification.Announcement(L10n.string("Invite link copied", language: language)).post()
                        }
                    } label: {
                        Text(model.copied ? "Copied" : "Copy")
                            .onboardingFont(14, weight: .medium, relativeTo: .subheadline)
                            .tracking(-0.14)
                            .foregroundStyle(HomeTheme.bodyInk)
                            .padding(.horizontal, 19.5)
                            .frame(minHeight: 34)
                            .background(HomeTheme.quietFill, in: Capsule())
                            .contentShape(Rectangle().inset(by: -5))
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
                        Rectangle().fill(HomeTheme.stepDivider).frame(height: 1).accessibilityHidden(true)
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
                            // Figma: 135 % line height.
                            .lineSpacing(2.35)
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
