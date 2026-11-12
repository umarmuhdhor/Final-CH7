import Foundation
import os

/// `ShooRepository` against the real backend (contracts/api.md). Replaces `MockRepository` in Fase C;
/// views don't change. Keeps `SessionStore` in step with the server, so the extension sees the same
/// name and guardian as the app (contracts/app-group-keys.md).
final class ApiRepository: ShooRepository {
    private let client: APIClient
    private let session: SessionStore
    /// The last family code, in memory only, for the device that got it. Home, Profile and onboarding
    /// each open their own code screen; they share this one instead of each asking the server, which
    /// allows 6 asks a minute (contracts/api.md). `fetchedAt` and `endsAt` are on the phone's clock
    /// (issue #227): the server's `expiresAt` is only trusted for how long is left, at most 30 min.
    private let lastCode = OSAllocatedUnfairLock<CachedCode?>(initialState: nil)
    private let now: @Sendable () -> Date

    init(client: APIClient, session: SessionStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.session = session
        self.now = now
    }

    // MARK: Devices

    func registerDevice(name: String, mode: UserMode, avatarId: String?, apnsToken: String?) async throws -> DeviceRegistration {
        struct Body: Encodable, Sendable {
            var name: String
            var mode: UserMode
            var avatarId: String?
            var apnsToken: String?
        }
        // The caller saves the session (`AppEnvironment.register`): it knows the name and mode chosen.
        return try await client.send(.init(
            method: .post, path: ["devices"], body: Body(name: name, mode: mode, avatarId: avatarId, apnsToken: apnsToken), authorized: false
        ))
    }

    func me() async throws -> DeviceProfile {
        let usedToken = session.token
        let profile: DeviceProfile = try await client.send(.init(method: .get, path: ["devices", "me"]))
        // Written only while the token is still the one this request used: when "Punya kode undangan?" saved
        // a new device meanwhile (fase 27h, F-A12), this is the old device's profile and the App Group keeps
        // the new name and guardian. No token (locked Keychain, cleared) = nothing to write for.
        // `guardian: null` = never joined, left, or removed by the guardian (D-alief-21).
        if let usedToken {
            session.applyProfile(
                name: profile.name, guardian: profile.mode == .protected ? profile.guardian : nil, ifToken: usedToken
            )
        }
        return profile
    }

    func updateMe(_ update: DeviceUpdate) async throws {
        let _: OkResponse = try await client.send(.init(method: .patch, path: ["devices", "me"], body: update))
        if let name = update.name { session.updateName(name) }
    }

    func becomeProtected(code: String) async throws -> ProtectedSwitch {
        struct Body: Encodable, Sendable { var code: String }
        // The caller saves the new session (`AppEnvironment.becomeProtected`), then the guardian.
        lastCode.withLock { $0 = nil }
        return try await client.send(.init(method: .post, path: ["devices", "me", "protected"], body: Body(code: code)))
    }

    func deleteMe() async throws {
        lastCode.withLock { $0 = nil }
        do {
            let _: OkResponse = try await client.send(.init(
                method: .delete, path: ["devices", "me"], reportsUnauthorized: false
            ))
        } catch let error as RepositoryError where [.notFound, .unauthorized].contains(error.apiCode) {
            // Already gone (an earlier answer got lost): the session goes too, then the caller decides.
            session.clear()
            throw error
        }
        session.clear()
    }

    // MARK: Family

    func createFamilyCode(refresh: Bool) async throws -> FamilyCode {
        struct Body: Encodable, Sendable { var refresh: Bool }
        let deviceId = session.deviceId
        // The server would hand back this same code while more than 5 min is left (contracts/api.md).
        if !refresh, let deviceId, let cached = lastCode.withLock({ $0 }), cached.deviceId == deviceId,
           cached.isReusable(at: now()) {
            return cached.code
        }
        // No body for the usual case (allowed by the contract): the server hands out the active code.
        let code: FamilyCode = try await client.send(.init(method: .post, path: ["family", "code"], body: refresh ? Body(refresh: true) : nil))
        let cached = deviceId.map { CachedCode(deviceId: $0, code: code, fetchedAt: now()) }
        lastCode.withLock { $0 = cached }
        return code
    }

