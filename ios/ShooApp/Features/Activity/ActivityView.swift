import SwiftUI

/// Activity (PR-05; GD-05 reuses it with `owner: .family` in fase 05): filter chips, newest first,
/// endless scroll, pull to refresh. Tap → Detail.
struct ActivityView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @State private var model: ActivityModel
    let showsOwner: Bool

    init(repository: any ShooRepository, owner: ScanOwnerFilter, showsOwner: Bool = false) {
        _model = State(initialValue: ActivityModel(repository: repository, owner: owner, filter: Self.initialFilter))
        self.showsOwner = showsOwner
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

    var body: some View {
        List {
            Section {
                if !model.people.isEmpty {
                    PersonChips(people: model.people, selection: model.person, language: language) { person in
                        Task { await model.select(person: person) }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                }
                FilterChips(selection: model.filter) { filter in
                    Task { await model.select(filter) }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                if model.baseOwner == .family {
                    Text("Only your own history? Set Family to Off.")
                        .font(.footnote)
                        .foregroundStyle(.readableSecondary)
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("activity.familyNote")
                }
            }
            content
        }
        .listStyle(.plain)
        .navigationTitle(localized: model.baseOwner == .family ? "Family activity" : "Activity")
        // App switcher snapshot on disk must not hold scam URLs or names (D-alief-A36).
        .privacyCover()
        .refreshable { await model.refresh() }
        .onChange(of: model.refreshFailed) { _, failed in
            guard failed else { return }
            AccessibilityNotification.Announcement(
                L10n.string("Couldn't refresh. Pull down to try again.", language: language)
            ).post()
        }
        // First appearance, and coming back to the tab after a failed load.
        .task { if model.state != .loaded { await model.retry() } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityLabel(Text("Loading"))
                .listRowSeparator(.hidden)
        case .failed:
            VStack(spacing: 12) {
                EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn't load activity", message: "Check your connection and try again.")
                Button { Task { await model.retry() } } label: { Text("Try again").frame(minHeight: 44) }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
        case .loaded where model.items.isEmpty:
            emptyState
                .frame(maxWidth: .infinity, minHeight: 300)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("activity.empty")
        case .loaded:
            if model.refreshFailed {
                Label { Text("Couldn't refresh. Pull down to try again.") } icon: { Image(systemName: "exclamationmark.circle") }
                    .font(.subheadline)
                    .foregroundStyle(.readableSecondary)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("activity.refreshFailed")
            }
            ForEach(model.items) { scan in
                Button {
                    env.router.showDetail(scanId: scan.id)
                } label: {
                    ActivityRow(scan: scan, language: language, showsOwner: showsOwner)
                }
                .accessibilityIdentifier("activity.row.\(scan.id)")
                .onAppear {
                    if scan.id == model.items.last?.id {
                        Task { await model.loadMore() }
                    }
                }
            }
            if model.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .accessibilityLabel(Text("Loading"))
            } else if model.loadMoreFailed {
                Button { Task { await model.loadMore() } } label: {
                    Label("Couldn't load more. Try again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("activity.loadMoreRetry")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch model.filter {
        case .all:
            EmptyStateView(systemImage: "list.bullet.rectangle", title: "No activity yet", message: "Risky sites you open will show up here.")
        case .warning:
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "No warnings", message: "Sites that look risky will show up here.")
        case .blocked:
            EmptyStateView(systemImage: "hand.raised", title: "Nothing blocked yet", message: "Blocked scam sites will show up here.")
        }
    }
}

/// One chip in a `ChoiceChips` bar.
struct ChipOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: Text
    let identifier: String
    var id: String { identifier }
}

/// Single-choice chips. Selected chip is filled and ticked; VoiceOver hears "selected".
/// At accessibility sizes the chips stack full width instead of scrolling sideways out of view.
struct ChoiceChips<Value: Hashable>: View {
    let label: Text
    let options: [ChipOption<Value>]
    let selection: Value
    let select: (Value) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// White text keeps 4.5:1 on this blue in light and dark mode (system accent is about 4:1).
    private static var selectedFill: Color { Color(red: 0, green: 0.38, blue: 0.80) }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { chips(fullWidth: true) }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { chips(fullWidth: false) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func chips(fullWidth: Bool) -> some View {
        ForEach(options) { option in
            let isSelected = option.value == selection
            Button { select(option.value) } label: {
                HStack(spacing: 6) {
                    if isSelected {
                        Image(systemName: "checkmark").accessibilityHidden(true)
                    }
                    option.title
                }
                .font(.body.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44, alignment: .leading)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? AnyShapeStyle(Self.selectedFill) : AnyShapeStyle(Color(.secondarySystemFill)), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier(option.identifier)
        }
    }
}

/// All / Warning / Blocked (PR-05, GD-05).
struct FilterChips: View {
    let selection: ActivityFilter
    let select: (ActivityFilter) -> Void

    var body: some View {
        ChoiceChips(
            label: Text("Filter"),
            options: ActivityFilter.allCases.map { ChipOption(value: $0, title: Text($0.title), identifier: "filter.\($0.rawValue)") },
            selection: selection,
            select: select
        )
    }
}

/// Everyone / You / each member (GD-05).
struct PersonChips: View {
    let people: [FamilyMember]
    let selection: ActivityPerson
    let language: AppLanguage
    let select: (ActivityPerson) -> Void

    var body: some View {
        ChoiceChips(
            label: Text("Person"),
            options: [
                ChipOption(value: ActivityPerson.everyone, title: Text("Everyone"), identifier: "person.everyone"),
                ChipOption(value: .me, title: Text("You"), identifier: "person.me"),
            ] + people.map { ChipOption(value: .device($0.deviceId), title: Text(verbatim: $0.name), identifier: "person.\($0.deviceId)") },
            selection: selection,
            select: select
        )
    }
}

/// One Activity item: site icon, domain (bold), link, relative time, status chip.
struct ActivityRow: View {
    let scan: ScanResult
    let language: AppLanguage
    var showsOwner = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Host and path only: query strings and fragments can carry personal data or tokens, and
    /// the row is visible to anyone looking at the screen (SECURITY §3 P9). Detail shows the full link.
    static func displayLink(_ url: URL) -> String {
        let host = url.host() ?? ""
        let path = url.path()
        return path.isEmpty || path == "/" ? host : host + path
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SiteIcon(domain: scan.domain)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: scan.domain)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(verbatim: Self.displayLink(scan.url))
                    .font(.subheadline)
                    .foregroundStyle(.readableSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    if showsOwner {
                        Text(verbatim: scan.ownerName)
                        Text(verbatim: "·").accessibilityHidden(true)
                    }
                    Text(verbatim: Formatters.relative(scan.detectedAt, language: language))
                }
                .font(.subheadline)
                .foregroundStyle(.readableSecondary)
                StatusChip(badge: ScanBadge(scan: scan))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        // One stop: site, status, (who), when. The link line only repeats the domain.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(verbatim: scan.domain + ", ") + Text(ScanBadge(scan: scan).title)
                + Text(verbatim: ", " + ((showsOwner ? [scan.ownerName] : []) + [Formatters.relative(scan.detectedAt, language: language)]).joined(separator: ", "))
        )
    }
}
