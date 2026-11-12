import Foundation
import Observation

/// Protected Home (PR-04, Figma "protected/Home" 1115:17162 … 1373:12752): extension status, the guardian, the
/// newest risky site of the last 24 h with what the guardian decided, and recent activity. All from
/// `GET /scans?owner=me`.
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
    /// `false` until the first read of the extension's status: the hero says "Checking Shoo…" instead of a guess
    /// (Figma "protected/Home · Mengecek ekstensi" 1681:5275).
    private(set) var extensionChecked = false
    /// `GET /devices/me` → `guardian`; `nil` when not (or no longer) connected.
    private(set) var guardian: GuardianInfo?
    /// The picked avatar for the profile circle top right.
    private(set) var profileAvatarId: String?
    /// This device's scans of the last 24 h, and at least enough older ones to fill the list; newest first.
    private(set) var scans: [ScanResult] = []
    /// The card under the activity; empty hides it.
    private(set) var scamCases: [ScamCase] = []

    /// The big card shows a site for this long after it was seen.
    static let cardWindow: TimeInterval = 24 * 60 * 60
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

    /// Newest scan among the loaded ones (every scan is a warning or a block).
    var lastScan: ScanResult? {
        scans.max { $0.detectedAt < $1.detectedAt }
    }

    /// The big card: the newest warning or blocked site of the last 24 h, decided or not (protected/Home/blocked
    /// 1115:17294, /warning 1363:12167, approved 1373:13100, 1373:12376 …).
    var cardScan: ScanResult? {
        guard let scan = lastScan, scan.detectedAt >= now().addingTimeInterval(-Self.cardWindow) else { return nil }
        return scan
    }

    /// The site in the big card is not listed again; the next site takes its row.
    var recent: [ScanResult] {
        let card = cardScan?.id
        return Array(scans.lazy.filter { $0.id != card }.prefix(Self.recentCount))
    }

    /// On appear and every time the app comes back to the foreground.
    /// Overlapping calls: only the newest one is applied.
    func refresh() async {
        generation += 1
        let request = generation
        // Local (App Group + Safari's switch): never waits for the network.
        extensionStatus = await readExtensionStatus()
        extensionChecked = true
        guard request == generation else { return }
        do {
            async let profile = repository.me()
            async let all = allScans()
            let (me, loaded) = try await (profile, all)
            guard request == generation else { return }
            guardian = me.guardian
            profileAvatarId = me.avatarId
            scans = loaded.sorted { $0.detectedAt > $1.detectedAt }
            state = .loaded
        } catch {
            guard request == generation, !error.isCancellation else { return }
            Log.ui.error("Shield load failed", error)
            // A failed foreground refresh keeps what is already on screen.
            if state != .loaded { state = .failed }
            return
        }
        await refreshScamCases(request: request)
    }

    /// A bonus on Home: loaded after the screen, never fails it, and a failed call keeps the card on screen.
    private func refreshScamCases(request: Int) async {
        guard let cases = try? await repository.latestScams(), request == generation else { return }
        scamCases = cases
    }

    /// "Try again" on the error card: the card stays (its button spins) until the answer is in.
    func retry() async {
        await refresh()
    }

    /// Pages arrive newest first: stop once a page reaches past the card's window and the list
    /// (plus the card's site) has its rows.
    private func allScans() async throws -> [ScanResult] {
        let since = now().addingTimeInterval(-Self.cardWindow)
        var items: [ScanResult] = []
        var cursor: String?
        for _ in 0..<Self.maxPages {
            let page = try await repository.scans(owner: .me, status: nil, cursor: cursor)
            items += page.items
            guard let next = page.nextCursor else { break }
            if let oldest = page.items.last, oldest.detectedAt < since, items.count > Self.recentCount { break }
            cursor = next
        }
        return items
    }
}
