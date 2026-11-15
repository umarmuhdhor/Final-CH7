import UIKit
import WebKit

/// One picture of part of the page copy, and the marks that touch it.
struct PagePicture {
    let image: UIImage
    /// Width of the page in CSS px, so `marks` land on the image.
    let cssWidth: CGFloat
    /// The meta's marks, moved to CSS px from the top of `image`; marks outside it are dropped.
    let marks: [ReplicaMark]

    /// Where `signalId` sits on this picture, in page CSS px from its top.
    func highlights(for signalId: String) -> [CGRect] {
        marks.filter { $0.signalId == signalId }.map(\.rect)
    }
}

/// The page copy as the Detail cards draw it: one picture of the locked replica around `focusY`, plus a
/// small picture for each card whose marks fell outside it (DT-04: a reason far down the page still shows
/// where it is). It lives in memory only while Detail is open (SECURITY §3 P9, P13); the HTML is dropped
/// once drawn.
struct PageCopy {
    let image: UIImage
    let meta: ReplicaMeta?
    /// Width of the page in CSS px, so `marks` land on the image.
    let cssWidth: CGFloat
    /// The meta's marks, moved to CSS px from the top of `image`; marks outside it are dropped.
    let marks: [ReplicaMark]
    /// Signal id → its own picture, only for signals with no mark on `image`.
    var crops: [String: PagePicture] = [:]

    /// The main picture.
    var main: PagePicture { PagePicture(image: image, cssWidth: cssWidth, marks: marks) }

    /// The picture for one reason card: its own crop when it has one, else the main picture.
    func picture(for signalId: String) -> PagePicture { crops[signalId] ?? main }
}

/// Draws the replica once in a hidden `LockedWebView` and keeps only pictures of it (fase 18b).
/// The pictures serve every evidence card and the full screen view: no live web view stays on screen,
/// so there is no form control to focus and nothing to select or share (K12).
@MainActor
enum ReplicaSnapshot {
    /// Same width as the iPhone the extension copied from, so the page lays out as it did there.
    static let renderWidth: CGFloat = 390
    /// Most of the page we keep, in view points, around the focus (fase 22 K7 a).
    nonisolated static let windowHeight: CGFloat = 1800
    /// How much of the page above the focus stays in the picture.
    nonisolated static let leadIn: CGFloat = 600
    /// Picture width in points (× screen scale in pixels): the full `renderWidth`, so the 270 pt card and
    /// the full screen view (up to 440 pt) are sharp. At 3× a full window is 1170 × 5400 px (≈ 25 MB),
    /// held only while Detail is open (fase 22 K7 a).
    static let imageWidth: CGFloat = renderWidth
    /// `didFinish` never came: show the placeholder instead of waiting forever.
    static let loadTimeout: Duration = .seconds(10)
    /// A page that stalls the content process must not keep the hidden view in the window.
    static let snapshotTimeout: Duration = .seconds(5)
    /// Time for the newly shown tiles after the frame grows.
    static let paintDelay: Duration = .milliseconds(300)
    /// A card whose marks are all outside the main window gets its own picture this tall (view points),
    /// at 3× 1170 × 2100 px (≈ 10 MB). At most `maxCrops` of them: Detail shows 3 reasons.
    nonisolated static let cropHeight: CGFloat = 700
    /// How much of the page above the mark stays in a crop, so the reader sees what leads to it.
    nonisolated static let cropLeadIn: CGFloat = 220
    nonisolated static let maxCrops = 3

    /// Why `render` gave `nil` (fase 23a, flake F2): the stage, never the page or its address.
    enum RenderFailure: Error, Equatable {
        /// Detail closed or a new link: normal.
        case cancelled
        /// No `didFinish` within `loadTimeout`, a load error, or a dead content process.
        case load
        /// The page has no size to place the window on.
        case place
        /// No picture within `snapshotTimeout`.
        case snapshot
    }

    /// `lockedHTML` must come from `ReplicaHTML.locked(_:)`. `nil` when WebKit can't draw it, or when the
    /// task is cancelled (Detail closed, new link): the hidden view leaves the window at once then.
    /// `wanted`: signal ids of the reason cards that point at the page; each one whose marks miss the main
    /// picture gets its own crop.
    static func render(
        _ lockedHTML: String, meta: ReplicaMeta?, wanted: [String] = [], ruleList: WKContentRuleList,
        in window: UIWindow
    ) async -> PageCopy? {
        switch await attempt(lockedHTML, meta: meta, wanted: wanted, ruleList: ruleList, in: window) {
        case .success(let copy): return copy
        case .failure(.cancelled): Log.replica.info("Replica snapshot nil: cancelled")
        case .failure(.load): Log.replica.error("Replica snapshot nil: load")
        case .failure(.place): Log.replica.error("Replica snapshot nil: place")
        case .failure(.snapshot): Log.replica.error("Replica snapshot nil: snapshot")
        }
        return nil
    }

