import SwiftUI
import UIKit

/// Detail for one scan, the same screen in every mode (PRD §8.4 DT-01..06, GD-07 buttons).
/// Figma "Guardian/Detail Aktivitas" (416:9255), "… Setelah Validasi" (416:9362), "… Waspada" (416:9469),
/// "… Ditandai Aman" (480:5768). The viewer's own scan has no owner chip and reads `labelSimple` when Protected.
struct DetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @Environment(\.screenshotLoader) private var screenshotLoader
    @Environment(\.replicaLoader) private var replicaLoader
    @State private var model: DetailModel
    /// The page image, in memory only (SECURITY §3 P9), shared by every card.
    @State private var screenshot: UIImage?
    @State private var screenshotLoading = false
    /// fase 18b: the page copy, drawn once; it comes before the screenshot (old builds) and the placeholder.
    @State private var pageCopy: PageCopy?
    @State private var copyState: PageCopyState = .none
    /// "Try again" bumps it, so the whole first load (read-aloud, waiting for the copy) runs again.
    @State private var loadAttempt = 0
    @State private var isZoomed = false
    @State private var copied = false

    init(scanId: String, repository: any ShooRepository) {
        _model = State(initialValue: DetailModel(scanId: scanId, repository: repository))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        content
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    DetailStyle.background
                    OnboardingHeaderBackground(height: 300)
                }
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .background(SwipeBackEnabler())
            .accessibilityAction(.escape) { env.router.pop() }
            .task(id: "\(model.scanId)#\(loadAttempt)") {
                #if DEBUG
                if env.repository is MockRepository {
                    model.marks = FixtureMarks.marks(scanId: model.scanId)
                    model.pageCSSWidth = FixtureMarks.pageWidth
                }
                #endif
                await model.load()
                // Left before the load ended: nothing is read out and nobody waits for the copy.
                guard !Task.isCancelled else { return }
                readAloud()
                await model.waitForCopy()
            }
            .task(id: model.scan?.pageReplicaUrl) { await loadPageCopy() }
            .task(id: model.scan?.screenshotUrl) {
                // With a copy the screenshot is only the fallback; a refreshed screenshot link after that
                // fallback must still load.
                guard model.scan?.pageReplicaUrl == nil || copyState == .unavailable else { return }
                await loadScreenshot()
            }
            .fullScreenCover(isPresented: $isZoomed) {
                if let pageImage { ZoomedScreenshot(image: pageImage) }
            }
            .privacyCover()
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            VStack(spacing: 0) {
                topBar(owner: nil)
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .notFound:
            VStack(spacing: 0) {
                topBar(owner: nil)
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: "This item is gone",
                    message: "Items are deleted after 14 days, or when the family is disconnected."
                )
            }
        case .failed:
            VStack(spacing: 0) {
                topBar(owner: nil)
                EmptyStateView(
                    systemImage: "wifi.exclamationmark",
                    title: "Couldn't load this item",
                    message: "Check your connection and try again."
                )
                Button("Try again") { loadAttempt += 1 }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 32)
            }
        case .loaded:
            if let scan = model.scan {
                loaded(scan)
            }
        }
    }

    /// Someone else's scan in the guardian's view; never on the viewer's own.
    private func ownerName(_ scan: ScanResult) -> String? {
        model.viewer?.mode == .guardian && !model.isOwnScan ? scan.ownerName : nil
    }

    private func loaded(_ scan: ScanResult) -> some View {
        let reasons = model.evidence(language: language)
        let markedSafe = scan.verdict?.value == .safe
        return ScrollView {
            VStack(spacing: 0) {
                topBar(owner: ownerName(scan))
                scoreCard(scan)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                VStack(alignment: .leading, spacing: 16) {
                    Text(markedSafe ? "What the AI flagged" : "Reasons detected")
                        .activityFont(17, .medium, tracking: -0.17)
                        .foregroundStyle(DetailStyle.secondary)
                        .accessibilityAddTraits(.isHeader)
                    PageCopyCaption(
                        state: model.isSavingCopy ? .saving : copyState,
                        meta: pageCopy?.meta,
                        scan: scan,
                        hasScreenshot: screenshot != nil || screenshotLoading
                    )
                    ForEach(reasons) { reason in
                        EvidenceCard(
                            reason: reason,
                            image: pageImage,
                            isLoadingImage: screenshotLoading || copyState == .loading || model.isSavingCopy,
                            pageCSSWidth: model.pageCSSWidth,
                            onOpenImage: { isZoomed = true }
                        )
                    }
                }
                .padding(.horizontal, ActivityStyle.margin)
                .padding(.top, 32)
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        // Cards scrolling under the status bar stay readable; over the header gradient it barely shows.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 0)
                .background(.ultraThinMaterial.opacity(0.9), ignoresSafeAreaEdges: .top)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.canValidate || scan.verdict != nil {
                DetailFooter(
                    verdict: scan.verdict,
                    viewerDeviceId: model.viewer?.deviceId,
                    canValidate: model.canValidate,
                    failed: model.verdictFailed,
                    ownerName: ownerName(scan),
                    onDecide: { value in
                        Task {
                            let outcome = await model.setVerdict(value)
                            announce(outcome)
                        }
                    }
                )
            }
        }
        .sensoryFeedback(.success, trigger: model.verdictSaves)
    }

    // MARK: Header

    /// Back button at the left, the owner chip in the middle (Figma "Profil Dilindungi").
    private func topBar(owner: String?) -> some View {
        ZStack {
            if let owner {
                HStack(spacing: 8) {
                    ActivityAvatar(name: owner, avatarId: model.ownerAvatarId ?? "1", size: 24)
                    Text(verbatim: owner)
                        .activityFont(16, .semibold, tracking: -0.16)
                        .foregroundStyle(DetailStyle.title)
                        .lineLimit(1)
                }
                .padding(.leading, 8)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
                .background(.white.opacity(0.7), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.9)))
                .padding(.horizontal, 84)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Opened by \(owner)"))
                .accessibilityIdentifier("detail.owner")
            }
            HStack {
                OnboardingBackButton(identifier: "detail.back") { env.router.pop() }
                Spacer()
            }
        }
        .padding(.horizontal, ActivityStyle.margin)
        .padding(.top, 4)
    }

    /// DT-01 gauge, DT-02 badge, DT-03 link and time (Figma "Score Card").
    private func scoreCard(_ scan: ScanResult) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                gauge(scan)
                badges(scan)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Risk score"))
            .accessibilityValue(Text(verbatim: headerValue(scan)))
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("detail.header")
            // Verbatim: never turned into a tappable link (D-alief-A31). Copy from the menu.
            Text(verbatim: Self.shownLink(scan.url))
                .activityFont(18, .semibold, tracking: -0.18)
                .foregroundStyle(DetailStyle.link)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .truncationMode(.middle)
                .padding(.horizontal, 24)
                .contextMenu {
                    Button {
                        LinkCopy.copy(scan.url)
                        AccessibilityNotification.Announcement(L10n.string("Copied", language: language)).post()
                    } label: {
                        Label("Copy link", systemImage: "doc.on.doc")
                    }
                }
                .accessibilityAction(named: Text("Copy link")) {
                    LinkCopy.copy(scan.url)
                    AccessibilityNotification.Announcement(L10n.string("Copied", language: language)).post()
                }
                .accessibilityIdentifier("detail.link")
            Text(verbatim: openedText(scan.detectedAt))
                .activityFont(13, rounded: true)
                .foregroundStyle(DetailStyle.secondary)
                .accessibilityIdentifier("detail.time")
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [DetailStyle.cardTop, DetailStyle.background], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 32, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(.white.opacity(0.9)))
    }

    /// 370 × 237 in Figma (219 when warning: the shorter label row); scales down on narrower screens.
    private func gauge(_ scan: ScanResult) -> some View {
        let height: CGFloat = scan.status == .blocked ? 237 : 219
        return Color.clear
            .aspectRatio(ScoreGauge.size.width / height, contentMode: .fit)
            .frame(maxWidth: ScoreGauge.size.width)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    ScoreGauge(score: scan.score, status: scan.status)
                        .scaleEffect(proxy.size.width / ScoreGauge.size.width, anchor: .topLeading)
                }
            }
    }

    /// The AI's badge; greyed with a blue "Anda menandai ini aman" chip once marked safe (480:5780).
    @ViewBuilder
    private func badges(_ scan: ScanResult) -> some View {
        let status = ScanBadge(status: scan.status)
        if let verdict = scan.verdict, verdict.value == .safe {
            HStack(spacing: 8) {
                GreyBadge(title: ActivityBadge(badge: status).title)
                Label {
                    Text(verbatim: VerdictNote.markedSafeChip(for: verdict, viewerDeviceId: model.viewer?.deviceId, language: language))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .labelStyle(ChipLabelStyle())
                .activityFont(13, tracking: -0.13)
                .foregroundStyle(DetailStyle.markedText)
                .padding(.leading, 8)
                .padding(.trailing, 9)
                .padding(.vertical, 6)
                .background(DetailStyle.markedFill, in: Capsule())
                .overlay(Capsule().stroke(DetailStyle.markedStroke))
            }
        } else {
            ActivityBadge(badge: status)
        }
    }

    /// Figma shows host and path ("bca-verifikasi.site/login"); the full link is what "Copy link" copies.
    static func shownLink(_ url: URL) -> String {
        guard let host = url.host(percentEncoded: false) else { return url.absoluteString }
        let path = url.path(percentEncoded: false)
        return host + (path == "/" ? "" : path)
    }

    /// "Diakses hari ini · 10.42 WIB".
    private func openedText(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = language.locale
            formatter.dateTimeStyle = .named
            day = formatter.localizedString(from: DateComponents(day: calendar.isDateInToday(date) ? 0 : -1))
        } else {
            day = Formatters.day(date, now: now, language: language)
        }
        return L10n.string("Opened \(day) · \(Formatters.time(date, language: language))", language: language)
    }

    // MARK: Text for VoiceOver

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

    /// "92%, Blocked, Verified scam by you" — the level is never only a colour.
    private func headerValue(_ scan: ScanResult) -> String {
        var parts = [Formatters.percent(scan.score, language: language)]
        if let badge = model.badge { parts.append(L10n.string(badge.titleKey, language: language)) }
        if let note = model.verdictNote(language: language) { parts.append(note) }
        return parts.joined(separator: ", ")
    }

    /// "Bacakan peringatan" (Pengaturan/Aksesibilitas): score and reasons of a warning, once loaded.
    private func readAloud() {
        guard let scan = model.scan else { return }
        let reasons = model.evidence(language: language).map { $0.spokenLine(language: language) }
        WarningFeedback.readAloud(settings: env.settings, text: ([headerValue(scan)] + reasons).joined(separator: ". "))
    }

    // MARK: Page copy and screenshot

    private var pageImage: UIImage? { pageCopy?.image ?? screenshot }

    /// fase 18b: fetch, lock, draw once, keep the picture. A failed link may only have expired: the model
    /// asks for a fresh one once. 429 says "Try again later" without a new link. A copy that can't be
    /// shown falls back to the screenshot of an old build, then to the placeholder.
    private func loadPageCopy() async {
        pageCopy = nil
        guard let url = model.scan?.pageReplicaUrl else {
            copyState = .none
            return
        }
        // Marks of an earlier picture would land on the wrong part of the next one (or of the screenshot).
        model.marks = []
        model.pageCSSWidth = nil
        copyState = .loading
        do {
            let html = try await pageLoader.html(at: url)
            // Up to 3 MB of device-written text: checked off the main thread.
            let (locked, meta) = await Task.detached(priority: .userInitiated) {
                (ReplicaHTML.locked(html), ReplicaMeta.read(from: html))
            }.value
            guard let locked,
                  let ruleList = await ReplicaRules.compiled(),
                  let window = ReplicaSnapshot.keyWindow,
                  let copy = await ReplicaSnapshot.render(locked, meta: meta, ruleList: ruleList, in: window)
            else {
                guard !Task.isCancelled else { return }
                copyState = .unavailable
                await loadScreenshot()
                return
            }
            guard !Task.isCancelled else { return }
            pageCopy = copy
            model.marks = copy.marks
            model.pageCSSWidth = copy.cssWidth
            copyState = .shown
        } catch ReplicaLoadError.rateLimited {
            guard !Task.isCancelled else { return }
            copyState = .rateLimited
        } catch {
            guard !error.isCancellation, !Task.isCancelled else { return }
            Log.ui.error("Page copy load failed")
            // A new link restarts `.task(id:)`.
            if await model.refreshReplicaLink() { return }
            // Cancelled while asking: the task for the next link owns the state now.
            guard !Task.isCancelled else { return }
            copyState = .unavailable
            await loadScreenshot()
        }
    }

    /// One load per link. A failed link may only have expired: the model asks for a fresh one once.
    private func loadScreenshot() async {
        screenshot = nil
        guard let url = model.scan?.screenshotUrl else { return }
        screenshotLoading = true
        defer { screenshotLoading = false }
        do {
            let data = try await loader.imageData(at: url)
            screenshot = ScreenshotDecoder.image(from: data)
        } catch {
            guard !error.isCancellation, !Task.isCancelled else { return }
            Log.ui.error("Screenshot load failed")
            // A new link restarts `.task(id:)`; otherwise the cards show no photo.
            _ = await model.refreshScreenshotLink()
        }
    }

    private var pageLoader: any ReplicaLoading {
        #if DEBUG
        if env.repository is MockRepository { return FixtureReplicaLoader() }
        #endif
        return replicaLoader
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

/// The AI's badge once a guardian marked the site safe: same words, grey (Figma 480:5780).
private struct GreyBadge: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle.fill")
                .activityFont(10, .semibold)
                .accessibilityHidden(true)
            Text(title)
                .activityFont(13, tracking: -0.1625)
                .lineLimit(1)
        }
        .foregroundStyle(DetailStyle.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 23)
        .background(DetailStyle.greyBadgeFill, in: Capsule())
        .overlay(Capsule().stroke(DetailStyle.greyBadgeStroke))
        .fixedSize()
    }
}

private struct ChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

#if DEBUG
/// Marks for the fixture page `FixtureScreenshotLoader` draws (390 pt wide, three fields from y 120),
/// so previews and the UI gate show both spotlight variants.
enum FixtureMarks {
    static let pageWidth: CGFloat = 390

    static func marks(scanId: String) -> [ReplicaMark] {
        guard scanId == "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03" else { return [] }
        return [
            ReplicaMark(signalId: "asks_pin", rect: CGRect(x: 20, y: 120, width: 350, height: 52)),
            ReplicaMark(signalId: "unreasonable_request", rect: CGRect(x: 20, y: 210, width: 350, height: 52)),
            ReplicaMark(signalId: "unreasonable_request", rect: CGRect(x: 20, y: 300, width: 350, height: 52)),
        ]
    }
}
#endif

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
