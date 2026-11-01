import Foundation

/// `ShooRepository` backed by `Data/Fixtures` (copies of contracts/fixtures). Used for previews,
/// tests and the whole of Fase A; `ApiRepository` replaces it in Fase C.
///
/// Magic join codes trigger the contract errors so screens can show them:
/// `0000` code_invalid · `9999` code_expired · `8888` family_full · `7777` too_many_attempts · `6666` already_connected.
actor MockRepository: ShooRepository {
    enum Scenario: String, Sendable {
        /// Fixture data as in contracts/fixtures.
        case standard
        /// No scans, no members — for empty states.
        case empty
        /// Fixture data with only the first member (UI gate GD-03: 1 person).
        case oneMember
        /// Fixture data plus a third, connected member without risky sites (UI gate GD-03: 3 people).
        case threeMembers
        // Figma parity QA (`MockScenarios`): the content the Figma frames show, and variants of it.
        case figma
        case mixedVerdicts
        case heavy
        case edge
        case allSafe
        case allBlocked
        /// Imelda's eval corpus with the detector's real results (`Fixtures/corpus-scans.json`).
        case corpus
    }

    /// Not in contracts/fixtures: only the 3-member UI gate uses it.
    static let extraMember = FamilyMember(
        deviceId: "dev_grandma", name: "Grandma", avatarId: "avatar_05", extensionActive: true, lastScan: nil
    )

    /// Fixture identities. `dev_me` is the guardian in contracts/fixtures (verdicts "by Adhella").
    static let guardianProfile = DeviceProfile(
        deviceId: "dev_me", name: "Adhella", avatarId: "avatar_01", mode: .guardian, language: "en", guardian: nil,
        stats: ProfileStats(blocked: 3, warnings: 5, since: Date(timeIntervalSince1970: 1_789_351_800)),
        timeZone: "Asia/Jakarta", notifications: .defaults
    )
    static let fixtureGuardian = GuardianInfo(deviceId: "dev_me", name: "Adhella", avatarId: "avatar_01")
    static let protectedProfile = DeviceProfile(
        deviceId: "dev_mom", name: "Mom", avatarId: "avatar_03", mode: .protected, language: "en",
        guardian: fixtureGuardian,
        stats: ProfileStats(blocked: 3, warnings: 1, since: Date(timeIntervalSince1970: 1_789_351_800)),
        timeZone: "Asia/Jakarta", notifications: .defaults
    )

    /// PF-01 member detail fields (proposed, not in contracts/fixtures): added to the fixture members by id.
    static func withDetails(_ member: FamilyMember) -> FamilyMember {
        var m = member
        m.connectedAt = Date(timeIntervalSince1970: 1_789_351_800) // 14 Sep 2026
        m.notify = true
        switch m.deviceId {
        case "dev_mom":
            m.lastSeenAt = Date(timeIntervalSince1970: 1_793_073_480)
            m.deviceModel = "iPhone 15"
            m.osVersion = "26"
            m.stats = .init(blocked: 3, warnings: 5)
        case "dev_dad":
            m.lastSeenAt = Date(timeIntervalSince1970: 1_792_900_000)
            m.deviceModel = "iPad"
            m.osVersion = "26"
            m.stats = .init(blocked: 1, warnings: 0)
        default:
            m.stats = .init(blocked: 0, warnings: 0)
        }
        return m
    }
    static let pageSize = 20

    private var profile: DeviceProfile
    private var allScans: [ScanResult]
    private var members: [FamilyMember]
    /// The guardian's active code, handed out again while more than 5 min is left.
    private var familyCode: FamilyCode?
    nonisolated let scenario: Scenario
    nonisolated let latency: Duration
    nonisolated let pageSize: Int
    private nonisolated let bundle: Bundle
    private nonisolated let now: @Sendable () -> Date
    /// `-debug.replicaFixture YES`: Detail of a scan with a screenshot gets a page copy link (`FixtureReplicaLoader`).
    /// The contract fixtures have `pageReplicaUrl: null`, so previews and the UI gate need this to show a copy.
    nonisolated let pageCopies: Bool

    /// Link the Detail screen gets for a fixture page copy; `example.invalid` never resolves.
    static func fixtureReplicaURL(scanId: String) -> URL {
        URL(string: "https://example.invalid/replicas/\(scanId)")!
    }

    init(
        mode: UserMode = .guardian,
        scenario: Scenario = .standard,
        latency: Duration = .milliseconds(300),
        pageSize: Int = MockRepository.pageSize,
        bundle: Bundle = .main,
        pageCopies: Bool = false,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let dataset = MockScenarios.dataset(for: scenario, now: now(), bundle: bundle)
        if let dataset {
            profile = mode == .guardian ? dataset.guardian : dataset.protected
        } else {
            profile = mode == .guardian ? Self.guardianProfile : Self.protectedProfile
        }
        self.pageCopies = pageCopies
        self.scenario = scenario
        self.latency = latency
        self.pageSize = pageSize
        self.bundle = bundle
        self.now = now
        switch scenario {
        case .standard, .oneMember, .threeMembers:
            allScans = Self.load(ScanPage.self, "activity-family", bundle: bundle)?.items ?? []
            let fixture = Self.load(FamilyMembersResponse.self, "family-members", bundle: bundle)?.members ?? []
            switch scenario {
            case .oneMember: members = Array(fixture.prefix(1)).map(Self.withDetails)
            case .threeMembers: members = (fixture + [Self.extraMember]).map(Self.withDetails)
            default: members = fixture.map(Self.withDetails)
            }
        case .empty:
            allScans = []
            members = []
        case .figma, .mixedVerdicts, .heavy, .edge, .allSafe, .allBlocked, .corpus:
            allScans = dataset?.scans ?? []
            members = dataset?.members ?? []
        }
    }

    // MARK: Devices

    func registerDevice(name: String, mode: UserMode, avatarId: String?, apnsToken: String?) async throws -> DeviceRegistration {
        try await pause()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...20).contains(trimmed.count) else {
            throw RepositoryError.api(.invalidBody, message: "name must be 1–20 characters")
        }
        // Same rule as the server (contracts/api.md, #120): a known id is kept, anything else is random.
        let avatarId = avatarId.flatMap { AvatarCatalog.ids.contains($0) ? $0 : nil }
            ?? String(format: "avatar_%02d", Int.random(in: 1...12))
        profile = DeviceProfile(
            deviceId: mode == .guardian ? Self.guardianProfile.deviceId : Self.protectedProfile.deviceId,
            name: trimmed, avatarId: avatarId, mode: mode, language: profile.language,
            guardian: mode == .guardian ? nil : profile.guardian
        )
        return DeviceRegistration(deviceId: profile.deviceId, token: "mock-\(UUID().uuidString)", avatarId: avatarId)
    }

    func me() async throws -> DeviceProfile {
        try await pause()
        return profile
    }

    func updateMe(_ update: DeviceUpdate) async throws {
        try await pause()
        // Validate everything first: a rejected update changes nothing.
        let trimmed = update.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !(1...20).contains(trimmed.count) {
            throw RepositoryError.api(.invalidBody, message: "name must be 1–20 characters")
        }
        if let language = update.language, !["en", "id"].contains(language) {
            throw RepositoryError.api(.invalidBody, message: "language must be en or id")
        }
        if let avatarId = update.avatarId, !AvatarCatalog.ids.contains(avatarId) {
            throw RepositoryError.api(.invalidBody, message: "avatarId must be avatar_01…avatar_12")
        }
        if let trimmed { profile.name = trimmed }
        if let language = update.language { profile.language = language }
        if let avatarId = update.avatarId { profile.avatarId = avatarId }
        if let timeZone = update.timeZone { profile.timeZone = timeZone }
        if let n = update.notifications { profile.notifications = (profile.notifications ?? .defaults).applying(n) }
    }

    // MARK: Family

    func createFamilyCode(refresh: Bool) async throws -> FamilyCode {
        try await pause()
        try require(.guardian)
        // Same code while more than 5 min is left, like the server (contracts/api.md).
        if !refresh, let familyCode, familyCode.expiresAt.timeIntervalSince(now()) > 5 * 60 { return familyCode }
        let code = String(format: "%06d", Int.random(in: 100_000...599_999))
        let fresh = FamilyCode(
            code: code,
            expiresAt: now().addingTimeInterval(30 * 60),
            inviteUrl: URL(string: "https://shoo-api.afindo-mi01.workers.dev/j/\(code)")!
        )
        familyCode = fresh
        return fresh
    }

    func joinFamily(code: String) async throws -> GuardianInfo {
        try await pause()
        try require(.protected)
        switch code {
        case "000000": throw RepositoryError.api(.codeInvalid, message: "No family uses this code")
        case "999999": throw RepositoryError.api(.codeExpired, message: "Code expired")
        case "888888": throw RepositoryError.api(.familyFull, message: "Guardian already has 3 members")
        case "777777": throw RepositoryError.api(.tooManyAttempts, message: "Too many attempts")
        case "666666": throw RepositoryError.api(.alreadyConnected, message: "Already connected")
        default: break
        }
        guard DeepLink.isCode(code) else {
            throw RepositoryError.api(.codeInvalid, message: "Code must be 6 digits")
        }
        guard profile.guardian == nil else {
            throw RepositoryError.api(.alreadyConnected, message: "Already connected")
        }
        let guardian = Self.fixtureGuardian
        profile.guardian = guardian
        return guardian
    }

    /// Another family's guardian, for "Punya kode undangan?".
    static let otherGuardian = GuardianInfo(deviceId: "dev_budi", name: "Budi", avatarId: "avatar_04")

    func becomeProtected(code: String) async throws -> ProtectedSwitch {
        try await pause()
        try require(.guardian)
        guard members.isEmpty else {
            throw RepositoryError.api(.hasMembers, message: "Disconnect the people you protect first")
        }
        switch code {
        case "000000": throw RepositoryError.api(.codeInvalid, message: "No family uses this code")
        case "999999": throw RepositoryError.api(.codeExpired, message: "Code expired")
        case "888888": throw RepositoryError.api(.familyFull, message: "Guardian already has 3 members")
        default: break
        }
        guard DeepLink.isCode(code) else {
            throw RepositoryError.api(.codeInvalid, message: "Code must be 6 digits")
        }
        profile.deviceId = Self.protectedProfile.deviceId
        profile.mode = .protected
        profile.guardian = Self.otherGuardian
        return ProtectedSwitch(
            deviceId: profile.deviceId, token: "mock-\(UUID().uuidString)", avatarId: profile.avatarId, guardian: Self.otherGuardian
        )
    }

    func familyMembers() async throws -> [FamilyMember] {
        try await pause()
        try require(.guardian)
        return members
    }

    func removeMember(deviceId: String) async throws {
        try await pause()
        try require(.guardian)
        guard members.contains(where: { $0.deviceId == deviceId }) else {
            throw RepositoryError.api(.notFound, message: "Not your member")
        }
        members.removeAll { $0.deviceId == deviceId }
    }

    func deleteMe() async throws {
        try await pause()
        let me = profile.deviceId
        allScans.removeAll { $0.ownerDeviceId == me }
        members = []
        profile.guardian = nil
    }

    func setMemberNotify(deviceId: String, notify: Bool) async throws {
        try await pause()
        try require(.guardian)
        guard let index = members.firstIndex(where: { $0.deviceId == deviceId }) else {
            throw RepositoryError.api(.notFound, message: "Not your member")
        }
        members[index].notify = notify
    }

    func remindMember(deviceId: String) async throws {
        try await pause()
        try require(.guardian)
        guard let index = members.firstIndex(where: { $0.deviceId == deviceId }) else {
            throw RepositoryError.api(.notFound, message: "Not your member")
        }
        if let last = members[index].remindedAt, now().timeIntervalSince(last) < 6 * 3600 {
            throw RepositoryError.api(.remindTooSoon, message: "Already reminded recently")
        }
        members[index].remindedAt = now()
    }

    func leaveGuardian() async throws {
        try await pause()
        try require(.protected)
        guard profile.guardian != nil else {
            throw RepositoryError.api(.notFound, message: "No guardian")
        }
        profile.guardian = nil
    }

    // MARK: Scans

    func scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?) async throws -> ScanPage {
        try await pause()
        let owners = try visibleOwners(for: owner)
        let matching = allScans
            .filter { owners.contains($0.ownerDeviceId) && (status == nil || $0.status == status) }
            // Tie-break on id so the index cursor never skips or repeats an item.
            .sorted { ($0.detectedAt, $0.id) > ($1.detectedAt, $1.id) }
        let start = cursor.flatMap(Int.init) ?? 0
        guard start >= 0, start <= matching.count else {
            throw RepositoryError.api(.invalidBody, message: "Bad cursor")
        }
        let end = min(start + pageSize, matching.count)
        // Lists never carry a screenshot URL (contracts/api.md).
        let items = matching[start..<end].map { scan -> ScanResult in
            var copy = scan
            copy.screenshotUrl = nil
            return copy
        }
        return ScanPage(items: items, nextCursor: end < matching.count ? String(end) : nil)
    }

    func scan(id: String) async throws -> ScanResult {
        try await pause()
        guard let scan = allScans.first(where: { $0.id == id }),
              try visibleOwners(for: profile.mode == .guardian ? .family : .me).contains(scan.ownerDeviceId)
        else {
            throw RepositoryError.api(.notFound, message: "Scan not found")
        }
        guard pageCopies, scan.screenshotUrl != nil else { return scan }
        var copy = scan
        copy.pageReplicaUrl = Self.fixtureReplicaURL(scanId: scan.id)
        return copy
    }

    func setVerdict(scanId: String, value: Verdict.Value) async throws -> Verdict {
        try await pause()
        guard profile.mode == .guardian else {
            throw RepositoryError.api(.verdictNotAllowed, message: "Only the guardian decides")
        }
        guard let scan = allScans.first(where: { $0.id == scanId }),
              try visibleOwners(for: .family).contains(scan.ownerDeviceId)
        else {
            throw RepositoryError.api(.notFound, message: "Scan not found")
        }
        // GD-07: warning and blocked alike (Figma 416:9469, backend #191); a new verdict replaces the old.
        let verdict = Verdict(value: value, byDeviceId: profile.deviceId, byName: profile.name, decidedAt: now())
        // A verdict applies to the scan's domain for that owner (contracts/api.md).
        for index in allScans.indices
        where allScans[index].domain == scan.domain
            && allScans[index].ownerDeviceId == scan.ownerDeviceId {
            allScans[index].verdict = verdict
        }
        return verdict
    }

    // MARK: Helpers

    private func visibleOwners(for filter: ScanOwnerFilter) throws -> Set<String> {
        let me = profile.deviceId
        // Only current members: a removed member's scans are gone from the guardian's view.
        let family = Set([me] + members.map(\.deviceId))
        switch filter {
        case .me:
            return [me]
        case .family:
            guard profile.mode == .guardian else {
                throw RepositoryError.api(.forbidden, message: "Guardian only")
            }
            return family
        case .device(let id):
            guard profile.mode == .guardian, family.contains(id) else {
                throw RepositoryError.api(.notFound, message: "Unknown device")
            }
            return [id]
        }
    }

    private func require(_ mode: UserMode) throws {
        guard profile.mode == mode else {
            throw RepositoryError.api(.forbidden, message: "Wrong mode")
        }
    }

    private func pause() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ name: String, bundle: Bundle) -> T? {
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            Log.data.error("Missing fixture", name)
            return nil
        }
        do {
            return try JSONDecoder.shoo.decode(type, from: data)
        } catch {
            Log.data.error("Bad fixture", name)
            return nil
        }
    }
}
