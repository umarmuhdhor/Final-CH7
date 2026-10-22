import Foundation

/// Every backend operation the app uses, shaped by contracts/api.md.
/// Fase A: `MockRepository` (fixtures). Fase C: `ApiRepository` — views never change.
protocol ShooRepository: AnyObject, Sendable {
    /// `POST /devices` (ON-02, ON-03).
    func registerDevice(name: String, mode: UserMode, apnsToken: String?) async throws -> DeviceRegistration
    /// `GET /devices/me` (PR-04, PF-01).
    func me() async throws -> DeviceProfile
    /// `PATCH /devices/me` (ON-05, PF-01, GD-03).
    func updateMe(_ update: DeviceUpdate) async throws

    /// `POST /family/code` — guardian (GD-04).
    func createFamilyCode() async throws -> FamilyCode
    /// `POST /family/join` — protected (PR-01, PR-03).
    func joinFamily(code: String) async throws -> GuardianInfo
    /// `GET /family/members` — guardian (GD-03).
    func familyMembers() async throws -> [FamilyMember]
    /// `DELETE /family/members/{deviceId}` — guardian (GD-04).
    func removeMember(deviceId: String) async throws
    /// `DELETE /family/guardian` — protected (PF-01).
    func leaveGuardian() async throws

    /// `GET /scans` newest first (PR-05, GD-05). `screenshotUrl` is always `nil` in lists.
    func scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?) async throws -> ScanPage
    /// `GET /scans/{id}` (DT-*).
    func scan(id: String) async throws -> ScanResult
    /// `POST /verdicts` — guardian, blocked scans only (GD-07).
    func setVerdict(scanId: String, value: Verdict.Value) async throws -> Verdict
}
