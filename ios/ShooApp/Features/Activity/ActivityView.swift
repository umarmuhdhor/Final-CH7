import SwiftUI

/// Activity (PR-05; GD-05 in Family mode with `owner: .family`), Figma "Aktivitas – Profil Pribadi /
/// Guardian": title, segments, rows grouped by day, endless scroll, pull to refresh. Tap → Detail.
/// Family mode adds the person picker top right (Figma "Switch Mode" + "Picker").
struct ActivityView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: ActivityModel
    @State private var isPickerOpen = false
    /// For the empty states: nil until read, so Off never flashes before the answer.
    @State private var extensionStatus: ExtensionStatus?
    @State private var checkStats = CheckStats()
    @State private var isTurnOnPresented = false

    init(
        repository: any ShooRepository, owner: ScanOwnerFilter, ownDeviceId: String? = nil,
        verdictSaves: @escaping @MainActor () -> Int = { 0 }
    ) {
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
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "debug.activityPicker") { isPickerOpen = true } }
        #endif
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
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
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
            ActivityMessage(systemImage: "wifi.exclamationmark", title: "Couldn't load activity", message: "Check your connection and try again.") {
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
                Label { Text("Couldn't refresh. Pull down to try again.") } icon: { Image(systemName: "exclamationmark.circle") }
                    .activityFont(15)
                    .foregroundStyle(ActivityStyle.secondary)
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
        let kind = ActivityEmptyKind.of(filter: model.filter, family: model.isFamily, extensionStatus: extensionStatus)
        return ActivityEmptyState(
            kind: kind,
            pill: model.isFamily ? nil : ActivityEmptyText.pill(kind: kind, stats: checkStats, language: language),
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
struct ActivitySegments: View {
    let selection: ActivityFilter
    let family: Bool
    let select: (ActivityFilter) -> Void
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ActivityFilter.allCases, id: \.self) { filter in
                let isSelected = filter == selection
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.1)) { select(filter) }
                } label: {
                    Text(filter.title(family: family))
                        .activityFont(13.33, isSelected ? .semibold : .medium, tracking: -0.08)
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
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
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("filter.\(filter.rawValue)")
            }
        }
        .padding(2)
        .background(ActivityStyle.segmentTrack, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Filter"))
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
                        ActivityAvatar(name: selected.name, avatarId: selected.avatarId, size: 24)
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
                    ActivityAvatar(name: member.name, avatarId: member.avatarId, size: 24)
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

    /// Host and path only: query strings and fragments can carry personal data or tokens, and
    /// the link is visible to anyone looking at the screen (SECURITY §3 P9). Detail shows the full link.
    /// Activity rows show the domain only (Figma); Family cards (GD-03) still use this.
    static func displayLink(_ url: URL) -> String {
        let host = url.host() ?? ""
        let path = url.path()
        return path.isEmpty || path == "/" ? host : host + path
    }

    /// The row title (BH-25): the registrable domain first, so it is the part that always shows, then the
    /// path when it is not the root, so two pages of one site read apart. Percent-encoded (BH-36): bidi
    /// or invisible characters in a path cannot reorder what is shown. No query or fragment (SECURITY §3 P9).
    static func pageTitle(url: URL, domain: String) -> String {
        let path = url.path(percentEncoded: true)
        return path.isEmpty || path == "/" ? domain : domain + path
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


    /// Icon + page title (domain, then path: `pageTitle`) + subline. One line as in Figma: a long title
    /// ends in "…" at the tail, so the domain stays and the path is what is cut; Detail shows the whole link. The badge shares its width
    /// with the domain line only, so "name | time" runs on under it: next to a wide verdict badge
    /// ("Penipuan terverifikasi") the name was cut to "M …" (QA 2026-11-10 #14).
    private func site(badge: Bool) -> some View {
        HStack(spacing: 12) {
            SiteIcon(url: scan.faviconUrl)
            // Figma "stack": 2 pt between domain and the "avatar name | time" line, none above a bare time.
            VStack(alignment: .leading, spacing: owner == nil ? 0 : 2) {
                HStack(alignment: .top, spacing: 16) {
                    Text(verbatim: Self.pageTitle(url: scan.url, domain: scan.domain))
                        .activityFont(17, tracking: -0.17)
                        .foregroundStyle(ActivityStyle.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .truncationMode(.tail)
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

    @ViewBuilder
    private var subline: some View {
        if let owner {
            // "Name | time" on one line as in Figma; the name is cut first, the time only when even
            // that is not enough (a long verdict badge), so the row never runs past the card.
            HStack(spacing: 4) {
                ActivityAvatar(name: owner.name, avatarId: owner.avatarId ?? "", size: 16)
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
    let message: LocalizedStringKey
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
                Text(message)
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
    init(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}
