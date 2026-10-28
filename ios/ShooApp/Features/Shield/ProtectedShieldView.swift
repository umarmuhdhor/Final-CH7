import SwiftUI

/// Whose own Shield this is: the protected parent (PR-04) or the guardian with Family mode off (GD-01).
enum ShieldPerspective {
    case protected
    case guardian

    func statusTitle(isActive: Bool) -> String.LocalizationValue {
        switch self {
        case .protected: isActive ? "Protection is on" : "Protection is off"
        case .guardian: isActive ? "You're protected" : "You're not protected"
        }
    }
}

/// Own Shield: is protection on, who looks after me (Protected only), what was blocked last.
struct ProtectedShieldView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var model: ShieldModel
    let perspective: ShieldPerspective

    init(
        repository: any ShooRepository,
        extensionStatus: @escaping () async -> ExtensionStatus,
        perspective: ShieldPerspective = .protected
    ) {
        _model = State(initialValue: ShieldModel(repository: repository, extensionStatus: extensionStatus))
        self.perspective = perspective
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ExtensionStatusCard(status: model.extensionStatus, perspective: perspective)
                if perspective == .protected {
                    guardianRow
                }
                lastBlockedSection
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(localized: "Shield")
        // App switcher snapshot on disk must not hold scam URLs or names (D-alief-A36).
        .privacyCover()
        .refreshable { await model.refresh() }
        // Coming back from Settings can flip Off → Active: say it (not on the first load).
        .onChange(of: model.extensionStatus.isActive) { _, isActive in
            guard model.state == .loaded else { return }
            AccessibilityNotification.Announcement(
                L10n.string(perspective.statusTitle(isActive: isActive), language: language)
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
    }

    @ViewBuilder
    private var guardianRow: some View {
        if model.state == .loaded {
            HStack(spacing: 16) {
                if let guardian = model.guardian {
                    AvatarView(id: guardian.avatarId, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Protected by").font(.subheadline).foregroundStyle(.readableSecondary)
                        Text(verbatim: guardian.name).font(.title3.bold())
                    }
                } else {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Not connected to a guardian yet").font(.headline)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("shield.guardian")
            if model.guardian == nil {
                Button { env.router.isConnectPresented = true } label: {
                    Text("Connect to your guardian").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("shield.connect")
            }
        }
    }

    @ViewBuilder
    private var lastBlockedSection: some View {
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Last blocked")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let scan = model.lastBlocked {
                    Button {
                        env.router.showDetail(scanId: scan.id)
                    } label: {
                        LastBlockedCard(scan: scan, reasons: model.reasons(for: scan, language: language), language: language)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shield.lastBlocked")
                } else {
                    EmptyStateView(
                        systemImage: "checkmark.shield",
                        title: "Nothing blocked yet",
                        message: "When Shoo blocks a scam site, you'll see it here."
                    )
                    .frame(minHeight: 220)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityIdentifier("shield.nothingBlocked")
                }
            }
        }
    }
}

/// Big Active / Off circle (PR-04). Off offers the way to switch the extension on.
private struct ExtensionStatusCard: View {
    let status: ExtensionStatus
    let perspective: ShieldPerspective
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .largeTitle) private var circle: CGFloat = 96

    /// Capped so "Turn on" stays on screen at accessibility sizes.
    private var side: CGFloat { min(circle, 160) }
    /// Dark enough for the white icon to keep 3:1 (WCAG 1.4.11).
    private var fill: Color {
        status.isActive ? Color(red: 0.10, green: 0.47, blue: 0.24) : Color(red: 0.42, green: 0.42, blue: 0.44)
    }

    /// The reason in a few words (#135); the Turn on sheet holds the full steps.
    private var subtitle: LocalizedStringKey {
        switch status.nextStep {
        case nil: "Shoo checks the sites you open in Safari."
        case .openAWebsite: "Open any website in Safari to finish setup."
        case .switchOn: "Shoo is switched off in Safari."
        case .allowEveryWebsite: "Shoo can't check every website yet."
        case .switchOnThenOpenAWebsite: "Switch on Shoo in Safari to stay safe."
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: status.isActive ? "checkmark.shield.fill" : "shield.slash.fill")
                .font(.system(size: side * 0.5))
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .background(fill, in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(verbatim: L10n.string(perspective.statusTitle(isActive: status.isActive), language: AppLanguage(locale: locale)))
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.readableSecondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            if status.nextStep != nil {
                Button {
                    env.router.isTurnOnPresented = true
                } label: {
                    Text(status.isActive ? "Finish setup" : "Turn on").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(Text("Shows how to switch Shoo on in Safari"))
                .accessibilityIdentifier("shield.turnOn")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(status.isActive ? "shield.status.active" : "shield.status.off")
        .sheet(
            isPresented: Binding(get: { env.router.isTurnOnPresented }, set: { env.router.isTurnOnPresented = $0 }),
            onDismiss: env.router.sheetDismissed
        ) {
            TurnOnExtensionSheet()
        }
    }
}

/// "Blocked!" card: score, site, why, when. Tap opens Detail.
private struct LastBlockedCard: View {
    let scan: ScanResult
    let reasons: [String]
    let language: AppLanguage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var time: String { Formatters.relative(scan.detectedAt, language: language) }

    var body: some View {
        // Ring above the text at accessibility sizes, so the text keeps the full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        layout {
            ScoreRing(score: scan.score, size: 64, lineWidth: 7)
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("Blocked!").foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.red)
                }
                .font(.headline)
                Text(verbatim: scan.domain)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                ForEach(reasons, id: \.self) { reason in
                    Text(verbatim: reason).font(.body).foregroundStyle(.primary)
                }
                Text(verbatim: time)
                    .font(.subheadline)
                    .foregroundStyle(.readableSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        // What, where, how risky, why, when — in that order.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("Blocked!") + Text(verbatim: " \(scan.domain). ") + Text("Risk score")
                + Text(verbatim: " \(Formatters.percent(scan.score, language: language)). "
                    + reasons.map { $0 + ". " }.joined() + time)
        )
        .accessibilityHint(Text("Opens the details"))
    }
}

#Preview {
    NavigationStack {
        ProtectedShieldView(repository: MockRepository(mode: .protected, latency: .zero), extensionStatus: { .off(lastSeen: nil) })
    }
        .environment(AppEnvironment.preview(mode: .protected))
}
