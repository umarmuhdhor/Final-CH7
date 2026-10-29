import CoreGraphics
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

    /// What `setVerdict` did, so the view announces and gives haptics only for real results.
    enum VerdictOutcome: Equatable {
        /// Not allowed here, or another verdict is still being sent.
        case ignored
        case saved
        /// The server said no; the previous verdict is back.
        case rolledBack
        /// The scan no longer exists (retention, disconnect, deleted data).
        case gone
    }

    let scanId: String
    private(set) var state: LoadState = .loading
    private(set) var scan: ScanResult?
    /// The device looking at the scan (`GET /devices/me`).
    private(set) var viewer: DeviceProfile?
    private(set) var isSubmittingVerdict = false
    /// The last verdict did not reach the server and was rolled back.
    private(set) var verdictFailed = false
    /// Counts verdicts the server confirmed (drives the success haptic).
    private(set) var verdictSaves = 0

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

    /// DT-05 / GD-07: only a Guardian, on warning and blocked items alike (Figma 416:9469, #190).
    /// The repository only returns the guardian's own scans and their protected members'.
    var canValidate: Bool {
        viewer?.mode == .guardian && scan != nil
    }

    /// Areas per signal on the page copy (`shoo-replica` meta `marks`, #176). Empty until the copy is shown.
    var marks: [ReplicaMark] = []
    /// Width of the copied page in CSS px (the meta's viewport), so marks land on the image.
    var pageCSSWidth: CGFloat?
    /// The owner's avatar for the chip, from the family list (best effort).
    private(set) var ownerAvatarId: String?

    /// DT-03: the owner's name is for the guardian's family view, never for Protected.
    func showsOwner(familyModeOn: Bool) -> Bool {
        guard viewer?.mode == .guardian, scan != nil else { return false }
        return familyModeOn || !isOwnScan
    }

    /// DT-04: 1–3 signals, heaviest first, in the viewer's wording.
    func evidence(language: AppLanguage) -> [Evidence] {
        guard let scan, let mode = viewer?.mode else { return [] }
        return Evidence.top(scan.signals, mode: mode, language: language, marks: marks)
    }

    /// DT-06: "Verified scam by Adhella" / "Marked safe by you".
    func verdictNote(language: AppLanguage) -> String? {
        guard let verdict = scan?.verdict else { return nil }
        return VerdictNote.text(for: verdict, viewerDeviceId: viewer?.deviceId, language: language)
    }

    // MARK: Actions

    func load() async {
        if scan == nil { state = .loading }
        screenshotLinkRefreshed = false
        let epoch = verdictEpoch
        do {
            async let fetchedScan = repository.scan(id: scanId)
            async let fetchedViewer = repository.me()
            var loadedScan = try await fetchedScan
            let loadedViewer = try await fetchedViewer
            // A verdict tapped while this load was in flight is newer than the snapshot.
            if isSubmittingVerdict || epoch != verdictEpoch, let current = scan, current.id == loadedScan.id {
                loadedScan.verdict = current.verdict
            }
            scan = loadedScan
            viewer = loadedViewer
            state = .loaded
            await loadOwnerAvatar()
        } catch RepositoryError.api(.notFound, _) {
            scan = nil
            state = .notFound
        } catch {
            // Leaving the screen cancels the load (`CancellationError`, or `URLError.cancelled` from URLSession).
            guard !Self.isCancellation(error), !Task.isCancelled else { return }
            Log.ui.error("Detail load failed", error)
            if scan == nil { state = .failed }
        }
    }

    /// Someone else's scan in the guardian's view: their avatar for the chip. Without it the chip
    /// shows the first avatar colour.
    private func loadOwnerAvatar() async {
        guard viewer?.mode == .guardian, !isOwnScan, ownerAvatarId == nil, let owner = scan?.ownerDeviceId else { return }
        ownerAvatarId = try? await repository.familyMembers().first { $0.deviceId == owner }?.avatarId
    }

    /// The screenshot link failed. It may only have expired (valid 1 h), so ask for the scan once more:
    /// that brings a fresh link, or a 404 when the scan is really gone (contracts/api.md, D-alief-C04).
    /// `true` when a new link came back.
    func refreshScreenshotLink() async -> Bool {
        guard !screenshotLinkRefreshed, let current = scan else { return false }
        screenshotLinkRefreshed = true
        do {
            let fresh = try await repository.scan(id: scanId)
            // A `load()` that finished meanwhile already brought the newest link.
            guard let link = fresh.screenshotUrl, link != current.screenshotUrl,
                  scan?.screenshotUrl == current.screenshotUrl
            else { return false }
            scan?.screenshotUrl = link
            return true
        } catch let error where error.isCancellation {
            screenshotLinkRefreshed = false
            return false
        } catch RepositoryError.api(.notFound, _) {
            scan = nil
            state = .notFound
            return false
        } catch {
            return false
        }
    }

    /// GD-07: applies at once, no confirmation. Optimistic; rolled back if the server says no.
    @discardableResult
    func setVerdict(_ value: Verdict.Value) async -> VerdictOutcome {
        guard canValidate, !isSubmittingVerdict, let viewer, let previous = scan else { return .ignored }
        isSubmittingVerdict = true
        verdictEpoch += 1
        verdictFailed = false
        scan?.verdict = Verdict(value: value, byDeviceId: viewer.deviceId, byName: viewer.name, decidedAt: now())
        defer { isSubmittingVerdict = false }
        do {
            let verdict = try await repository.setVerdict(scanId: previous.id, value: value)
            scan?.verdict = verdict
            verdictSaves += 1
            return .saved
        } catch RepositoryError.api(.notFound, _) {
            scan = nil
            state = .notFound
            return .gone
        } catch {
            Log.ui.error("Verdict failed", error)
            scan?.verdict = previous.verdict
            verdictFailed = true
            return .rolledBack
        }
    }

    @ObservationIgnored private var verdictEpoch = 0
    /// One fresh screenshot link per load; a second failure shows "isn't available".
    @ObservationIgnored private var screenshotLinkRefreshed = false

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
