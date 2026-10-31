import UIKit
import WebKit

/// The page copy as the Detail cards draw it: one picture of the locked replica around `focusY`.
/// It lives in memory only while Detail is open (SECURITY §3 P9, P13); the HTML is dropped once drawn.
struct PageCopy {
    let image: UIImage
    let meta: ReplicaMeta?
    /// Width of the page in CSS px, so `marks` land on the image.
    let cssWidth: CGFloat
    /// The meta's marks, moved to CSS px from the top of `image`; marks outside it are dropped.
    let marks: [ReplicaMark]
}

/// Draws the replica once in a hidden `LockedWebView` and keeps only a picture of it (fase 18b).
/// One picture serves every evidence card and the full screen view: no live web view stays on screen,
/// so there is no form control to focus and nothing to select or share (K12).
@MainActor
enum ReplicaSnapshot {
    /// Same width as the iPhone the extension copied from, so the page lays out as it did there.
    static let renderWidth: CGFloat = 390
    /// Most of the page we keep, in view points, around the focus.
    static let windowHeight: CGFloat = 3000
    /// How much of the page above the focus stays in the picture.
    static let leadIn: CGFloat = 600
    /// Picture width in points (× screen scale in pixels): sharp on the 270 pt card. At 3× a full
    /// 3000 pt window is about 600 × 4600 px (≈ 11 MB), held only while Detail is open.
    static let imageWidth: CGFloat = 200
    /// `didFinish` never came: show the placeholder instead of waiting forever.
    static let loadTimeout: Duration = .seconds(10)
    /// A page that stalls the content process must not keep the hidden view in the window.
    static let snapshotTimeout: Duration = .seconds(5)
    /// Time for the newly shown tiles after the frame grows.
    static let paintDelay: Duration = .milliseconds(300)

    /// `lockedHTML` must come from `ReplicaHTML.locked(_:)`. `nil` when WebKit can't draw it, or when the
    /// task is cancelled (Detail closed, new link): the hidden view leaves the window at once then.
    static func render(
        _ lockedHTML: String, meta: ReplicaMeta?, ruleList: WKContentRuleList, in window: UIWindow
    ) async -> PageCopy? {
        let controller = ReplicaWebController(ruleList: ruleList, focusY: meta?.focusY ?? 0)
        controller.scrollsToFocusOnFinish = false
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

        guard await finished(controller, html: lockedHTML), !Task.isCancelled else { return nil }
        await controller.waitForLayout()
        guard !Task.isCancelled, place(webView, focusY: meta?.focusY ?? 0) else { return nil }
        // The taller frame shows page parts WebKit has not painted yet; there is no paint-done event
        // without JS, so let the new size lay out and give the tiles a moment. Pages sized with `vh`
        // change height with the frame: place once more on the final size.
        await controller.waitForLayout()
        guard !Task.isCancelled, place(webView, focusY: meta?.focusY ?? 0) else { return nil }
        do { try await Task.sleep(for: paintDelay) } catch { return nil }

        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(origin: .zero, size: webView.bounds.size)
        configuration.snapshotWidth = NSNumber(value: Double(imageWidth))
        configuration.afterScreenUpdates = true
        let image: UIImage? = await first(within: snapshotTimeout, otherwise: nil) { done in
            webView.takeSnapshot(with: configuration) { image, _ in done(image) }
        }
        guard let image, !Task.isCancelled else { return nil }

        // Marks follow where the picture really starts, after WebKit clamped the offset.
        let zoom = max(webView.scrollView.zoomScale, 0.01)
        let topCSS = webView.scrollView.contentOffset.y / zoom
        return PageCopy(
            image: image,
            meta: meta,
            cssWidth: renderWidth / zoom,
            marks: shifted(meta?.marks ?? [], topCSS: topCSS, heightCSS: webView.bounds.height / zoom)
        )
    }

    /// Sizes the view to the kept part and scrolls to it. `false` for an empty page.
    private static func place(_ webView: WKWebView, focusY: Double) -> Bool {
        let scrollView = webView.scrollView
        let contentHeight = scrollView.contentSize.height
        guard contentHeight > 0 else { return false }
        let kept = window(focusY: focusY, zoom: max(scrollView.zoomScale, 0.01), contentHeight: contentHeight)
        webView.frame.size.height = kept.height
        scrollView.contentOffset = CGPoint(x: 0, y: kept.top)
        webView.layoutIfNeeded()
        return true
    }

    /// The part of the page we keep, in view points: `leadIn` above the focus, inside the page.
    static func window(focusY: Double, zoom: CGFloat, contentHeight: CGFloat) -> (top: CGFloat, height: CGFloat) {
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
    private static func first<T>(
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
private final class Race<T> {
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
