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
    /// Personal: the family list answered (it only decides the "Mode Terawasi" card).
    private(set) var personalMembersKnown = false
    private(set) var isSubmittingVerdict = false
    private(set) var verdictFailed = false
    /// The server refused this verdict (`verdict_not_allowed`), e.g. a warning site while the contract allows blocked only.
    private(set) var verdictNotAllowed = false
    /// Counts Home verdicts the server confirmed: drives the success haptic and the card's hand-over animation.
    private(set) var verdictSaves = 0

    let scope: Scope
    @ObservationIgnored private let repository: any ShooRepository
    @ObservationIgnored private let readExtensionStatus: () async -> ExtensionStatus
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let now: () -> Date
    /// Told after every verdict the server confirmed (`AppEnvironment.verdictSaves`, K8).
    @ObservationIgnored private let onVerdictSaved: @MainActor () -> Void
    @ObservationIgnored private var generation = 0
    /// Bumped by every verdict the server confirmed, like Detail's `verdictEpoch` (fase 27 K7).
    @ObservationIgnored private var verdictEpoch = 0
    /// Verdicts confirmed on Home by scan id, with the epoch they were saved in. A refresh that started
    /// before one of them read an older list; the verdict is put back on it.
    @ObservationIgnored private var savedVerdicts: [String: (epoch: Int, verdict: Verdict)] = [:]

    init(
        repository: any ShooRepository,
        settings: AppSettings,
        scope: Scope = .family,
        extensionStatus: @escaping () async -> ExtensionStatus = { await ExtensionStatus.load() },
        now: @escaping () -> Date = Date.init,
        onVerdictSaved: @escaping @MainActor () -> Void = {}
    ) {
        self.repository = repository
        self.settings = settings
        self.scope = scope
        readExtensionStatus = extensionStatus
        self.now = now
        self.onVerdictSaved = onVerdictSaved
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

    /// The avatar of a scan's owner: the guardian's own scans use their own avatar, a member's scans the
    /// member's. `nil` when the owner is not known (yet): the view draws the neutral person.
    func avatarId(forOwner deviceId: String) -> String? {
        if let profile, profile.deviceId == deviceId { return profile.avatarId }
        return members.first { $0.deviceId == deviceId }?.avatarId
    }

    /// Family Home with no one to look after: the invite takes the sheet.
    var hasNoFamily: Bool { scope == .family && state == .loaded && members.isEmpty }

    /// Pribadi with nobody to look after ("Pribadi/Home kalau belum setting guardian or protected" 1382:10567): the
    /// "Mode Terawasi" card, until it is closed. Unknown members (their call failed) hide it.
    var showsSupervisedCard: Bool {
        scope == .personal && state == .loaded && personalMembersKnown && members.isEmpty && !settings.supervisedCardDismissed
    }

    // MARK: Actions

    /// On appear, on foreground, on pull to refresh. Overlapping calls: only the newest one is applied,
    /// and a failed refresh keeps what is already on screen.
    func refresh() async {
        generation += 1
        let request = generation
        let epoch = verdictEpoch
        extensionStatus = await readExtensionStatus()
        guard request == generation else { return }
        do {
            async let me = repository.me()
            async let family: [FamilyMember] = scope == .family ? repository.familyMembers() : []
            async let all = allScans()
            let (loadedProfile, loadedMembers, loadedScans) = try await (me, family, all)
            guard request == generation else { return }
            profile = loadedProfile
            // Personal reads the family on its own, after the screen (`refreshPersonalMembers`).
            if scope == .family { members = loadedMembers }
            scans = merged(loadedScans, readAt: epoch)
            state = .loaded
        } catch {
            guard request == generation, !error.isCancellation else { return }
            Log.ui.error("Guardian Home load failed", error)
            if state != .loaded { state = .failed }
            return
        }
        if scope == .personal {
            await refreshPersonalMembers(request: request)
            await refreshScamCases(request: request)
        }
    }

    /// Personal Home only needs to know whether anyone is looked after; a failure never fails the screen.
    private func refreshPersonalMembers(request: Int) async {
        guard let loaded = try? await repository.familyMembers(), request == generation else { return }
        members = loaded
        personalMembersKnown = true
    }

    /// X on the "Mode Terawasi" card: gone for good on this iPhone.
    func dismissSupervisedCard() {
        settings.supervisedCardDismissed = true
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

    /// The last Safe / Dangerous tapped on the card: "Try again" under "Couldn't save" sends it again.
    private(set) var lastDecision: Verdict.Value?
    /// The reasons sent with the last "Safe" (SafeReasonSheet), so "Try again" sends them again.
    @ObservationIgnored private var lastNotes: String?
    /// The site the last answer was for, so "Try again" never lands on the next card.
    @ObservationIgnored private var lastScanId: String?

    /// "Try again" on "Couldn't save" (Figma 1665:3183).
    func retryDecision() async {
        guard let lastDecision else { return }
        await decide(lastDecision, notes: lastNotes, scanId: lastScanId)
    }

    /// X on the card: hidden on this iPhone, the next pending site (if any) takes its place.
    func dismissPending() {
        guard let scan = pendingScan else { return }
        verdictFailed = false
        verdictNotAllowed = false
        settings.dismissHomeScan(scan.id)
    }

    /// GD-07 from Home: applies at once, no confirmation. On success the card moves on to the next site.
    /// `notes`: why (the "Aman" reason sheet). `scanId`: the site the answer was given for (the sheet keeps it, so a
    /// card that moved on while the sheet was open never gets the answer); `nil` is the card shown now.
    /// `true` when the sheet can close: saved, the scan is gone, or this viewer may not decide (the card says so).
    @discardableResult
    func decide(_ value: Verdict.Value, notes: String? = nil, scanId: String? = nil) async -> Bool {
        let target = scanId.map { id in scans.first { $0.id == id } } ?? pendingScan
        guard let scan = target else { return scanId != nil }
        guard Self.verdictStatuses.contains(scan.status), !isSubmittingVerdict else { return false }
        isSubmittingVerdict = true
        lastDecision = value
        lastNotes = notes
        lastScanId = scan.id
        verdictFailed = false
        verdictNotAllowed = false
        defer { isSubmittingVerdict = false }
        do {
            let verdict = try await repository.setVerdict(scanId: scan.id, value: value, notes: notes)
            // Only the decided scan (K7): the server applies it per link (contracts/api.md, #241), and other
            // rows of that link get it from the next refresh. A refresh running now may have replaced `scans`.
            verdictEpoch += 1
            savedVerdicts[scan.id] = (verdictEpoch, verdict)
            if let index = scans.firstIndex(where: { $0.id == scan.id }) {
                scans[index].verdict = verdict
            }
            verdictSaves += 1
            onVerdictSaved()
            return true
        } catch RepositoryError.api(.verdictNotAllowed, _) {
            verdictNotAllowed = true
            return true
        } catch RepositoryError.api(.notFound, _) {
            // BH-27: the scan was deleted (14 days, a disconnect): no verdict can ever be saved on it, so the
            // card moves on to the next site, as Detail shows "This item is gone".
            scans.removeAll { $0.id == scan.id }
            return true
        } catch {
            guard !error.isCancellation else { return false }
            Log.ui.error("Home verdict failed", error)
            verdictFailed = true
            return false
        }
    }

    /// A list read when the epoch was `epoch`: verdicts saved after that are newer than the list, so they
    /// win for their scan. Older ones are in the list already (the server had them) and are forgotten.
    private func merged(_ loaded: [ScanResult], readAt epoch: Int) -> [ScanResult] {
        savedVerdicts = savedVerdicts.filter { $0.value.epoch > epoch }
        guard !savedVerdicts.isEmpty else { return loaded }
        return loaded.map { scan in
            guard let saved = savedVerdicts[scan.id] else { return scan }
            var scan = scan
            scan.verdict = saved.verdict
            return scan
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
