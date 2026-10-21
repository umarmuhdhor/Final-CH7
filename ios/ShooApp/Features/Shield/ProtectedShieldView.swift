import SwiftUI

/// Protected Home (PR-04): is protection on, who looks after me, what was blocked last.
struct ProtectedShieldView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var model: ShieldModel

    init(repository: any ShooRepository) {
        _model = State(initialValue: ShieldModel(repository: repository))
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
                        Text("Protected by").font(.subheadline).foregroundStyle(.secondary)
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
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        case .failed:
            VStack(spacing: 12) {
                Text("Couldn't load your Shield").font(.headline)
                Text("Check your connection and try again.").foregroundStyle(.secondary)
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
    @ScaledMetric(relativeTo: .largeTitle) private var circle: CGFloat = 96

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: status.isActive ? "checkmark.shield.fill" : "shield.slash.fill")
                .font(.system(size: circle * 0.5))
                .foregroundStyle(.white)
                .frame(width: circle, height: circle)
                .background(status.isActive ? Color.green.gradient : Color.gray.gradient, in: Circle())
                .accessibilityHidden(true)
            Text(status.isActive ? "Protection is on" : "Protection is off")
                .font(.title2.bold())
            Text(status.isActive ? "Shoo checks the sites you open in Safari." : "Switch on Shoo in Safari to stay safe.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !status.isActive {
                Button {
                    // TODO(sync:alief): present TurnOnExtensionView (fase 02) as a sheet once 02 is in this chain
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Turn on").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("shield.turnOn")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(status.isActive ? "shield.status.active" : "shield.status.off")
    }
}

/// "Blocked!" card: score, site, why, when. Tap opens Detail.
private struct LastBlockedCard: View {
    let scan: ScanResult
    let reasons: [String]
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScoreRing(score: scan.score, size: 64, lineWidth: 7)
            VStack(alignment: .leading, spacing: 6) {
                Label { Text("Blocked!") } icon: { Image(systemName: "hand.raised.fill") }
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(verbatim: scan.domain)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                ForEach(reasons, id: \.self) { reason in
                    Text(verbatim: reason).font(.body).foregroundStyle(.primary)
                }
                Text(verbatim: Formatters.relative(scan.detectedAt, language: language))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the details"))
    }
}

#Preview {
    NavigationStack { ProtectedShieldView(repository: MockRepository(mode: .protected, latency: .zero)) }
        .environment(AppEnvironment.preview(mode: .protected))
}
