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
    /// Picture width in points (× screen scale in pixels): sharp on the 270 pt card, small in memory.
    static let imageWidth: CGFloat = 200
    /// `didFinish` never came: show the placeholder instead of waiting forever.
    static let loadTimeout: Duration = .seconds(10)
    /// A page that stalls the content process must not keep the hidden view in the window.
    static let snapshotTimeout: Duration = .seconds(5)
    /// Time for the newly shown tiles after the frame grows.
    static let paintDelay: Duration = .milliseconds(300)

    /// `lockedHTML` must come from `ReplicaHTML.locked(_:)`. `nil` when WebKit can't draw it.
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
        defer { webView.removeFromSuperview() }

        guard await finished(controller, html: lockedHTML) else { return nil }
        await controller.waitForLayout()

        let scrollView = webView.scrollView
        let zoom = max(scrollView.zoomScale, 0.01)
        let contentHeight = scrollView.contentSize.height
        guard contentHeight > 0 else { return nil }
        let kept = Self.window(focusY: meta?.focusY ?? 0, zoom: zoom, contentHeight: contentHeight)
        webView.frame.size.height = kept.height
        scrollView.contentOffset = CGPoint(x: 0, y: kept.top)
        // The taller frame shows page parts WebKit has not painted yet; there is no paint-done event
        // without JS, so let the new size lay out and give the tiles a moment.
        webView.layoutIfNeeded()
        await controller.waitForLayout()
        try? await Task.sleep(for: paintDelay)

        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(origin: .zero, size: webView.bounds.size)
        configuration.snapshotWidth = NSNumber(value: Double(imageWidth))
        configuration.afterScreenUpdates = true
        let image: UIImage? = await first(within: snapshotTimeout, otherwise: nil) { done in
            webView.takeSnapshot(with: configuration) { image, _ in done(image) }
        }
        guard let image else {
            webView.stopLoading()
            return nil
        }

        let topCSS = kept.top / zoom
        return PageCopy(
            image: image,
            meta: meta,
            cssWidth: renderWidth / zoom,
            marks: shifted(meta?.marks ?? [], topCSS: topCSS, heightCSS: kept.height / zoom)
        )
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

    /// The window the Detail screen is in, for `render(_:meta:ruleList:in:)`.
    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    /// `true` on `didFinish`; `false` on failure, a dead content process, or `loadTimeout`.
    private static func finished(_ controller: ReplicaWebController, html: String) async -> Bool {
        await first(within: loadTimeout, otherwise: false) { done in
            controller.onFinish = { done(true) }
            controller.onFailure = { done(false) }
            controller.load(html)
        }
    }

    /// The first answer `start` gives, or `fallback` after `timeout`; later answers are ignored.
    private static func first<T>(
        within timeout: Duration, otherwise fallback: T, _ start: (@escaping (T) -> Void) -> Void
    ) async -> T {
        await withCheckedContinuation { continuation in
            var resumed = false
            let done: (T) -> Void = { value in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }
            start(done)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                done(fallback)
            }
        }
    }
}
