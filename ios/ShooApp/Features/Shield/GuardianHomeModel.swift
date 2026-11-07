import Foundation
import Observation

/// Guardian Home (GD-01/GD-03, Figma HOME page). `personal` (Family mode off, "Pribadi/Home"): extension
/// status, how the last day went and recent sites, from `GET /scans?owner=me`. `family` ("Guardian/Home"):
/// the people looked after, the newest site that still waits for a verdict, and the family's recent sites,
/// from `GET /scans?owner=family`.
@MainActor
@Observable
final class GuardianHomeModel {
    enum Scope: Equatable {
        case personal
        case family
    }

    enum State: Equatable {
        case loading
        case loaded
        case failed
    }

    /// Which Home is shown (contracts: 30–79 warning, ≥ 80 blocked). Family: the pending scan's `status`.
    /// Personal: the worst undecided site of the last 24 h.
    enum Level: Equatable {
        case normal
        case warning
        case danger
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
    /// The card under the personal activity; empty hides it.
    private(set) var scamCases: [ScamCase] = []
    private(set) var isSubmittingVerdict = false
    private(set) var verdictFailed = false
    /// The server refused this verdict (`verdict_not_allowed`), e.g. a warning site while the contract allows blocked only.
    private(set) var verdictNotAllowed = false

    let scope: Scope
    @ObservationIgnored private let repository: any ShooRepository
    @ObservationIgnored private let readExtensionStatus: () async -> ExtensionStatus
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var generation = 0

    init(
        repository: any ShooRepository,
        settings: AppSettings,
        scope: Scope = .family,
        extensionStatus: @escaping () async -> ExtensionStatus = { await ExtensionStatus.load() },
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.settings = settings
        self.scope = scope
        readExtensionStatus = extensionStatus
        self.now = now
    }

    // MARK: Derived

    /// Newest family member's scan from the last 24 h with no verdict, unless its card was closed.
    var pendingScan: ScanResult? {
        guard scope == .family else { return nil }
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
        switch scope {
        case .family:
            switch pendingScan?.status {
            case nil: .normal
            case .warning: .warning
            case .blocked: .danger
            }
        case .personal:
            personalLevel
        }
    }

    private var personalLevel: Level {
        let since = now().addingTimeInterval(-Self.pendingWindow)
        let open = scans.filter { $0.verdict == nil && $0.detectedAt >= since }
        if open.contains(where: { $0.status == .blocked }) { return .danger }
        return open.isEmpty ? .normal : .warning
    }

    var canDecide: Bool {
        guard let scan = pendingScan else { return false }
        return Self.verdictStatuses.contains(scan.status)
    }

    /// Family Home lists the members' sites only, like Family Activity (GD-05).
    var recent: [ScanResult] {
        let shown = scope == .family ? scans.filter { $0.ownerDeviceId != profile?.deviceId } : scans
        return Array(shown.prefix(Self.recentCount))
    }

    /// At most 3 people are shown (PRD GD-03).
    var shownMembers: [FamilyMember] { Array(members.prefix(FamilyShieldModel.maxMembers)) }

    /// Family Home with no one to look after: the invite takes the sheet.
    var hasNoFamily: Bool { scope == .family && state == .loaded && members.isEmpty }

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
            async let family: [FamilyMember] = scope == .family ? repository.familyMembers() : []
            async let all = allScans()
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
            return
        }
        if scope == .personal { await refreshScamCases(request: request) }
    }

    /// A bonus on Home: loaded after the screen, never fails it, and a failed call keeps the card on screen.
    private func refreshScamCases(request: Int) async {
        guard let cases = try? await repository.latestScams(), request == generation else { return }
        scamCases = cases
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

    /// Pages arrive newest first. Personal needs only the last day (the hero) and the list's rows: it stops once
    /// a page reaches past the window with enough rows. Family reads every page (members' sites, pending card).
    private func allScans() async throws -> [ScanResult] {
        let owner: ScanOwnerFilter = scope == .family ? .family : .me
        let since = now().addingTimeInterval(-Self.pendingWindow)
        var items: [ScanResult] = []
        var cursor: String?
        for _ in 0..<Self.maxPages {
            let page = try await repository.scans(owner: owner, status: nil, cursor: cursor)
            items += page.items
            guard let next = page.nextCursor else { break }
            if scope == .personal, let oldest = page.items.last, oldest.detectedAt < since,
               items.count >= Self.recentCount { break }
            cursor = next
        }
        return items
    }
}