    /// `render`, with the stage that failed.
    static func attempt(
        _ lockedHTML: String, meta: ReplicaMeta?, wanted: [String] = [], ruleList: WKContentRuleList,
        in window: UIWindow
    ) async -> Result<PageCopy, RenderFailure> {
        let controller = ReplicaWebController(ruleList: ruleList)
        let webView = controller.webView
        // In the window (WebKit only paints views in one), outside its bounds, never seen or read out.
        webView.frame = CGRect(x: -renderWidth * 2, y: 0, width: renderWidth, height: 844)
        webView.isUserInteractionEnabled = false
        webView.accessibilityElementsHidden = true
        webView.scrollView.isScrollEnabled = false
        window.addSubview(webView)
        defer {
            controller.onFinish = nil
            controller.onFailure = nil
            webView.stopLoading()
            webView.removeFromSuperview()
        }

        let loaded = await finished(controller, html: lockedHTML)
        guard !Task.isCancelled else { return .failure(.cancelled) }
        guard loaded else { return .failure(.load) }
        await controller.waitForLayout()
        guard !Task.isCancelled else { return .failure(.cancelled) }

        let allMarks = meta?.marks ?? []
        let main: PagePicture
        switch await picture(
            of: controller, focusY: meta?.focusY ?? 0, height: windowHeight, leadIn: leadIn, marks: allMarks
        ) {
        case .success(let picture): main = picture
        case .failure(let failure): return .failure(failure)
        }

        // A reason far from the focus (urgent text in the footer) would show no mark at all: give it its own
        // picture around its first mark. A crop that fails leaves that card on the main picture.
        var crops: [String: PagePicture] = [:]
        for signalId in cropSignals(wanted: wanted, marks: allMarks, kept: main.marks) {
            guard let first = allMarks.first(where: { $0.signalId == signalId }) else { continue }
            switch await picture(
                of: controller, focusY: Double(first.rect.minY), height: cropHeight, leadIn: cropLeadIn,
                marks: allMarks
            ) {
            case .success(let picture): crops[signalId] = picture
            case .failure(.cancelled): return .failure(.cancelled)
            case .failure: Log.replica.error("Replica crop skipped")
            }
        }

        return .success(PageCopy(
            image: main.image, meta: meta, cssWidth: main.cssWidth, marks: main.marks, crops: crops
        ))
    }

    /// Signals in `wanted` (in its order) with marks on the page but none on the main picture, at most
    /// `maxCrops`.
    static func cropSignals(wanted: [String], marks: [ReplicaMark], kept: [ReplicaMark]) -> [String] {
        let onPage = Set(marks.map(\.signalId))
        let shown = Set(kept.map(\.signalId))
        var seen = Set<String>()
        return wanted
            .filter { onPage.contains($0) && !shown.contains($0) && seen.insert($0).inserted }
            .prefix(maxCrops)
            .map { $0 }
    }

    /// Places the hidden view on one part of the page and takes its picture.
    private static func picture(
        of controller: ReplicaWebController, focusY: Double, height: CGFloat, leadIn: CGFloat,
        marks: [ReplicaMark]
    ) async -> Result<PagePicture, RenderFailure> {
        let webView = controller.webView
        guard place(webView, focusY: focusY, height: height, leadIn: leadIn) else { return .failure(.place) }
        // The taller frame shows page parts WebKit has not painted yet; there is no paint-done event
        // without JS, so let the new size lay out and give the tiles a moment. Pages sized with `vh`
        // change height with the frame: place once more on the final size.
        await controller.waitForLayout()
        guard !Task.isCancelled else { return .failure(.cancelled) }
        guard place(webView, focusY: focusY, height: height, leadIn: leadIn) else { return .failure(.place) }
        do { try await Task.sleep(for: paintDelay) } catch { return .failure(.cancelled) }

        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(origin: .zero, size: webView.bounds.size)
        configuration.snapshotWidth = NSNumber(value: Double(imageWidth))
        configuration.afterScreenUpdates = true
        let image: UIImage? = await first(within: snapshotTimeout, otherwise: nil) { done in
            webView.takeSnapshot(with: configuration) { image, _ in done(image) }
        }
        guard !Task.isCancelled else { return .failure(.cancelled) }
        guard let image else { return .failure(.snapshot) }

        // Marks follow where the picture really starts, after WebKit clamped the offset.
        let zoom = max(webView.scrollView.zoomScale, 0.01)
        let topCSS = webView.scrollView.contentOffset.y / zoom
        return .success(PagePicture(
            image: image,
            cssWidth: renderWidth / zoom,
            marks: shifted(marks, topCSS: topCSS, heightCSS: webView.bounds.height / zoom)
        ))
    }

