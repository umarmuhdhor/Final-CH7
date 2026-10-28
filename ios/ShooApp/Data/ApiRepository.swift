import Foundation

/// `ShooRepository` against the real backend (contracts/api.md). Replaces `MockRepository` in Fase C;
/// views don't change. Keeps `SessionStore` in step with the server, so the extension sees the same
/// name and guardian as the app (contracts/app-group-keys.md).
final class ApiRepository: ShooRepository {
    private let client: APIClient
    private let session: SessionStore

    init(client: APIClient, session: SessionStore) {
        self.client = client
        self.session = session
    }

    // MARK: Devices

    func registerDevice(name: String, mode: UserMode, apnsToken: String?) async throws -> DeviceRegistration {
        struct Body: Encodable, Sendable {
            var name: String
            var mode: UserMode
            var apnsToken: String?
        }
        // The caller saves the session (`AppEnvironment.register`): it knows the name and mode chosen.
        return try await client.send(.init(
            method: .post, path: ["devices"], body: Body(name: name, mode: mode, apnsToken: apnsToken), authorized: false
        ))
    }

    func me() async throws -> DeviceProfile {
        let profile: DeviceProfile = try await client.send(.init(method: .get, path: ["devices", "me"]))
        session.updateName(profile.name)
        // `guardian: null` = never joined, left, or removed by the guardian (D-alief-21).
        session.setGuardian(profile.mode == .protected ? profile.guardian : nil)
        return profile
    }

    func updateMe(_ update: DeviceUpdate) async throws {
        let _: OkResponse = try await client.send(.init(method: .patch, path: ["devices", "me"], body: update))
        if let name = update.name { session.updateName(name) }
    }

    func deleteMe() async throws {
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
        // No body for the usual case (allowed by the contract): the server hands out the active code.
        return try await client.send(.init(method: .post, path: ["family", "code"], body: refresh ? Body(refresh: true) : nil))
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
        struct Body: Encodable, Sendable {
            var scanId: String
            var value: Verdict.Value
        }
        let response: VerdictResponse = try await client.send(.init(
            method: .post, path: ["verdicts"], body: Body(scanId: scanId, value: value)
        ))
        return response.verdict
    }
}
