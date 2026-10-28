import Foundation
@testable import Shoo

/// Every call fails like an offline device.
final class FailingRepository: ShooRepository {
    func registerDevice(name: String, mode: UserMode, avatarId: String?, apnsToken: String?) async throws -> DeviceRegistration { throw RepositoryError.network }
    func me() async throws -> DeviceProfile { throw RepositoryError.network }
    func updateMe(_ update: DeviceUpdate) async throws { throw RepositoryError.network }
    func createFamilyCode(refresh: Bool) async throws -> FamilyCode { throw RepositoryError.network }
    func joinFamily(code: String) async throws -> GuardianInfo { throw RepositoryError.network }
    func familyMembers() async throws -> [FamilyMember] { throw RepositoryError.network }
    func removeMember(deviceId: String) async throws { throw RepositoryError.network }
    func leaveGuardian() async throws { throw RepositoryError.network }
    func setMemberNotify(deviceId: String, notify: Bool) async throws { throw RepositoryError.network }
    func remindMember(deviceId: String) async throws { throw RepositoryError.network }
    func becomeProtected(code: String) async throws -> ProtectedSwitch { throw RepositoryError.network }
    func deleteMe() async throws { throw RepositoryError.network }
    func scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?) async throws -> ScanPage { throw RepositoryError.network }
    func scan(id: String) async throws -> ScanResult { throw RepositoryError.network }
    func setVerdict(scanId: String, value: Verdict.Value) async throws -> Verdict { throw RepositoryError.network }
}

/// Wraps a repository; each `scans` call waits for the next delay in the list first.
/// Lets a test make an older request answer after a newer one. Setting `failure` makes
/// `scans` and `me` throw it (a flaky network, or a cancelled URL request).
final class DelayedScansRepository: ShooRepository, @unchecked Sendable {
    private let base: any ShooRepository
    private var delays: [Duration]
    var failure: (any Error)?
    /// `updateMe` throws this.
    var updateFailure: (any Error)?
    /// `familyMembers` throws this.
    var membersFailure: (any Error)?
    /// `remindMember` throws this.
    var remindFailure: (any Error)?
    /// `setMemberNotify` throws this.
    var notifyFailure: (any Error)?
    /// Only `scans` for this owner throw `RepositoryError.network`.
    var failingOwner: ScanOwnerFilter?

    init(base: any ShooRepository, delays: [Duration] = []) {
        self.base = base
        self.delays = delays
    }

    func scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?) async throws -> ScanPage {
        let delay = delays.isEmpty ? .zero : delays.removeFirst()
        try await Task.sleep(for: delay)
        if let failure { throw failure }
        if owner == failingOwner { throw RepositoryError.network }
        return try await base.scans(owner: owner, status: status, cursor: cursor)
    }

    func registerDevice(name: String, mode: UserMode, avatarId: String?, apnsToken: String?) async throws -> DeviceRegistration {
        try await base.registerDevice(name: name, mode: mode, avatarId: avatarId, apnsToken: apnsToken)
    }
    func me() async throws -> DeviceProfile {
        if let failure { throw failure }
        return try await base.me()
    }
    func updateMe(_ update: DeviceUpdate) async throws {
        if let updateFailure { throw updateFailure }
        try await base.updateMe(update)
    }
    func createFamilyCode(refresh: Bool) async throws -> FamilyCode { try await base.createFamilyCode(refresh: refresh) }
    func joinFamily(code: String) async throws -> GuardianInfo { try await base.joinFamily(code: code) }
    func familyMembers() async throws -> [FamilyMember] {
        if let membersFailure { throw membersFailure }
        return try await base.familyMembers()
    }
    func removeMember(deviceId: String) async throws { try await base.removeMember(deviceId: deviceId) }
    func leaveGuardian() async throws { try await base.leaveGuardian() }
    func setMemberNotify(deviceId: String, notify: Bool) async throws {
        if let notifyFailure { throw notifyFailure }
        try await base.setMemberNotify(deviceId: deviceId, notify: notify)
    }
    func remindMember(deviceId: String) async throws {
        if let remindFailure { throw remindFailure }
        try await base.remindMember(deviceId: deviceId)
    }
    func becomeProtected(code: String) async throws -> ProtectedSwitch { try await base.becomeProtected(code: code) }
    func deleteMe() async throws { try await base.deleteMe() }
    func scan(id: String) async throws -> ScanResult { try await base.scan(id: id) }
    func setVerdict(scanId: String, value: Verdict.Value) async throws -> Verdict { try await base.setVerdict(scanId: scanId, value: value) }
}