    /// Sizes the view to the kept part and scrolls to it. `false` for an empty page.
    private static func place(_ webView: WKWebView, focusY: Double, height: CGFloat, leadIn: CGFloat) -> Bool {
        let scrollView = webView.scrollView
        let contentHeight = scrollView.contentSize.height
        guard contentHeight > 0 else { return false }
        let kept = window(
            focusY: focusY, zoom: max(scrollView.zoomScale, 0.01), contentHeight: contentHeight,
            height: height, leadIn: leadIn
        )
        webView.frame.size.height = kept.height
        scrollView.contentOffset = CGPoint(x: 0, y: kept.top)
        webView.layoutIfNeeded()
        return true
    }

    /// The part of the page we keep, in view points: `leadIn` above the focus, inside the page.
    static func window(
        focusY: Double, zoom: CGFloat, contentHeight: CGFloat, height windowHeight: CGFloat = windowHeight,
        leadIn: CGFloat = leadIn
    ) -> (top: CGFloat, height: CGFloat) {
        let height = min(windowHeight, contentHeight)
        let focus = focusY.isFinite ? CGFloat(max(0, focusY)) * zoom : 0
        let top = min(max(0, focus - leadIn), contentHeight - height)
        return (top, height)
    }

    /// Marks that touch the kept part, measured from its top.
    static func shifted(_ marks: [ReplicaMark], topCSS: CGFloat, heightCSS: CGFloat) -> [ReplicaMark] {
        marks.compactMap { mark in
            guard mark.rect.maxY > topCSS, mark.rect.minY < topCSS + heightCSS else { return nil }
            return ReplicaMark(signalId: mark.signalId, rect: mark.rect.offsetBy(dx: 0, dy: -topCSS))
        }
    }

    /// The window the Detail screen is in, for `render(_:meta:ruleList:in:)`. Opened from a push on a cold
    /// start, no window may be key yet and the scene may still be `.foregroundInactive`: then the first
    /// window of the active scene, else of any scene on screen.
    static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first { $0.isKeyWindow }
            ?? scenes.first { $0.activationState == .foregroundActive }?.windows.first
            ?? scenes.first { $0.activationState == .foregroundInactive }?.windows.first
    }

    /// `true` on `didFinish`; `false` on failure, a dead content process, or `loadTimeout`.
    private static func finished(_ controller: ReplicaWebController, html: String) async -> Bool {
        await first(within: loadTimeout, otherwise: false) { done in
            controller.onFinish = { done(true) }
            controller.onFailure = { done(false) }
            controller.load(html)
        }
    }

    /// The first answer `start` gives, or `fallback` after `timeout` or when the task is cancelled.
    /// Later answers are ignored, and the timer stops with the first one.
    private static func first<T: Sendable>(
        within timeout: Duration, otherwise fallback: T, _ start: (@escaping (T) -> Void) -> Void
    ) async -> T {
        let race = Race(fallback: fallback)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.begin(continuation, timeout: timeout, start: start)
            }
        } onCancel: {
            Task { @MainActor in race.cancel() }
        }
    }
}

/// One answer for `ReplicaSnapshot.first`: whichever of the callback, the timer or cancellation comes first.
@MainActor
private final class Race<T: Sendable> {
    private let fallback: T
    private var continuation: CheckedContinuation<T, Never>?
    private var timer: Task<Void, Never>?
    private var cancelled = false

    init(fallback: T) { self.fallback = fallback }

    func begin(_ continuation: CheckedContinuation<T, Never>, timeout: Duration, start: (@escaping (T) -> Void) -> Void) {
        guard !cancelled, !Task.isCancelled else {
            continuation.resume(returning: fallback)
            return
        }
        self.continuation = continuation
        start { [weak self] value in self?.finish(value) }
        guard self.continuation != nil else { return }
        timer = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(nil)
        }
    }

    func cancel() {
        cancelled = true
        finish(nil)
    }

    /// `nil` means the fallback.
    private func finish(_ value: T?) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.cancel()
        continuation.resume(returning: value ?? fallback)
    }
}
