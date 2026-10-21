import SwiftUI

/// Detail for one scan, the same screen in every mode (PRD §8.4 DT-01..06, GD-07 buttons).
struct DetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @Environment(\.screenshotLoader) private var screenshotLoader
    @State private var model: DetailModel

    init(scanId: String, repository: any ShooRepository) {
        _model = State(initialValue: DetailModel(scanId: scanId, repository: repository))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        content
            .navigationTitle(localized: "Detail")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: model.scanId) { await model.load() }
            .privacyCover()
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notFound:
            EmptyStateView(
                systemImage: "clock.arrow.circlepath",
                title: "This item is gone",
                message: "Items are deleted after 14 days, or when the family is disconnected."
            )
        case .failed:
            VStack {
                EmptyStateView(
                    systemImage: "wifi.exclamationmark",
                    title: "Couldn't load this item",
                    message: "Check your connection and try again."
                )
                Button("Try again") {
                    Task { await model.load() }
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 32)
            }
        case .loaded:
            if let scan = model.scan {
                loaded(scan)
            }
        }
    }

    private func loaded(_ scan: ScanResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(scan)
                DetailInfoSection(
                    scan: scan,
                    ownerName: model.showsOwner(familyModeOn: env.settings.familyModeOn)
                        ? (model.isOwnScan ? L10n.string("You", language: language) : scan.ownerName)
                        : nil
                )
                EvidenceList(items: model.evidence(language: language))
                if let url = scan.screenshotUrl {
                    ScreenshotView(url: url)
                        .environment(\.screenshotLoader, loader)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            if model.canValidate {
                VerdictButtons(current: scan.verdict?.value, failed: model.verdictFailed) { value in
                    Task {
                        let outcome = await model.setVerdict(value)
                        announce(outcome)
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: model.verdictSaves)
    }

    /// VoiceOver hears the result of a tap: the new note, or that it was rolled back.
    private func announce(_ outcome: DetailModel.VerdictOutcome) {
        let text: String? = switch outcome {
        case .saved: model.verdictNote(language: language)
        case .rolledBack: L10n.string("Couldn't save. Check your connection and try again.", language: language)
        case .gone: L10n.string("This item is gone", language: language)
        case .ignored: nil
        }
        if let text { AccessibilityNotification.Announcement(text).post() }
    }

    /// DT-01 ring, DT-02 label, DT-06 note.
    private func header(_ scan: ScanResult) -> some View {
        VStack(spacing: 12) {
            ScoreRing(score: scan.score, size: 160, lineWidth: 16)
            if let badge = model.badge {
                StatusChip(badge: badge)
            }
            if let verdict = scan.verdict, let note = model.verdictNote(language: language) {
                VerdictNoteView(text: note, value: verdict.value)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Risk score"))
        .accessibilityValue(Text(verbatim: headerValue(scan)))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("detail.header")
    }

    /// "92%, Blocked, Verified scam by you" — the level is never only a colour.
    private func headerValue(_ scan: ScanResult) -> String {
        var parts = [Formatters.percent(scan.score, language: language)]
        if let badge = model.badge { parts.append(L10n.string(badge.titleKey, language: language)) }
        if let note = model.verdictNote(language: language) { parts.append(note) }
        return parts.joined(separator: ", ")
    }

    private var loader: any ScreenshotLoading {
        #if DEBUG
        if env.repository is MockRepository { return FixtureScreenshotLoader() }
        #endif
        return screenshotLoader
    }
}

private extension ScanBadge {
    /// `title` as a catalog key for strings built outside `Text` (D-alief-A02).
    var titleKey: String.LocalizationValue {
        switch self {
        case .warning: "Warning"
        case .blocked: "Blocked"
        case .verifiedScam: "Verified scam"
        case .markedSafe: "Marked safe"
        }
    }
}

/// DT-03: full link (copy only), time opened, owner in the guardian's family view.
private struct DetailInfoSection: View {
    let scan: ScanResult
    let ownerName: String?

    @Environment(\.locale) private var locale
    @State private var copied = false
    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Link")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    // Verbatim: never turned into a tappable link (D-alief-A31).
                    Text(verbatim: scan.url.absoluteString)
                        .font(.body.monospaced())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("detail.link")
                Button {
                    LinkCopy.copy(scan.url)
                    copied = true
                    AccessibilityNotification.Announcement(L10n.string("Copied", language: language)).post()
                } label: {
                    Label(copied ? LocalizedStringKey("Copied") : LocalizedStringKey("Copy link"), systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("detail.copyLink")
                .task(id: copied) {
                    guard copied else { return }
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            }
            row(
                title: "Opened",
                value: Formatters.dateTime(scan.detectedAt, language: language),
                detail: Formatters.relative(scan.detectedAt, language: language),
                identifier: "detail.time"
            )
            if let ownerName {
                row(title: "Opened by", value: ownerName, detail: nil, identifier: "detail.owner")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(title: LocalizedStringKey, value: String, detail: String?, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
            if let detail {
                Text(verbatim: detail)
                    .font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Guardian · blocked") {
    NavigationStack {
        DetailView(scanId: "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03", repository: MockRepository(latency: .zero))
    }
    .environment(AppEnvironment.preview())
}

#Preview("Protected · ID") {
    NavigationStack {
        DetailView(
            scanId: "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e05",
            repository: MockRepository(mode: .protected, latency: .zero)
        )
    }
    .environment(AppEnvironment.preview(mode: .protected, language: .indonesian))
    .environment(\.locale, AppLanguage.indonesian.locale)
}
