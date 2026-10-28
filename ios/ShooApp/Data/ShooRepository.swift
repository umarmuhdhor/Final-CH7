import Foundation

/// Every backend operation the app uses, shaped by contracts/api.md.
/// Fase A: `MockRepository` (fixtures). Fase C: `ApiRepository` — views never change.
protocol ShooRepository: AnyObject, Sendable {
    /// `POST /devices` (ON-02, ON-03). `avatarId` is the ON-02 pick; nil or unknown → the server picks (#120).
    func registerDevice(name: String, mode: UserMode, avatarId: String?, apnsToken: String?) async throws -> DeviceRegistration
    /// `GET /devices/me` (PR-04, PF-01).
    func me() async throws -> DeviceProfile
    /// `PATCH /devices/me` (ON-05, PF-01, GD-03).
    func updateMe(_ update: DeviceUpdate) async throws

    /// `POST /family/code` — guardian (GD-04). The active code while it has more than 5 min left;
    /// `refresh` always makes a new one and the old one stops working.
    func createFamilyCode(refresh: Bool) async throws -> FamilyCode
    /// `POST /family/join` — protected (PR-01, PR-03).
    func joinFamily(code: String) async throws -> GuardianInfo
    /// `GET /family/members` — guardian (GD-03).
    func familyMembers() async throws -> [FamilyMember]
    /// `DELETE /family/members/{deviceId}` — guardian (GD-04).
    func removeMember(deviceId: String) async throws
    /// `DELETE /family/guardian` — protected (PF-01).
    func leaveGuardian() async throws
    /// `DELETE /devices/me` (PF-01, SECURITY §3 P3, App Store 5.1.1(v)): removes the device and
    /// everything about it (family links, codes, scans + screenshots, verdicts). The token stops working.
    func deleteMe() async throws

    /// `GET /scans` newest first (PR-05, GD-05). `screenshotUrl` is always `nil` in lists.
    func scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?) async throws -> ScanPage
    /// `GET /scans/{id}` (DT-*).
    func scan(id: String) async throws -> ScanResult
    /// `POST /verdicts` — guardian, blocked scans only (GD-07).
    func setVerdict(scanId: String, value: Verdict.Value) async throws -> Verdict
}
