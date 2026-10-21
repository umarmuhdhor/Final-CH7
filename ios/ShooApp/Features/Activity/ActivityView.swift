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
                FilterChips(selection: model.filter) { filter in
                    Task { await model.select(filter) }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
            }
            content
        }
        .listStyle(.plain)
        .navigationTitle(localized: "Activity")
        // App switcher snapshot on disk must not hold scam URLs or names (D-alief-A36).
        .privacyCover()
        .refreshable { await model.refresh() }
        // First appearance, and coming back to the tab after a failed load.
        .task { if model.state != .loaded { await model.retry() } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
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
                    .foregroundStyle(.secondary)
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
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
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

/// All / Warning / Blocked. Selected chip is filled; VoiceOver hears "selected".
struct FilterChips: View {
    let selection: ActivityFilter
    let select: (ActivityFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityFilter.allCases, id: \.self) { filter in
                    let isSelected = filter == selection
                    Button { select(filter) } label: {
                        Text(filter.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemFill)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("filter.\(filter.rawValue)")
                }
            }
        }
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
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                StatusChip(badge: ScanBadge(scan: scan))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
