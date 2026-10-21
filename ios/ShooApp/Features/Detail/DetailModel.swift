import Foundation
import Observation

/// State of the Detail screen (DT-01..06, GD-07). Every source opens it by scan id:
/// Activity, the Shield card, and push in fase 15.
@MainActor
@Observable
final class DetailModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        /// Deleted (14-day retention), disconnected, or never ours: `GET /scans/{id}` answers 404.
        case notFound
        case failed
    }

    let scanId: String
    private(set) var state: LoadState = .loading
    private(set) var scan: ScanResult?
    /// The device looking at the scan (`GET /devices/me`).
    private(set) var viewer: DeviceProfile?
    private(set) var isSubmittingVerdict = false
    /// The last verdict did not reach the server and was rolled back.
    private(set) var verdictFailed = false

    @ObservationIgnored private let repository: any ShooRepository
    @ObservationIgnored private let now: () -> Date

    init(scanId: String, repository: any ShooRepository, now: @escaping () -> Date = Date.init) {
        self.scanId = scanId
        self.repository = repository
        self.now = now
    }

    // MARK: Derived

    /// DT-02: Warning / Blocked / Verified scam / Marked safe.
    var badge: ScanBadge? { scan.map(ScanBadge.init(scan:)) }

    var isOwnScan: Bool {
        guard let scan, let viewer else { return false }
        return scan.ownerDeviceId == viewer.deviceId
    }

    /// DT-05 / GD-07: only a Guardian, only blocked items (contracts/api.md `verdict_not_allowed`).
    /// The repository only returns the guardian's own scans and their protected members'.
    var canValidate: Bool {
        viewer?.mode == .guardian && scan?.status == .blocked
    }

    /// DT-03: the owner's name is for the guardian's family view, never for Protected.
    func showsOwner(familyModeOn: Bool) -> Bool {
        guard viewer?.mode == .guardian, scan != nil else { return false }
        return familyModeOn || !isOwnScan
    }

    /// DT-04: 1–3 signals, heaviest first, in the viewer's wording.
    func evidence(language: AppLanguage) -> [Evidence] {
        guard let scan, let mode = viewer?.mode else { return [] }
        return Evidence.top(scan.signals, mode: mode, language: language)
    }

    /// DT-06: "Verified scam by Adhella" / "Marked safe by you".
    func verdictNote(language: AppLanguage) -> String? {
        guard let verdict = scan?.verdict else { return nil }
        return VerdictNote.text(for: verdict, viewerDeviceId: viewer?.deviceId, language: language)
    }

    // MARK: Actions

    func load() async {
        if scan == nil { state = .loading }
        do {
            async let scan = repository.scan(id: scanId)
            async let viewer = repository.me()
            (self.scan, self.viewer) = try await (scan, viewer)
            state = .loaded
        } catch RepositoryError.api(.notFound, _) {
            scan = nil
            state = .notFound
        } catch is CancellationError {
            // The screen went away; keep whatever is shown.
        } catch {
            Log.ui.error("Detail load failed", error)
            if scan == nil { state = .failed }
        }
    }

    /// GD-07: applies at once, no confirmation. Optimistic; rolled back if the server says no.
    func setVerdict(_ value: Verdict.Value) async {
        guard canValidate, !isSubmittingVerdict, let viewer, let previous = scan else { return }
        isSubmittingVerdict = true
        verdictFailed = false
        scan?.verdict = Verdict(value: value, byDeviceId: viewer.deviceId, byName: viewer.name, decidedAt: now())
        defer { isSubmittingVerdict = false }
        do {
            let verdict = try await repository.setVerdict(scanId: previous.id, value: value)
            scan?.verdict = verdict
        } catch {
            Log.ui.error("Verdict failed", error)
            scan?.verdict = previous.verdict
            verdictFailed = true
        }
    }
}
