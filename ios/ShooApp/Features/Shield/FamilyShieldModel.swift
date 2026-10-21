import Foundation
import Observation

extension FamilyMember {
    /// "Not connected" only when the server says the extension is off (D-alief-15/24):
    /// it never sends `false` without evidence, so an unknown state still counts as connected.
    var isConnected: Bool { extensionActive }
}

/// Guardian's Family mode (GD-03): the people they look after, each with their newest risky site.
@MainActor
@Observable
final class FamilyShieldModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed
    }

    /// At most 3 people are shown (PRD GD-03).
    static let maxMembers = 3

    private(set) var state: State = .loading
    private(set) var members: [FamilyMember] = []
    /// Newest scan id per member, so a card can open Detail (`lastScan` in the contract has no id).
    private var lastScanIds: [String: String] = [:]

    @ObservationIgnored private let repository: any ShooRepository
    @ObservationIgnored private var generation = 0

    init(repository: any ShooRepository) {
        self.repository = repository
    }

    var isEmpty: Bool { state == .loaded && members.isEmpty }

    func lastScanId(for deviceId: String) -> String? {
        lastScanIds[deviceId]
    }

    /// On appear, on foreground, and on pull to refresh. A failed refresh keeps what is shown (D-alief-A12).
    func refresh() async {
        generation += 1
        let request = generation
        do {
            let family = Array(try await repository.familyMembers().prefix(Self.maxMembers))
            let ids = try await newestScanIds(for: family)
            guard request == generation else { return }
            members = family
            lastScanIds = ids
            state = .loaded
        } catch {
            guard request == generation, !error.isCancellation else { return }
            Log.ui.error("Family load failed", error)
            if state != .loaded { state = .failed }
        }
    }

    func retry() async {
        state = .loading
        await refresh()
    }

    private func newestScanIds(for family: [FamilyMember]) async throws -> [String: String] {
        let repository = repository
        return try await withThrowingTaskGroup(of: (String, String?).self) { group in
            for member in family where member.lastScan != nil {
                group.addTask {
                    let page = try await repository.scans(owner: .device(member.deviceId), status: nil, cursor: nil)
                    return (member.deviceId, page.items.first?.id)
                }
            }
            var ids: [String: String] = [:]
            for try await (deviceId, scanId) in group {
                ids[deviceId] = scanId
            }
            return ids
        }
    }
}
