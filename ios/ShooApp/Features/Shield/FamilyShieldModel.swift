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
            let ids = await newestScanIds(for: family)
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

    private func newestScanIds(for family: [FamilyMember]) async -> [String: String] {
        let repository = repository
        // One member's failure only leaves that card without a link; it never hides the family.
        return await withTaskGroup(of: (String, String?).self) { group in
            for member in family {
                guard let lastScan = member.lastScan else { continue }
                group.addTask {
                    guard let page = try? await repository.scans(owner: .device(member.deviceId), status: nil, cursor: nil) else {
                        return (member.deviceId, nil)
                    }
                    // The scan the card shows; the newest one if the list moved on meanwhile.
                    let shown = page.items.first { $0.url == lastScan.url && $0.detectedAt == lastScan.detectedAt }
                    return (member.deviceId, (shown ?? page.items.first)?.id)
                }
            }
            var ids: [String: String] = [:]
            for await (deviceId, scanId) in group {
                ids[deviceId] = scanId
            }
            return ids
        }
    }
}
