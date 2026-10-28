import Foundation
import Observation

/// Calls shared by Profile's family list and the member detail.
enum MemberActions {
    /// `POST /family/members/{id}/remind`: `nil` when sent, else what to tell the guardian.
    static func remind(_ member: FamilyMember, repository: any ShooRepository) async -> String.LocalizationValue? {
        do {
            try await repository.remindMember(deviceId: member.deviceId)
            return nil
        } catch RepositoryError.api(.pushUnavailable, _) {
            return "\(member.name) hasn't turned on notifications"
        } catch RepositoryError.api(.remindTooSoon, _) {
            return "You already reminded \(member.name) recently"
        } catch {
            Log.ui.error("Remind failed", error)
            return "Couldn't send. Check your connection and try again."
        }
    }
}

/// "Guardian/Detail Orang Dilindungi" (PF-01): one protected member, read from `GET /family/members`,
/// with their three newest scans, "Kabari saya" and "Putuskan koneksi".
@MainActor
@Observable
final class MemberDetailModel {
    enum State: Equatable {
        case loading
        case loaded
        /// Not (or no longer) one of my members.
        case gone
        case failed
    }

    let deviceId: String
    private(set) var state: State = .loading
    private(set) var member: FamilyMember?
    /// Newest first, at most 3 ("Aktivitas terbaru").
    private(set) var recent: [ScanResult] = []
    private(set) var recentFailed = false
    private(set) var isWorking = false
    private(set) var isReminding = false
    /// Shown as an alert.
    var actionError: String.LocalizationValue?

    @ObservationIgnored private let repository: any ShooRepository
    @ObservationIgnored private let now: () -> Date

    init(deviceId: String, repository: any ShooRepository, now: @escaping () -> Date = Date.init) {
        self.deviceId = deviceId
        self.repository = repository
        self.now = now
    }

    func load() async {
        do {
            let members = try await repository.familyMembers()
            guard let found = members.first(where: { $0.deviceId == deviceId }) else {
                state = .gone
                return
            }
            member = found
            state = .loaded
        } catch {
            guard !error.isCancellation else { return }
            Log.ui.error("Member load failed", error)
            if state != .loaded { state = .failed }
            return
        }
        do {
            recent = Array(try await repository.scans(owner: .device(deviceId), status: nil, cursor: nil).items.prefix(3))
            recentFailed = false
        } catch {
            guard !error.isCancellation else { return }
            Log.ui.error("Member activity failed", error)
            recentFailed = true
        }
    }

    /// Calendar days since the link was made, counting today.
    var daysProtected: Int? {
        guard let since = member?.connectedAt else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: since), to: calendar.startOfDay(for: now())).day ?? 0
        return max(1, days + 1)
    }

    /// "Kabari saya": optimistic, back to the old value when the server says no.
    func setNotify(_ on: Bool) async {
        guard let old = member?.notify, old != on else { return }
        member?.notify = on
        do {
            try await repository.setMemberNotify(deviceId: deviceId, notify: on)
        } catch {
            Log.ui.error("Notify change failed", error)
            member?.notify = old
            actionError = "Couldn't save. Check your connection and try again."
        }
    }

    /// The message to announce after "Ingatkan".
    func remind() async -> String.LocalizationValue? {
        guard let member, !isReminding else { return nil }
        isReminding = true
        defer { isReminding = false }
        if let problem = await MemberActions.remind(member, repository: repository) { return problem }
        self.member?.remindedAt = now()
        return "Reminder sent to \(member.name)"
    }

    /// `DELETE /family/members/{id}`; `true` when the member is gone (also when it already was).
    func disconnect() async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.removeMember(deviceId: deviceId)
        } catch RepositoryError.api(.notFound, _) {
            // Already removed (an earlier answer got lost): same end state.
        } catch {
            Log.ui.error("Disconnect member failed", error)
            actionError = "Couldn't disconnect. Check your connection and try again."
            return false
        }
        return true
    }
}
