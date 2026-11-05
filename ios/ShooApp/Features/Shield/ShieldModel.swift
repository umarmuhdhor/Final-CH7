import Foundation
import Observation

/// Protected Home (PR-04, Figma "protected/Home" 957:11102 / 957:11377): extension status, the guardian, the
/// site blocked in the last 24 h, and recent activity. All from `GET /scans?owner=me`.
@MainActor
@Observable
final class ShieldModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed
    }

    private(set) var state: State = .loading
    private(set) var extensionStatus: ExtensionStatus = .off(lastSeen: nil)
    /// `GET /devices/me` → `guardian`; `nil` when not (or no longer) connected.
    private(set) var guardian: GuardianInfo?
    /// For the profile initial top right.
    private(set) var profileName: String?
    /// This device's scans the server still keeps (14-day retention), newest first.
    private(set) var scans: [ScanResult] = []
    /// The card under the activity; empty hides it.
    private(set) var scamCases: [ScamCase] = []

    /// The blocked card shows a site for this long after it was blocked.
    static let blockedCardWindow: TimeInterval = 24 * 60 * 60
    /// Enough for 14 days of one person; stops a runaway cursor.
    static let maxPages = 10
    static let recentCount = 3

    @ObservationIgnored private let repository: any ShooRepository
    @ObservationIgnored private let readExtensionStatus: () async -> ExtensionStatus
    @ObservationIgnored private var generation = 0

    @ObservationIgnored private let now: () -> Date

    init(
        repository: any ShooRepository,
        extensionStatus: @escaping () async -> ExtensionStatus = { await ExtensionStatus.load() },
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        readExtensionStatus = extensionStatus
        self.now = now
    }

    // MARK: Derived

    /// Newest `blocked` scan of this device.
    var lastBlocked: ScanResult? {
        scans.filter { $0.status == .blocked }.max { $0.detectedAt < $1.detectedAt }
    }

    /// The big card: the newest blocked site of the last 24 h.
    var recentBlocked: ScanResult? {
        guard let scan = lastBlocked, scan.detectedAt >= now().addingTimeInterval(-Self.blockedCardWindow) else { return nil }
        return scan
    }

    /// The site in the big card is not listed again (Figma 957:11377).
    var recent: [ScanResult] { scans.prefix(Self.recentCount).filter { $0.id != recentBlocked?.id } }

    /// On appear and every time the app comes back to the foreground.
    /// Overlapping calls: only the newest one is applied.
    func refresh() async {
        generation += 1
        let request = generation
        // Local (App Group + Safari's switch): never waits for the network.
        extensionStatus = await readExtensionStatus()
        guard request == generation else { return }
        do {
            async let profile = repository.me()
            async let all = allScans()
            // A bonus on Home: it never fails the screen.
            async let cases = try? repository.latestScams()
            let (me, loaded) = try await (profile, all)
            let loadedCases = await cases
            guard request == generation else { return }
            guardian = me.guardian
            profileName = me.name
            scans = loaded.sorted { $0.detectedAt > $1.detectedAt }
            scamCases = loadedCases ?? []
            state = .loaded
        } catch {
            guard request == generation, !error.isCancellation else { return }
            Log.ui.error("Shield load failed", error)
            // A failed foreground refresh keeps what is already on screen.
            if state != .loaded { state = .failed }
        }
    }

    /// "Try again" on the error view: shows the spinner while it retries.
    func retry() async {
        state = .loading
        await refresh()
    }

    private func allScans() async throws -> [ScanResult] {
        var items: [ScanResult] = []
        var cursor: String?
        for _ in 0..<Self.maxPages {
            let page = try await repository.scans(owner: .me, status: nil, cursor: cursor)
            items += page.items
            guard let next = page.nextCursor else { break }
            cursor = next
        }
        return items
    }
}
