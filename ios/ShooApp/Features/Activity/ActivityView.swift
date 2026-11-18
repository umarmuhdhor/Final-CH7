import SwiftUI

/// Activity (PR-05; GD-05 in Family mode with `owner: .family`), Figma "Aktivitas – Profil Pribadi /
/// Guardian": title, segments, rows grouped by day, endless scroll, pull to refresh. Tap → Detail.
/// Family mode adds the person picker top right (Figma "Switch Mode" + "Picker").
struct ActivityView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: ActivityModel
    @State private var isPickerOpen = false
    /// For the empty states: nil until read, so Off never flashes before the answer.
    @State private var extensionStatus: ExtensionStatus?
    @State private var checkStats = CheckStats()
    @State private var isTurnOnPresented = false
    /// Set when pushed (a member's activity from Member detail): the page draws its own back button, as the
    /// navigation bar is hidden. Nil on the Activity tab's root.
    private let onBack: (() -> Void)?

    init(
        repository: any ShooRepository, owner: ScanOwnerFilter, ownDeviceId: String? = nil,
        verdictSaves: @escaping @MainActor () -> Int = { 0 }, onBack: (() -> Void)? = nil
    ) {
        self.onBack = onBack
        _model = State(initialValue: ActivityModel(
            repository: repository, owner: owner, ownDeviceId: ownDeviceId,
            filter: Self.initialFilter, person: Self.initialPerson, verdictSaves: verdictSaves
        ))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    /// Screenshots open a filter directly with `-debug.activityFilter warning` (DEBUG only).
    private static var initialFilter: ActivityFilter {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "debug.activityFilter"), let filter = ActivityFilter(rawValue: raw) {
            return filter
        }
        #endif
        return .all
    }

    /// Screenshots open one member with `-debug.activityPerson dev_mom` (DEBUG only).
    private static var initialPerson: ActivityPerson {
        #if DEBUG
        if let id = UserDefaults.standard.string(forKey: "debug.activityPerson") {
            return .device(id)
        }
        #endif
        return .everyone
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .zIndex(1)
                ActivitySegments(selection: model.filter, family: model.isFamily) { filter in
                    Task { await model.select(filter) }
                }
                .padding(.top, 24)
                content
                    // Loader → list (or message): a 0.2 s cross-fade, gentle enough for Reduce Motion.
                    .animation(.easeOut(duration: 0.2), value: model.state)
                    .padding(.top, 32)
            }
            .padding(.horizontal, ActivityStyle.margin)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(ActivityBackground())
        .overlayPreferenceValue(PickerAnchorKey.self) { anchor in
            if isPickerOpen, let anchor {
                picker(anchor: anchor)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        // Pushed: the tab bar stays hidden as on Member detail, and the edge swipe still goes back.
        .toolbar(onBack == nil ? .automatic : .hidden, for: .tabBar)
        .background { if onBack != nil { SwipeBackEnabler() } }
        .accessibilityAction(.escape) { onBack?() }
        // Detail's back button.
        .navigationTitle(localized: "Activity")
        // App switcher snapshot on disk must not hold scam URLs or names (D-alief-A36).
        .privacyCover()
        .refreshable {
            await model.refresh()
            await readExtension()
        }
        .onChange(of: model.refreshFailed) { _, failed in
            guard failed else { return }
            AccessibilityNotification.Announcement(
                L10n.string("Couldn't refresh. Pull down to try again.", language: language)
            ).post()
        }
        // A push while this screen is open (new scan, verdict, member change): reload, as Guardian Home does (A-12).
        .onChange(of: env.pushesWhileOpen) { _, count in
            Task { await model.pushesWhileOpenChanged(to: count) }
        }
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "debug.activityPicker") { isPickerOpen = true } }
        #endif
        // A tapped push opens Detail here: the "Turn on" sheet must not stay over it.
        .onChange(of: env.router.screenSheetsClosed) { isTurnOnPresented = false }
        .sheet(isPresented: $isTurnOnPresented, onDismiss: { Task { await readExtension() } }) {
            TurnOnExtensionSheet()
        }
        // First appearance, and coming back to the tab after a failed load. Back from Detail or from the other
        // tab: reload once if a verdict was saved meanwhile (K8).
        .task {
            if model.state != .loaded {
                await model.retry()
            } else {
                await model.refreshIfVerdictsChanged()
            }
        }
        .task { await readExtension() }
        // Back from the background (a push tapped while Shoo was closed, the app icon, `shoo://activity`): new scans
        // arrived meanwhile, and only pushes that land while Shoo is open reload this list (A-12). As Home does.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, model.state == .loaded else { return }
            Task { await model.refresh() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            if let onBack {
                OnboardingBackButton(identifier: "activity.back", action: onBack)
            }
            Text("Activity")
                .activityFont(27, .medium, tracking: -0.27)
                .foregroundStyle(ActivityStyle.title)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.isFamily, !model.people.isEmpty {
                ActivityPersonButton(people: model.people, selected: model.selectedMember) {
                    setPicker(open: true)
                }
                .anchorPreference(key: PickerAnchorKey.self, value: .bounds) { $0 }
            }
        }
        .frame(minHeight: 50)
        // Figma: the title's top is 2 pt under the status bar, the 50 pt picker button 7 pt above it.
        .padding(.top, -7)
    }

    private func setPicker(open: Bool) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) { isPickerOpen = open }
    }

    private func picker(anchor: Anchor<CGRect>) -> some View {
        GeometryReader { proxy in
            let button = proxy[anchor]
            ZStack(alignment: .topLeading) {
                // Tap anywhere else closes the menu.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { setPicker(open: false) }
                    .accessibilityHidden(true)
                ActivityPersonMenu(people: model.people, selection: model.person) { person in
                    setPicker(open: false)
                    Task { await model.select(person: person) }
                } close: {
                    setPicker(open: false)
                }
                .offset(x: button.maxX - ActivityPersonMenu.width, y: button.minY)
                .transition(.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
            }
        }
    }

    // MARK: List

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ShieldPulseLoader()
                .frame(maxWidth: .infinity, minHeight: 200)
                .transition(.opacity)
        case .failed:
            ActivityMessage(
                systemImage: "wifi.exclamationmark", title: "Couldn't load activity",
                message: Text(verbatim: L10n.string(model.loadFailure.message(connection: "Check your connection and try again."), language: language))
            ) {
                Button { Task { await model.retry() } } label: {
                    Text("Try again")
                        .activityFont(15, .semibold, tracking: -0.15)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(ActivityStyle.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("activity.retry")
            }
            .transition(.opacity)
        case .loaded where model.items.isEmpty:
            emptyState
                .accessibilityIdentifier("activity.empty")
                .transition(.opacity)
        case .loaded:
            rows
                .modifier(LoaderReplacementFade())
        }
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if model.refreshFailed {
                RefreshFailedNotice { await model.refresh() }
                    .transition(StateMotion.transition(reduceMotion: reduceMotion, edge: .top))
                    .accessibilityIdentifier("activity.refreshFailed")
            }
            let days = model.days
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                Section {
                    ForEach(day.items) { scan in
                        row(scan)
                    }
                } header: {
                    dayTitle(day.id)
                        .activityFont(17, .medium, tracking: -0.17)
                        .foregroundStyle(ActivityStyle.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, index == 0 ? 0 : 12)
                        .padding(.bottom, 4)
                }
            }
            if model.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel(Text("Loading"))
            } else if model.loadMoreFailed {
                Button { Task { await model.loadMore() } } label: {
                    Label("Couldn't load more. Try again", systemImage: "arrow.clockwise")
                        .activityFont(15, .medium)
                        .foregroundStyle(ActivityStyle.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("activity.loadMoreRetry")
            }
        }
        .animation(StateMotion.enter(reduceMotion: reduceMotion), value: model.refreshFailed)
    }

    private func row(_ scan: ScanResult) -> some View {
        Button {
            env.router.showDetail(scanId: scan.id)
        } label: {
            ActivityRow(
                scan: scan, language: language,
                owner: model.isFamily ? .init(name: scan.ownerName, avatarId: model.avatarId(for: scan.ownerDeviceId)) : nil,
                note: model.note(for: scan), ownList: model.isOwnList
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activity.row.\(scan.id)")
        .onAppear {
            if scan.id == model.items.last?.id {
                Task { await model.loadMore() }
            }
        }
    }

    /// "Hari ini" (own list) / "Hari Ini" (Family mode), as in the two Figma frames; else "25 Oktober".
    private func dayTitle(_ day: Date) -> Text {
        if Calendar.current.isDateInToday(day) {
            return model.isFamily ? Text("activity.todayFamily") : Text("Today")
        }
        return Text(verbatim: Formatters.day(day, language: language))
    }

    private var emptyState: some View {
        // Only this iPhone's own list is about this iPhone's extension: Family Activity and a member's Activity
        // (from Member detail) list other people's scans, so no "Protection is off" and no "sites checked" pill.
        let kind = ActivityEmptyKind.of(filter: model.filter, family: !model.isOwnList, extensionStatus: extensionStatus)
        return ActivityEmptyState(
            kind: kind,
            pill: model.isOwnList ? ActivityEmptyText.pill(kind: kind, stats: checkStats, language: language) : nil,
            offSince: ActivityEmptyText.offSince(extensionStatus?.lastSeen, language: language)
        ) {
            isTurnOnPresented = true
        }
    }

    /// The extension's state and counters for the empty states; cheap, read on every appearance.
    private func readExtension() async {
        extensionStatus = await env.extensionStatus()
        checkStats = CheckStats.current()
    }
}

/// Bounds of the person button, for placing the menu over it.
private struct PickerAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: Segments

/// "Semua / Waspada / Diblokir" (own) or "… / Bahaya" (Family): Figma "Segmented Control" (iOS 26 style).
/// Selected segment is white; VoiceOver hears "selected".
/// U-12: a filter word never breaks in the middle. Three equal segments while the longest word fits a third;
/// at large text sizes each segment as wide as its word; and when the words no longer fit side by side, one
/// segment per line.
struct ActivitySegments: View {
    let selection: ActivityFilter
    let family: Bool
    let select: (ActivityFilter) -> Void
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ActivitySegmentRow(spacing: 4) { segments(stacked: false) }
                .padding(2)
                .background(ActivityStyle.segmentTrack, in: Capsule())
            VStack(spacing: 4) { segments(stacked: true) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Filter"))
    }

    /// `stacked`: one segment per line, each on its own track (one capsule track around three lines would
    /// round off the top and bottom segments).
    private func segments(stacked: Bool) -> some View {
        ForEach(ActivityFilter.allCases, id: \.self) { filter in
            let isSelected = filter == selection
            Button {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.1)) { select(filter) }
            } label: {
                // The semibold word sets the width, so selecting a segment never changes which layout fits.
                // No line limit: if a word ever lacks room it wraps (the AX3 UI test sees that), never "…".
                Text(filter.title(family: family))
                    .activityFont(13.33, .semibold, tracking: -0.08)
                    .hidden()
                    .accessibilityHidden(true)
                    .overlay {
                        Text(filter.title(family: family))
                            .activityFont(13.33, isSelected ? .semibold : .medium, tracking: -0.08)
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(.white)
                                .shadow(color: .black.opacity(0.06), radius: 10, y: 2)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .background(stacked ? ActivityStyle.segmentTrack : .clear, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("filter.\(filter.rawValue)")
        }
    }
}

/// The segments side by side: equal widths while the widest fits a third of the row, otherwise each as wide
/// as its word plus an equal share of what is left. Its ideal width is the words side by side, so
/// `ViewThatFits` stacks the segments only when the words cannot share one line.
private struct ActivitySegmentRow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? ideal.reduce(gaps, +)
        let widths = widths(in: width, ideal: ideal)
        let height = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max()
        return CGSize(width: width, height: height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = widths(in: bounds.width, ideal: subviews.map { $0.sizeThatFits(.unspecified).width })
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(
                at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private func widths(in width: CGFloat, ideal: [CGFloat]) -> [CGFloat] {
        guard !ideal.isEmpty else { return [] }
        let count = CGFloat(ideal.count)
        let available = width - spacing * (count - 1)
        let equal = available / count
        if ideal.allSatisfy({ $0 <= equal }) { return ideal.map { _ in equal } }
        let share = max(available - ideal.reduce(0, +), 0) / count
        return ideal.map { $0 + share }
    }
}

// MARK: Person picker

/// Family mode's top-right glass button: everyone's stacked avatars, or the picked member's
/// avatar + name, and a chevron (Figma "Switch Mode").
struct ActivityPersonButton: View {
    let people: [FamilyMember]
    let selected: FamilyMember?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                if let selected {
                    HStack(spacing: 4) {
                        AvatarView(id: selected.avatarId, size: 24, ring: ActivityStyle.avatarRing)
                        Text(verbatim: selected.name)
                            .activityFont(15, tracking: -0.15)
                            .foregroundStyle(ActivityStyle.ink)
                            .lineLimit(1)
                    }
                } else {
                    ActivityAvatarStack(people: people)
                }
                Image(systemName: "chevron.down")
                    .activityFont(17)
                    .foregroundStyle(ActivityStyle.ink)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 50)
            .activityGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Person"))
        .accessibilityValue(selected.map { Text(verbatim: $0.name) } ?? Text("Everyone"))
        .accessibilityHint(Text("Shows whose activity to see"))
        .accessibilityIdentifier("activity.personPicker")
    }
}

/// Figma "Picker": glass menu with "Semua" (stacked avatars) and one row per member, single choice,
/// no checkmark. Rows are 40 pt as in Figma.
struct ActivityPersonMenu: View {
    static let width: CGFloat = 250

    let people: [FamilyMember]
    let selection: ActivityPerson
    let select: (ActivityPerson) -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            item(.everyone, title: Text("All"), identifier: "person.everyone") {
                ActivityAvatarStack(people: people)
            }
            ForEach(people) { member in
                item(.device(member.deviceId), title: Text(verbatim: member.name), identifier: "person.\(member.deviceId)") {
                    AvatarView(id: member.avatarId, size: 24, ring: ActivityStyle.avatarRing)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(width: Self.width)
        .activityGlass(in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        // Figma "Picker" glass: black 25 %, y 8, blur 48.
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .accessibilityIdentifier("activity.personMenu")
    }

    private func item(
        _ person: ActivityPerson, title: Text, identifier: String, @ViewBuilder avatar: () -> some View
    ) -> some View {
        Button { select(person) } label: {
            HStack(spacing: 8) {
                title
                    .activityFont(17, tracking: -0.43)
                    .foregroundStyle(ActivityStyle.menuText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                avatar()
            }
            .padding(.leading, 22)
            .padding(.trailing, 24)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(person == selection ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: Row

/// One Activity card: favicon circle, domain, (member avatar + name |) time, badge top right
/// (Figma "Update card", 354 × 82, r 20).
struct ActivityRow: View {
    struct Owner {
        let name: String
        let avatarId: String?
    }

    let scan: ScanResult
    let language: AppLanguage
    /// Family Activity only: whose scan it is.
    var owner: Owner?
    /// Own list only: the guardian's verdict, or that they have not looked yet (Figma 450:8443).
    var note: ActivityNote?
    /// Own list: Figma 450:8443 badges (solid "Diblokir"), the verdict goes in `note`.
    var ownList = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The least room the path gets next to a whole domain: "/" and "…" at the title size, so the domain is
    /// never followed by a bare "…".
    @ScaledMetric(relativeTo: .body) private var pathRoom: CGFloat = 24

    /// Host and path only: query strings and fragments can carry personal data or tokens, and
    /// the link is visible to anyone looking at the screen (SECURITY §3 P9). Detail shows the full link.
    /// Activity rows show the domain only (Figma); Family cards (GD-03) still use this.
    static func displayLink(_ url: URL) -> String {
        let host = url.host() ?? ""
        let path = url.path()
        return path.isEmpty || path == "/" ? host : host + path
    }

    /// The row title (BH-25): the scan's `domain` first (the registrable domain, or the full host on a shared
    /// platform such as `sites.google.com`, #495), so it is the part that always shows, then the
    /// path when it is not the root, so two pages of one site read apart. Percent-encoded (BH-36): bidi
    /// or invisible characters in a path cannot reorder what is shown. No query or fragment (SECURITY §3 P9).
    static func pageTitle(url: URL, domain: String) -> String {
        let parts = titleParts(url: url, domain: domain)
        return parts.domain + parts.path
    }

    /// The row title split in two (U-05, K8): the scan's `domain`, drawn whole or cut in the middle, and the
    /// path after it (empty for the root), the only part cut at its tail. Same encoding rules as `pageTitle`.
    static func titleParts(url: URL, domain: String) -> (domain: String, path: String) {
        let path = url.path(percentEncoded: true)
        return (domain, path == "/" ? "" : path)
    }

    var body: some View {
        // Figma 450:8443 / 450:8657: a one-line note sits 8 pt under the row and the card stays 118 high
        // (11 pt below the note); the two-line "safe" note is laid out 16 pt under the row, 17 pt above the edge.
        VStack(alignment: .leading, spacing: note?.isTwoLine == true ? 16 : 8) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        statusBadge
                        site(badge: false)
                    }
                } else {
                    site(badge: true)
                }
            }
            if let note {
                ActivityNoteView(note: note, language: language)
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 17)
        .padding(.bottom, note.map { $0.isTwoLine ? 17 : 11 } ?? 17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.9)))
        .figmaCardShadow()
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // One stop: site, status, (who), when.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(verbatim: Self.pageTitle(url: scan.url, domain: scan.domain) + ", ") + statusTitle
                + Text(verbatim: ", " + ([owner?.name].compactMap { $0 } + [time]).joined(separator: ", "))
                + (note.map { Text(verbatim: ". ") + $0.text(language: language) } ?? Text(verbatim: ""))
        )
    }

    /// The own list keeps the detection status on the badge ("Waspada" / "Diblokir") and puts the
    /// guardian's verdict in the note below (Figma 450:8443); Family lists still show the verdict.
    @ViewBuilder
    private var statusBadge: some View {
        if ownList && scan.status == .blocked {
            ActivityBlockedPill(markedSafe: scan.verdict?.value == .safe)
        } else if ownList {
            ActivityBadge(badge: .warning)
        } else {
            ActivityBadge(badge: ScanBadge(scan: scan))
        }
    }

    private var statusTitle: Text {
        if ownList {
            return Text(ActivityBadge(badge: ScanBadge(status: scan.status)).title)
        }
        return Text(ActivityBadge(badge: ScanBadge(scan: scan)).title)
    }

    private var time: String { Formatters.time(scan.detectedAt, language: language) }


    /// Icon + page title (domain, then path: `title`) + subline. One line as in Figma; Detail shows the whole
    /// link. The badge shares its width with the domain line only, so "name | time" runs on under it: next to a
    /// wide verdict badge ("Penipuan terverifikasi") the name was cut to "M …" (QA 2026-11-10 #14).
    private func site(badge: Bool) -> some View {
        HStack(spacing: 12) {
            SiteIcon(url: scan.faviconUrl)
            // Figma "stack": 2 pt between domain and the "avatar name | time" line, none above a bare time.
            VStack(alignment: .leading, spacing: owner == nil ? 0 : 2) {
                HStack(alignment: .top, spacing: 16) {
                    title
                        .activityFont(17, tracking: -0.17)
                        .foregroundStyle(ActivityStyle.ink)
                        .frame(minHeight: 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if badge { statusBadge }
                }
                subline
                    .frame(minHeight: 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// U-05 (K8): the start of the domain is free text the scammer picks ("bca-verifikasi-…"); its end holds the
    /// public suffix (".site"), which no fake can make read as the bank's own. So the domain is never cut at its
    /// tail: whole, or cut in the middle as on the Home card. The path only gets the
    /// room the whole domain leaves (at least `pathRoom`), cut at its tail; with less, the row shows the domain
    /// alone rather than a "…" right after it that reads as more domain.
    @ViewBuilder
    private var title: some View {
        let parts = Self.titleParts(url: scan.url, domain: scan.domain)
        let domain = Text(verbatim: parts.domain).truncationMode(.middle)
        if parts.path.isEmpty {
            domain.lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        } else if dynamicTypeSize.isAccessibilitySize {
            // Large text wraps: the domain on up to three lines (as without a path), the path on its own line under it.
            VStack(alignment: .leading, spacing: 0) {
                domain.lineLimit(3)
                Text(verbatim: parts.path).lineLimit(1).truncationMode(.tail)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    domain.lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    Text(verbatim: parts.path).lineLimit(1).truncationMode(.tail)
                        .frame(idealWidth: pathRoom, alignment: .leading)
                }
                domain.lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var subline: some View {
        if let owner {
            // "Name | time" on one line as in Figma; the name is cut first, the time only when even
            // that is not enough (a long verdict badge), so the row never runs past the card.
            HStack(spacing: 4) {
                AvatarView(id: owner.avatarId ?? "", size: 16, ring: ActivityStyle.avatarRing)
                Text(verbatim: owner.name)
                    .activityFont(13, .medium, rounded: true)
                    .lineLimit(1)
                Text(verbatim: "|")
                    .activityFont(13, rounded: true)
                    .foregroundStyle(ActivityStyle.separator)
                    .fixedSize()
                Text(verbatim: time)
                    .activityFont(13, rounded: true)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .foregroundStyle(ActivityStyle.secondary)
        } else {
            Text(verbatim: time)
                .activityFont(13, rounded: true)
                .foregroundStyle(ActivityStyle.time)
                .lineLimit(1)
        }
    }
}

// MARK: Messages

/// Empty / error state in the Figma card look: grey icon circle, title, message, optional button.
struct ActivityMessage<Action: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: Text
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .activityFont(20, .semibold)
                .foregroundStyle(ActivityStyle.secondary)
                .frame(width: 48, height: 48)
                .background(ActivityStyle.iconFill, in: Circle())
                .overlay(Circle().stroke(ActivityStyle.iconStroke))
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(title)
                    .activityFont(17, .semibold, tracking: -0.17)
                    .foregroundStyle(ActivityStyle.ink)
                    .accessibilityAddTraits(.isHeader)
                message
                    .activityFont(15, tracking: -0.15)
                    .foregroundStyle(ActivityStyle.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            // One VoiceOver stop, and the caller's identifier lands on one element.
            .accessibilityElement(children: .combine)
            action
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.9)))
        .accessibilityElement(children: .contain)
    }
}

extension ActivityMessage where Action == EmptyView {
    init(systemImage: String, title: LocalizedStringKey, message: Text) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

/// Figma "Aktivitas · Gagal memperbarui" (1681:6347): over the rows the list still shows, an 80 pt grey tile with
/// the circular "!", "Gagal memperbarui" and "Menampilkan data terakhir. **Coba Lagi**". The tile's symbol nudges
/// when it arrives and spins in place of itself while the retry runs. Guardian Home shows the same notice over what it
/// last loaded (D-alief-A12, fase 28a K1).
struct RefreshFailedNotice: View {
    var retryIdentifier = "activity.refreshRetry"
    let retry: () async -> Void
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var isRunning = false
    @State private var nudge = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if isRunning {
                    ProgressView().controlSize(.large).tint(Color(hex: 0x6A717E))
                } else {
                    icon
                }
            }
            .frame(width: 80, height: 80)
            .background(Color(hex: 0xF3F6F8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityHidden(true)
            Text("Couldn't refresh")
                .activityFont(17, .semibold, tracking: -0.43)
                .foregroundStyle(Color(hex: 0x151617))
                .padding(.top, 14)
            Button {
                guard !isRunning else { return }
                Task {
                    isRunning = true
                    await retry()
                    isRunning = false
                    nudge += 1
                }
            } label: {
                (Text("Showing the last data. ") + Text("Try again").foregroundColor(Color(hex: 0x136CB7)).fontWeight(.semibold))
                    .activityFont(13, tracking: -0.08)
                    .foregroundStyle(Color(hex: 0x6A717E))
                    .frame(minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(isRunning)
            .accessibilityIdentifier(retryIdentifier)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .onAppear { nudge += 1 }
        .sensoryFeedback(.error, trigger: nudge) { old, _ in old == 0 }
    }

    @ViewBuilder
    private var icon: some View {
        let image = Image(systemName: "exclamationmark.arrow.circlepath")
            .font(.system(size: 43, weight: .regular))
            .foregroundStyle(Color(hex: 0x6A717E))
        if reduceMotion {
            image
        } else if #available(iOS 18, *) {
            image.symbolEffect(.wiggle.byLayer, options: .nonRepeating, value: nudge)
        } else {
            image.symbolEffect(.bounce, options: .nonRepeating, value: nudge)
        }
    }
}
