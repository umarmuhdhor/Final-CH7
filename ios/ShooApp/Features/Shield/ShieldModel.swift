import Foundation
import Observation

/// Protected Home (PR-04): extension status, the guardian, and the last blocked site.
@MainActor
@Observable
final class ShieldModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed
    }

    private(set) var state: State = .loading
    private(set) var extensionStatus: ExtensionStatus = .off(lastSeen: nil)
    /// `GET /devices/me` → `guardian`; `nil` when not (or no longer) connected.
    private(set) var guardian: GuardianInfo?
    /// Newest `blocked` scan of this device.
    private(set) var lastBlocked: ScanResult?

    @ObservationIgnored private let repository: any ShooRepository
    @ObservationIgnored private let readExtensionStatus: () -> ExtensionStatus
    @ObservationIgnored private var generation = 0

    init(repository: any ShooRepository, extensionStatus: @escaping () -> ExtensionStatus = { ExtensionStatus.current() }) {
        self.repository = repository
        readExtensionStatus = extensionStatus
    }

    /// On appear and every time the app comes back to the foreground.
    /// Overlapping calls: only the newest one is applied.
    func refresh() async {
        generation += 1
        let request = generation
        // Local and instant: never waits for the network.
        extensionStatus = readExtensionStatus()
        do {
            async let profile = repository.me()
            async let blocked = repository.scans(owner: .me, status: .blocked, cursor: nil)
            let (me, page) = try await (profile, blocked)
            guard request == generation else { return }
            guardian = me.guardian
            lastBlocked = page.items.first
            state = .loaded
        } catch {
            guard request == generation, !error.isCancellation else { return }
            Log.ui.error("Shield load failed", error)
            // A failed foreground refresh keeps what is already on screen.
            if state != .loaded { state = .failed }
        }
    }

    /// "Try again" on the error view: shows the spinner while it retries.
    func retry() async {
        state = .loading
        await refresh()
    }

    /// "Why blocked" on the card: the one or two strongest signals in simple words.
    func reasons(for scan: ScanResult, language: AppLanguage) -> [String] {
        scan.signals
            .sorted { $0.weight > $1.weight }
            .prefix(2)
            .map { $0.labelSimple.text(for: language.code) }
    }
}
