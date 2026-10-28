import Foundation
import Observation

/// Guardian Home (GD-01, Figma "Guardian/Home"): extension status, the family's numbers, the newest site that
/// still waits for a verdict, and recent activity. Everything comes from `GET /scans?owner=family`.
@MainActor
@Observable
final class GuardianHomeModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed
    }

    /// Which Home is shown, from the pending scan's `status` (contracts: 30–79 warning, ≥ 80 blocked).
    enum Level: Equatable {
        case normal
        case warning
        case danger
    }

    /// The four tiles, counted over the scans the server still keeps (14-day retention).
    struct Stats: Equatable {
        var blocked = 0
        var warnings = 0
        var suspiciousHosts = 0
        var scansToday = 0
    }

    /// A pending site gets a card for this long after it was detected.
    static let pendingWindow: TimeInterval = 24 * 60 * 60
    /// Statuses whose card shows Danger / Safe. Product decision: warning too.
    /// contracts/api.md still allows verdicts on `blocked` only (`verdict_not_allowed`) — raised with the lead.
    static let verdictStatuses: Set<ScanStatus> = [.warning, .blocked]
    /// Enough for 14 days of a family of 4; stops a runaway cursor.
    static let maxPages = 10
    static let recentCount = 3

    private(set) var state: State = .loading
    private(set) var extensionStatus: ExtensionStatus = .off(lastSeen: nil)
    private(set) var profile: DeviceProfile?
    private(set) var members: [FamilyMember] = []
    private(set) var scans: [ScanResult] = []
    private(set) var isSubmittingVerdict = false
    private(set) var verdictFailed = false
    /// The server refused this verdict (`verdict_not_allowed`), e.g. a warning site while the contract allows blocked only.
    private(set) var verdictNotAllowed = false

    @ObservationIgnored private let repository: any ShooRepository
    @ObservationIgnored private let readExtensionStatus: () async -> ExtensionStatus
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var generation = 0

    init(
        repository: any ShooRepository,
        settings: AppSettings,
        extensionStatus: @escaping () async -> ExtensionStatus = { await ExtensionStatus.load() },
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.settings = settings
        readExtensionStatus = extensionStatus
        self.now = now
    }

    // MARK: Derived

    /// Newest family member's scan from the last 24 h with no verdict, unless its card was closed.
    var pendingScan: ScanResult? {
        let since = now().addingTimeInterval(-Self.pendingWindow)
        let dismissed = Set(settings.dismissedHomeScanIds)
        return scans.first { scan in
            scan.verdict == nil
                && scan.ownerDeviceId != profile?.deviceId
                && scan.detectedAt >= since
                && !dismissed.contains(scan.id)
        }
    }

    var level: Level {
        switch pendingScan?.status {
        case nil: .normal
        case .warning: .warning
        case .blocked: .danger
        }
    }

    var canDecide: Bool {
        guard let scan = pendingScan else { return false }
        return Self.verdictStatuses.contains(scan.status)
    }

    var stats: Stats {
        let calendar = Calendar.current
        let today = now()
        return Stats(
            blocked: scans.filter { $0.status == .blocked }.count,
            warnings: scans.filter { $0.status == .warning }.count,
            suspiciousHosts: Set(scans.map { $0.domain.lowercased() }).count,
            scansToday: scans.filter { calendar.isDate($0.detectedAt, inSameDayAs: today) }.count
        )
    }

    var recent: [ScanResult] { Array(scans.prefix(Self.recentCount)) }

    /// Avatar for a scan's owner: a member's, or the guardian's own.
    func avatarId(for scan: ScanResult) -> String? {
        if scan.ownerDeviceId == profile?.deviceId { return profile?.avatarId }
        return members.first { $0.deviceId == scan.ownerDeviceId }?.avatarId
    }

    // MARK: Actions

    /// On appear, on foreground, on pull to refresh. Overlapping calls: only the newest one is applied,
    /// and a failed refresh keeps what is already on screen.
    func refresh() async {
        generation += 1
        let request = generation
        extensionStatus = await readExtensionStatus()
        guard request == generation else { return }
        do {
            async let me = repository.me()
            async let family = repository.familyMembers()
            async let all = allFamilyScans()
            let (loadedProfile, loadedMembers, loadedScans) = try await (me, family, all)
            guard request == generation else { return }
            profile = loadedProfile
            members = loadedMembers
            scans = loadedScans
            state = .loaded
        } catch {
            guard request == generation, !error.isCancellation else { return }
            Log.ui.error("Guardian Home load failed", error)
            if state != .loaded { state = .failed }
        }
    }

    func retry() async {
        state = .loading
        await refresh()
    }

    /// X on the card: hidden on this iPhone, the next pending site (if any) takes its place.
    func dismissPending() {
        guard let scan = pendingScan else { return }
        verdictFailed = false
        verdictNotAllowed = false
        settings.dismissHomeScan(scan.id)
    }

    /// GD-07 from Home: applies at once, no confirmation. On success the card moves on to the next site.
    func decide(_ value: Verdict.Value) async {
        guard canDecide, !isSubmittingVerdict, let scan = pendingScan else { return }
        isSubmittingVerdict = true
        verdictFailed = false
        verdictNotAllowed = false
        defer { isSubmittingVerdict = false }
        do {
            let verdict = try await repository.setVerdict(scanId: scan.id, value: value)
            // A verdict applies to the domain for that owner (contracts/api.md).
            for index in scans.indices where scans[index].domain == scan.domain && scans[index].ownerDeviceId == scan.ownerDeviceId {
                scans[index].verdict = verdict
            }
        } catch RepositoryError.api(.verdictNotAllowed, _) {
            verdictNotAllowed = true
        } catch {
            guard !error.isCancellation else { return }
            Log.ui.error("Home verdict failed", error)
            verdictFailed = true
        }
    }

    private func allFamilyScans() async throws -> [ScanResult] {
        var items: [ScanResult] = []
        var cursor: String?
        for _ in 0..<Self.maxPages {
            let page = try await repository.scans(owner: .family, status: nil, cursor: cursor)
            items += page.items
            guard let next = page.nextCursor else { break }
            cursor = next
        }
        return items
    }
}
