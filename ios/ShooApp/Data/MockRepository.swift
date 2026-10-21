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
    }

    /// Fixture identities. `dev_me` is the guardian in contracts/fixtures (verdicts "by Adhella").
    static let guardianProfile = DeviceProfile(
        deviceId: "dev_me", name: "Adhella", avatarId: "avatar_01", mode: .guardian, language: "en", guardian: nil
    )
    static let fixtureGuardian = GuardianInfo(deviceId: "dev_me", name: "Adhella", avatarId: "avatar_01")
    static let protectedProfile = DeviceProfile(
        deviceId: "dev_mom", name: "Mom", avatarId: "avatar_03", mode: .protected, language: "en",
        guardian: fixtureGuardian
    )
    static let pageSize = 20

    private var profile: DeviceProfile
    private var allScans: [ScanResult]
    private var members: [FamilyMember]
    nonisolated let scenario: Scenario
    nonisolated let latency: Duration
    nonisolated let pageSize: Int
    private nonisolated let bundle: Bundle
    private nonisolated let now: @Sendable () -> Date

    init(
        mode: UserMode = .guardian,
        scenario: Scenario = .standard,
        latency: Duration = .milliseconds(300),
        pageSize: Int = MockRepository.pageSize,
        bundle: Bundle = .main,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        profile = mode == .guardian ? Self.guardianProfile : Self.protectedProfile
        self.scenario = scenario
        self.latency = latency
        self.pageSize = pageSize
        self.bundle = bundle
        self.now = now
        switch scenario {
        case .standard:
            allScans = Self.load(ScanPage.self, "activity-family", bundle: bundle)?.items ?? []
            members = Self.load(FamilyMembersResponse.self, "family-members", bundle: bundle)?.members ?? []
        case .empty:
            allScans = []
            members = []
        }
    }

    // MARK: Devices

    func registerDevice(name: String, mode: UserMode, apnsToken: String?) async throws -> DeviceRegistration {
        try await pause()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...20).contains(trimmed.count) else {
            throw RepositoryError.api(.invalidBody, message: "name must be 1–20 characters")
        }
        let avatarId = String(format: "avatar_%02d", Int.random(in: 1...12))
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
        if let trimmed { profile.name = trimmed }
        if let language = update.language { profile.language = language }
    }

    // MARK: Family

    func createFamilyCode() async throws -> FamilyCode {
        try await pause()
        try require(.guardian)
        let code = String(format: "%04d", Int.random(in: 1000...5999))
        return FamilyCode(
            code: code,
            expiresAt: now().addingTimeInterval(60),
            inviteUrl: URL(string: "https://shoo.example/join?code=\(code)")!
        )
    }

    func joinFamily(code: String) async throws -> GuardianInfo {
        try await pause()
        try require(.protected)
        switch code {
        case "0000": throw RepositoryError.api(.codeInvalid, message: "No family uses this code")
        case "9999": throw RepositoryError.api(.codeExpired, message: "Code expired")
        case "8888": throw RepositoryError.api(.familyFull, message: "Guardian already has 3 members")
        case "7777": throw RepositoryError.api(.tooManyAttempts, message: "Too many attempts")
        case "6666": throw RepositoryError.api(.alreadyConnected, message: "Already connected")
        default: break
        }
        guard code.count == 4, code.allSatisfy(\.isASCII), code.allSatisfy(\.isNumber) else {
            throw RepositoryError.api(.codeInvalid, message: "Code must be 4 digits")
        }
        guard profile.guardian == nil else {
            throw RepositoryError.api(.alreadyConnected, message: "Already connected")
        }
        let guardian = Self.fixtureGuardian
        profile.guardian = guardian
        return guardian
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
        return scan
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
        guard scan.status == .blocked else {
            throw RepositoryError.api(.verdictNotAllowed, message: "Only blocked scans take a verdict")
        }
        let verdict = Verdict(value: value, byDeviceId: profile.deviceId, byName: profile.name, decidedAt: now())
        // A verdict applies to the scan's domain for that owner (contracts/api.md).
        for index in allScans.indices
        where allScans[index].domain == scan.domain
            && allScans[index].ownerDeviceId == scan.ownerDeviceId
            && allScans[index].status == .blocked {
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
