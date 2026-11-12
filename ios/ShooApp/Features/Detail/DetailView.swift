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
    /// The material under the status bar shows once the hero has scrolled away.
    @State private var statusBarShade = 0.0
    /// The link pill grows with Dynamic Type; the title keeps clear of it.
    @State private var pillHeight: CGFloat = 34
    /// "Aman" on a site Shoo flagged asks why first (SafeReasonSheet); "Bahaya" still applies at once.
    @State private var askingSafeReason = false

    init(scanId: String, repository: any ShooRepository, onVerdictSaved: @escaping @MainActor () -> Void = {}) {
        _model = State(initialValue: DetailModel(scanId: scanId, repository: repository, onVerdictSaved: onVerdictSaved))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        content
            // Loader → Detail (or "gone" / "couldn't load"): a 0.2 s cross-fade, gentle enough for Reduce Motion.
            .animation(.easeOut(duration: 0.2), value: model.state)
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    DetailStyle.background
                    OnboardingHeaderBackground(height: 300)
                }
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            // Detail is drawn on fixed light colours (DetailStyle.background, the hero); in dark mode the
            // "gone" and "couldn't load" text turned white on that light background (BH-12). Pinned light,
            // as Home, Invite and Onboarding.
            .environment(\.colorScheme, .light)
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
                ShieldPulseLoader().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .transition(.opacity)
        case .notFound:
            // Figma "Detail Aktivitas · Sudah tidak ada" (1665:3006): the clock shield on slate, "Kedaluwarsa",
            // the two reasons an item goes, and the way back.
            StateHeroPage(
                chip: "Expired",
                chipTone: .slate,
                background: .image("HeroGradientSlate"),
                title: "This item is gone",
                message: "An item can disappear for one of these reasons:",
                titleIdentifier: "detail.notFound",
                onBack: { env.router.pop() },
                backIdentifier: "detail.back"
            ) {
                Image("StateShieldClock").resizable().frame(width: 215, height: 230)
            } content: {
                StateInfoList(rows: [
                    .init(systemImage: "clock.fill", text: "14 days have passed"),
                    .init(systemImage: "person.2.fill", text: "The family link was removed"),
                ], tint: Color(hex: 0x4F6074), boxed: false)
                .padding(.horizontal, 14)
            } footer: {
                Button("Back to Activity") { env.router.pop() }
                    .buttonStyle(OnboardingCapsuleButtonStyle())
                    .accessibilityIdentifier("detail.backToActivity")
            }
            .transition(.opacity)
        case .failed:
            // Figma "Detail Aktivitas · Gagal memuat" (1665:3023): the "!" shield on orange, "Gangguan koneksi".
            StateHeroPage(
                chip: "Connection problem",
                chipTone: .orange,
                background: .image("HeroGradientOrange"),
                title: "Couldn't load this item",
                message: "This item can't be shown right now. Check your connection, then try again!",
                titleIdentifier: "detail.failed",
                onBack: { env.router.pop() },
                backIdentifier: "detail.back"
            ) {
                Image("StateShieldAlert").resizable().frame(width: 215, height: 230)
            } content: {
                EmptyView()
            } footer: {
                Button("Try again") { loadAttempt += 1 }
                    .buttonStyle(OnboardingCapsuleButtonStyle())
                    .accessibilityIdentifier("detail.retry")
            }
            .sensoryFeedback(.error, trigger: model.state == .failed)
            .transition(.opacity)
        case .loaded:
            if let scan = model.scan {
                loaded(scan)
                    .modifier(LoaderReplacementFade())
            }
        }
    }

    /// Someone else's scan in the guardian's view; never on the viewer's own.
    private func ownerName(_ scan: ScanResult) -> String? {
        model.viewer?.mode == .guardian && !model.isOwnScan ? scan.ownerName : nil
    }

    private func loaded(_ scan: ScanResult) -> some View {
        let reasons = model.evidence(language: language)
        let look = DetailLook(scan: scan)
        return ScrollView {
            VStack(spacing: 0) {
                DetailHero(look: look, guardianAvatarId: model.deciderAvatarId) { env.router.pop() }
                sheet(scan, reasons: reasons, look: look)
            }
            .background(alignment: .top) {
                // Figma "Hero BG" (402 × 360, rings in it); its top colour carries on when pulled down.
                DetailHeroBackground(look: look)
                    .background(alignment: .bottom) {
                        look.topColor.frame(height: 400).offset(y: -DetailHeroLayout.imageHeight)
                    }
                    .accessibilityHidden(true)
            }
        }
        .scrollIndicators(.hidden)
        // Figma lays the hero out from the top of the screen, under the status bar.
        .ignoresSafeArea(edges: .top)
        .background(Color.white)
        // Cards scrolling under the status bar stay readable once the hero has gone up.
        .overlay(alignment: .top) {
            Color.clear.frame(height: 0)
                .background(.ultraThinMaterial.opacity(statusBarShade), ignoresSafeAreaEdges: .top)
        }
        .onScrollOffset { statusBarShade = $0 > DetailHeroLayout.sheetTop - 60 ? 0.9 : 0 }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Only the guardian answers here; the protected person reads the decision in "Status situs"
            // (the Ortu frames of 1211:19924 have no footer).
            if model.canValidate {
                DetailFooter(
                    verdict: scan.verdict,
                    viewerDeviceId: model.viewer?.deviceId,
                    canValidate: model.canValidate,
                    failure: model.verdictError,
                    ownerName: ownerName(scan),
                    isBlocked: scan.status == .blocked,
                    onDecide: { value in
                        if value == .safe {
                            askingSafeReason = true
                            return
                        }
                        Task {
                            let outcome = await model.setVerdict(value)
                            announce(outcome)
                        }
                    }
                )
            }
        }
        .sensoryFeedback(.success, trigger: model.verdictSaves)
        .sheet(isPresented: $askingSafeReason) {
            SafeReasonSheet { notes in
                let outcome = await model.setVerdict(.safe, notes: notes)
                announce(outcome)
                return outcome == .saved || outcome == .gone
            }
        }
    }

    /// Figma "Sheet": white from y 284 with 32 pt corners; the link pill sits on its top edge.
    private func sheet(_ scan: ScanResult, reasons: [Evidence], look: DetailLook) -> some View {
        VStack(spacing: 0) {
            summary(scan, look: look)
            DetailStyle.divider
                .frame(height: 1)
                .padding(.horizontal, 24)
                // Figma: the score row ends at 500, the divider is at 516, "Alasan Terdeteksi" at 541.
                .padding(.top, 16)
                .padding(.bottom, 24)
            VStack(alignment: .leading, spacing: 16) {
                Text("Reasons detected")
                    .activityFont(20, .semibold, tracking: -0.45)
                    .figmaLineHeight(25, relativeTo: .title2)
                    .foregroundStyle(DetailStyle.title)
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
            .padding(.bottom, 24)
        }
        // Figma: the title starts 32 pt into the sheet (y 316), 15 pt under the 34 pt pill.
        .padding(.top, max(32, pillHeight / 2 - 1 + 16))
        .frame(maxWidth: .infinity)
        .background(
            .white,
            in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
        )
        .overlay(alignment: .top) {
            // Verbatim: never turned into a tappable link (D-alief-A31). Copy from the menu.
            DetailLinkPill(look: look, text: Self.shownLink(scan.url, domain: scan.domain))
                .contextMenu {
                    Button {
                        copyLink(scan.url)
                    } label: {
                        Label("Copy link", systemImage: "doc.on.doc")
                    }
                }
                .accessibilityAction(named: Text("Copy link")) { copyLink(scan.url) }
                .accessibilityIdentifier("detail.link")
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pillHeight = $0 }
                // Figma: 34 pt at y 266, i.e. its middle 1 pt above the sheet's top edge.
                .alignmentGuide(.top) { $0.height / 2 + 1 }
        }
    }

    private func copyLink(_ url: URL) {
        LinkCopy.copy(url)
        AccessibilityNotification.Announcement(L10n.string("Copied", language: language)).post()
    }

    /// Title, when it was opened, then the score next to the site status (own scan) or who opened it.
    private func summary(_ scan: ScanResult, look: DetailLook) -> some View {
        // Figma 24; 22 here because the line above sits 2 pt lower to match.
        VStack(spacing: 22) {
            // Overlaid on the Figma export: title 1 pt low, the line under it 2 pt high with the 8 pt gap.
            VStack(spacing: 10) {
                Text(verbatim: title(scan))
                    .activityFont(28, .medium, tracking: -0.56)
                    // Figma 120 % (33.6 pt) is the font's own line; an exact height clipped a wrapped title
                    // at large Dynamic Type (accessibility audit).
                    .foregroundStyle(DetailStyle.title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("detail.title")
                Text(verbatim: openedText(scan.detectedAt))
                    .activityFont(13, rounded: true, tracking: -0.08)
                    .figmaLineHeight(18, relativeTo: .footnote)
                    .foregroundStyle(DetailStyle.rowSubtitle)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("detail.time")
            }
            .padding(.horizontal, 16)
            scoreRow(scan, look: look)
        }
    }

    /// Figma "Frame 1618872308": two 181 pt columns either side of a 76 pt line. The red frames put it
    /// at x 24–387 (line at 205.5), the orange ones at 16–386 (line at 201).
    private func scoreRow(_ scan: ScanResult, look: DetailLook) -> some View {
        let leading: CGFloat = look == .danger ? 24 : 16
        let gap: CGFloat = look == .danger ? 0 : 3.5
        return HStack(alignment: .top, spacing: 0) {
            scoreColumn(scan)
                .frame(width: 181)
            DetailStyle.scoreLine
                .frame(width: 1, height: 76)
                .padding(.top, 12)
                .padding(.horizontal, gap)
            rightColumn(scan)
                .frame(width: 181)
        }
        .padding(.leading, leading)
        // 100 pt in Figma; grows with Dynamic Type instead of clipping.
        .frame(width: DetailHeroLayout.width, alignment: .topLeading)
        .frame(minHeight: 100, alignment: .top)
        .frame(maxWidth: .infinity)
    }

    /// "Penilaian Risiko Shoo", "92/100" and the bar (DT-01).
    private func scoreColumn(_ scan: ScanResult) -> some View {
        VStack(spacing: 6) {
            Text("detail.riskScore")
                .activityFont(13, rounded: true, tracking: -0.08)
                .figmaLineHeight(18, glyphOffset: 2, relativeTo: .footnote)
                .foregroundStyle(DetailStyle.rowSubtitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "\(scan.score)/100")
                .activityFont(28, .semibold, tracking: 0.56)
                .figmaLineHeight(34, glyphOffset: -1, relativeTo: .title)
                .foregroundStyle(DetailStyle.title)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            RiskScoreBar(score: scan.score, weights: scan.signals.map(\.weight))
        }
        .padding(.top, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Risk score"))
        .accessibilityValue(Text(verbatim: headerValue(scan)))
        .accessibilityIdentifier("detail.header")
    }

    /// Someone else's scan: "Profil yang mengakses" and their chip. Own scan: "Status situs", the chip and
    /// who decided ("dikonfirmasi Virellia · 10.51", "ditandai oleh Shoo").
    @ViewBuilder
    private func rightColumn(_ scan: ScanResult) -> some View {
        if let owner = ownerName(scan) {
            VStack(spacing: 16) {
                label("detail.openedBy")
                DetailOwnerChip(name: owner, avatarId: model.ownerAvatarId)
            }
            .padding(.top, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Opened by \(owner)"))
            .accessibilityIdentifier("detail.owner")
        } else {
            VStack(spacing: 6) {
                label("detail.siteStatus")
                DetailStatusChip(kind: statusKind(scan))
                    .frame(maxWidth: .infinity)
                Text(verbatim: decidedText(scan))
                    .activityFont(13, rounded: true, tracking: -0.08)
                    .figmaLineHeight(18, glyphOffset: 2, relativeTo: .footnote)
                    .foregroundStyle(DetailStyle.rowSubtitle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    // Figma: 16 pt in on both sides (147 pt of 181).
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier(scan.verdict == nil ? "detail.flagged" : "detail.verdictNote")
            }
            .padding(.top, 12)
        }
    }

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .activityFont(13, rounded: true, tracking: -0.08)
            .figmaLineHeight(18, glyphOffset: 1.5, relativeTo: .footnote)
            .foregroundStyle(DetailStyle.rowSubtitle)
            .multilineTextAlignment(.center)
            .frame(width: 181)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusKind(_ scan: ScanResult) -> DetailStatusChip.Kind {
        switch scan.verdict?.value {
        case .notSafe: .blocked
        case .safe: scan.status == .blocked ? .unblocked : .markedSafe
        case nil: scan.status == .blocked ? .blocked : .warning
        }
    }

    /// "dikonfirmasi Virellia · 10.51" once a guardian decided, "ditandai oleh Shoo" before.
    private func decidedText(_ scan: ScanResult) -> String {
        guard let verdict = scan.verdict else { return L10n.string("detail.flaggedByShoo", language: language) }
        let time = Formatters.dateFormatter(template: "jm", locale: language.locale, timeZone: .current)
            .string(from: verdict.decidedAt)
        return verdict.byDeviceId == model.viewer?.deviceId
            ? L10n.string("confirmed by you · \(time)", language: language)
            : L10n.string("confirmed by \(verdict.byName) · \(time)", language: language)
    }

    /// "Situs Berbahaya!", "Situs Mencurigakan!", "Situs Sudah Ditandai Blokir!", "Anda Menandai ini Aman",
    /// "Virellia Menandai ini Aman".
    private func title(_ scan: ScanResult) -> String {
        let byViewer = scan.verdict?.byDeviceId == model.viewer?.deviceId
        switch scan.verdict?.value {
        case .safe:
            return byViewer
                ? L10n.string("detail.title.youMarkedSafe", language: language)
                : L10n.string("\(scan.verdict?.byName ?? "") marked this safe", language: language)
        case .notSafe where model.viewer?.mode == .guardian:
            return L10n.string("detail.title.markedBlocked", language: language)
        case .notSafe:
            return L10n.string("detail.title.dangerous", language: language)
        case nil:
            return scan.status == .blocked
                ? L10n.string("detail.title.dangerous", language: language)
                : L10n.string("detail.title.suspicious", language: language)
        }
    }

    // MARK: Header

    /// Back button only: the screens that have no hero (loading, gone, failed).
    private func topBar(owner: String?) -> some View {
        HStack {
            OnboardingBackButton(identifier: "detail.back") { env.router.pop() }
            Spacer()
        }
        .padding(.horizontal, ActivityStyle.margin)
        .padding(.top, 4)
    }

    /// Figma shows "bca-verifikasi.site/login"; the full link is what "Copy link" copies. The registrable
    /// domain, then the path (BH-13): a deceiving subdomain (`klikbca.co.id.secure-login.<domain>`) is left
    /// out and the domain is never the part the pill cuts, as on the block page (#382). The path stays
    /// percent-encoded (BH-36), as in Activity: bidi or invisible characters cannot reorder it.
    static func shownLink(_ url: URL, domain: String) -> String {
        let path = url.path(percentEncoded: true)
        return path.isEmpty || path == "/" ? domain : domain + path
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

    /// Up to 3 MB of device-written text, locked and read off the main actor (nonisolated async runs on the
    /// global executor, SE-0338; mark it `@concurrent` under Swift 6.2 `NonisolatedNonsendingByDefault`).
    /// Unlike the old `Task.detached`, closing Detail cancels it: no meta scan after the lock, and `nil`
    /// means no render (fase 22 C14).
    nonisolated static func prepare(_ html: String) async -> (locked: String?, meta: ReplicaMeta?) {
        guard !Task.isCancelled, let locked = ReplicaHTML.locked(html), !Task.isCancelled else { return (nil, nil) }
        return (locked, ReplicaMeta.read(from: html))
    }

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
            let (locked, meta) = await Self.prepare(html)
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