    /// Same as the server's `REUSE_MIN_SECONDS` (checked by backend/api/test/family-code-sync.test.ts).
    nonisolated static let codeReuseSeconds: TimeInterval = 5 * 60

    struct CachedCode: Sendable {
        var deviceId: String
        var code: FamilyCode
        var fetchedAt: Date
        /// `fetchedAt` + what the server says is left, clamped to 0…30 min: a phone clock behind the
        /// server's never stretches it, one ahead makes it 0 (asks the server again).
        var endsAt: Date {
            fetchedAt.addingTimeInterval(min(max(code.expiresAt.timeIntervalSince(fetchedAt), 0), FamilyCodeModel.codeLifetime))
        }

        /// More than 5 min left, and the clock was not set back since the code came.
        func isReusable(at now: Date) -> Bool {
            now >= fetchedAt && endsAt.timeIntervalSince(now) > ApiRepository.codeReuseSeconds
        }
    }

    func joinFamily(code: String) async throws -> GuardianInfo {
        struct Body: Encodable, Sendable { var code: String }
        let response: JoinResponse = try await client.send(.init(
            method: .post, path: ["family", "join"], body: Body(code: code)
        ))
        session.setGuardian(response.guardian)
        return response.guardian
    }

    func familyMembers() async throws -> [FamilyMember] {
        let response: FamilyMembersResponse = try await client.send(.init(method: .get, path: ["family", "members"]))
        return response.members
    }

    func removeMember(deviceId: String) async throws {
        // P13: their icons go from memory whatever the answer (a failed call only costs a download).
        defer { session.forgetCachedData() }
        let _: OkResponse = try await client.send(.init(method: .delete, path: ["family", "members", deviceId]))
    }

    func setMemberNotify(deviceId: String, notify: Bool) async throws {
        struct Body: Encodable, Sendable { var notify: Bool }
        let _: OkResponse = try await client.send(.init(
            method: .patch, path: ["family", "members", deviceId], body: Body(notify: notify)
        ))
    }

    func remindMember(deviceId: String) async throws {
        let _: OkResponse = try await client.send(.init(method: .post, path: ["family", "members", deviceId, "remind"]))
    }

    func leaveGuardian() async throws {
        do {
            let _: OkResponse = try await client.send(.init(method: .delete, path: ["family", "guardian"]))
        } catch let error as RepositoryError where error.apiCode == .notFound {
            // No guardian on the server any more: forget the name here too.
            session.setGuardian(nil)
            throw error
        }
        session.setGuardian(nil)
    }

    // MARK: Scans

    func scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?) async throws -> ScanPage {
        var query = [URLQueryItem(name: "owner", value: owner.queryValue)]
        if let status { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await client.send(.init(method: .get, path: ["scans"], query: query))
    }

    func scan(id: String) async throws -> ScanResult {
        try await client.send(.init(method: .get, path: ["scans", id]))
    }

    func setVerdict(scanId: String, value: Verdict.Value) async throws -> Verdict {
        try await setVerdict(scanId: scanId, value: value, notes: nil)
    }

    func setVerdict(scanId: String, value: Verdict.Value, notes: String?) async throws -> Verdict {
        struct Body: Encodable, Sendable {
            var scanId: String
            var value: Verdict.Value
            /// Left out when empty, as older builds send it.
            var notes: String?
        }
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let response: VerdictResponse = try await client.send(.init(
            method: .post, path: ["verdicts"],
            body: Body(scanId: scanId, value: value, notes: trimmed?.isEmpty == false ? trimmed : nil)
        ))
        return response.verdict
    }
}
