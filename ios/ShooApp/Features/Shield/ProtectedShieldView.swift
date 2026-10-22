import SwiftUI

/// Protected Home (PR-04): is protection on, who looks after me, what was blocked last.
struct ProtectedShieldView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var model: ShieldModel

    init(repository: any ShooRepository, extensionStatus: @escaping () -> ExtensionStatus) {
        _model = State(initialValue: ShieldModel(repository: repository, extensionStatus: extensionStatus))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ExtensionStatusCard(status: model.extensionStatus)
                guardianRow
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
                L10n.string(isActive ? "Protection is on" : "Protection is off", language: language)
            ).post()
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
                    // TODO(sync:alief): link to PR-01 Connect — replace after fase 14
                    Text("Not connected to a guardian yet").font(.headline)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("shield.guardian")
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
    @State private var isTurnOnPresented = false
    @ScaledMetric(relativeTo: .largeTitle) private var circle: CGFloat = 96

    /// Capped so "Turn on" stays on screen at accessibility sizes.
    private var side: CGFloat { min(circle, 160) }
    /// Dark enough for the white icon to keep 3:1 (WCAG 1.4.11).
    private var fill: Color {
        status.isActive ? Color(red: 0.10, green: 0.47, blue: 0.24) : Color(red: 0.42, green: 0.42, blue: 0.44)
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
                Text(status.isActive ? "Protection is on" : "Protection is off")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(status.isActive ? "Shoo checks the sites you open in Safari." : "Switch on Shoo in Safari to stay safe.")
                    .font(.body)
                    .foregroundStyle(.readableSecondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            if !status.isActive {
                Button {
                    isTurnOnPresented = true
                } label: {
                    Text("Turn on").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
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
        .sheet(isPresented: $isTurnOnPresented) {
            TurnOnExtensionSheet()
        }
    }
}

/// ON-04's guide as a sheet (PR-04). Closes itself once the extension reports in.
private struct TurnOnExtensionSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TurnOnExtensionView {
                if env.extensionStatus().isActive { dismiss() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("turnOn.close")
                }
            }
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
