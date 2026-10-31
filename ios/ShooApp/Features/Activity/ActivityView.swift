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

    init(repository: any ShooRepository, owner: ScanOwnerFilter, ownDeviceId: String? = nil) {
        _model = State(initialValue: ActivityModel(
            repository: repository, owner: owner, ownDeviceId: ownDeviceId,
            filter: Self.initialFilter, person: Self.initialPerson
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
        // First appearance, and coming back to the tab after a failed load.
        .task { if model.state != .loaded { await model.retry() } }
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
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityLabel(Text("Loading"))
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
        case .loaded where model.items.isEmpty:
            emptyState
                .accessibilityIdentifier("activity.empty")
        case .loaded:
            rows
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
                owner: model.isFamily ? .init(name: scan.ownerName, avatarId: model.avatarId(for: scan.ownerDeviceId)) : nil
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
                                    .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
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
        .padding(.vertical, 8)
        .frame(width: Self.width)
        .activityGlass(in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 30, y: 12)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Host and path only: query strings and fragments can carry personal data or tokens, and
    /// the link is visible to anyone looking at the screen (SECURITY §3 P9). Detail shows the full link.
    /// Activity rows show the domain only (Figma); Family cards (GD-03) still use this.
    static func displayLink(_ url: URL) -> String {
        let host = url.host() ?? ""
        let path = url.path()
        return path.isEmpty || path == "/" ? host : host + path
    }

    var body: some View {
        let badge = ScanBadge(scan: scan)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    ActivityBadge(badge: badge)
                    site
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    site
                    ActivityBadge(badge: badge)
                }
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.9)))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // One stop: site, status, (who), when.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(verbatim: scan.domain + ", ") + Text(ActivityBadge(badge: badge).title)
                + Text(verbatim: ", " + ([owner?.name].compactMap { $0 } + [time]).joined(separator: ", "))
        )
    }

    private var time: String { Formatters.time(scan.detectedAt, language: language) }


    /// Icon + domain (host only, never the path) + subline. One line as in Figma: a long domain
    /// ends in "…" to leave room for the badge; Detail shows the whole link.
    private var site: some View {
        HStack(spacing: 12) {
            SiteIcon(url: scan.faviconUrl)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: scan.domain)
                    .activityFont(17, tracking: -0.17)
                    .foregroundStyle(ActivityStyle.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.tail)
                    .frame(minHeight: 24)
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
