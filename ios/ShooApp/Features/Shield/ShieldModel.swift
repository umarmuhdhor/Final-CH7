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

    init(repository: any ShooRepository, extensionStatus: @escaping () -> ExtensionStatus = ExtensionStatus.live) {
        self.repository = repository
        readExtensionStatus = extensionStatus
    }

    /// On appear and every time the app comes back to the foreground.
    func refresh() async {
        // Local and instant: never waits for the network.
        extensionStatus = readExtensionStatus()
        do {
            async let profile = repository.me()
            async let blocked = repository.scans(owner: .me, status: .blocked, cursor: nil)
            let (me, page) = try await (profile, blocked)
            guardian = me.guardian
            lastBlocked = page.items.first
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            Log.ui.error("Shield load failed", error)
            state = .failed
        }
    }

    /// "Why blocked" on the card: the one or two strongest signals in simple words.
    func reasons(for scan: ScanResult, language: AppLanguage) -> [String] {
        scan.signals
            .sorted { $0.weight > $1.weight }
            .prefix(2)
            .map { $0.labelSimple.text(for: language.code) }
    }
}

extension ExtensionStatus {
    /// The status the app shows: the App Group heartbeat. UI tests and screenshots can force
    /// Active with `-UITestExtensionActive YES` (DEBUG only, D-alief-A05).
    static func live() -> ExtensionStatus {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "UITestExtensionActive") == "YES" {
            return .active(lastSeen: Date())
        }
        #endif
        return current()
    }
}
