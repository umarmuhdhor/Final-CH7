import UIKit
import WebKit

/// K11: every URL other than `data:` and `about:` is blocked inside the replica web view.
/// This is the network lock under the CSP; the lexical gate in `ReplicaHTML` is the one above it.
enum ReplicaRules {
    static let identifier = "shoo-replica-v1"
    static let json = """
        [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},\
        {"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}},\
        {"trigger":{"url-filter":"^about:"},"action":{"type":"ignore-previous-rules"}}]
        """

    /// `nil` when WebKit can't compile it: the caller shows the placeholder, never an unlocked page.
    @MainActor
    static func compiled() async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier, encodedContentRuleList: json
            ) { list, _ in
                continuation.resume(returning: list)
            }
        }
    }
}

/// K12: no selection menu, no callout (Share, Translate, Look Up, Save Image), no keyboard.
/// The evidence must not leave the app (P9); the injected CSS can lose to inline `!important`, this can't.
final class LockedWebView: WKWebView {
    override func buildMenu(with builder: UIMenuBuilder) {}
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
    override var canBecomeFirstResponder: Bool { false }
    override func becomeFirstResponder() -> Bool { false }
}

/// Owns one locked web view: loads the replica once, refuses every later navigation. `ReplicaSnapshot`
/// places and draws it; no live web view is shown (fase 18b K12, fase 22 K9).
@MainActor
final class ReplicaWebController: NSObject, WKNavigationDelegate, WKUIDelegate {
    /// How long the layout may keep changing after `didFinish` before we place the page anyway (K13).
    static let layoutTimeout: Duration = .seconds(2)

    let webView: LockedWebView
    private var firstLoadAllowed = false
    /// Navigations refused after the first load (links, forms, `meta refresh`).
    private(set) var refusedNavigations = 0
    var onFinish: (() -> Void)?
    /// The content process died or the page failed: show the placeholder, never reload.
    var onFailure: (() -> Void)?

    init(ruleList: WKContentRuleList) {
        webView = LockedWebView(frame: .zero, configuration: Self.configuration(ruleList: ruleList))
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        webView.isInspectable = false
    }

    static func configuration(ruleList: WKContentRuleList) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Nothing the page sets survives the view (P13).
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(ruleList)
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.dataDetectorTypes = []
        return configuration
    }

    /// `html` must come from `ReplicaHTML.locked(_:)`.
    func load(_ html: String) {
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        // The string load is `about:blank`; everything after it is the page trying to go somewhere.
        if !firstLoadAllowed, navigationAction.navigationType == .other,
           navigationAction.request.url?.absoluteString == "about:blank" {
            firstLoadAllowed = true
            decisionHandler(.allow)
            return
        }
        refusedNavigations += 1
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        onFailure?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        onFailure?()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onFailure?()
    }

    // MARK: WKUIDelegate

    func webView(
        _ webView: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping @MainActor (UIContextMenuConfiguration?) -> Void
    ) {
        completionHandler(nil)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }

    /// Without JS there is no layout-done event: wait until the content size stops changing (or 2 s).
    func waitForLayout() async {
        let clock = ContinuousClock()
        let deadline = clock.now + Self.layoutTimeout
        var last = CGSize.zero
        while clock.now < deadline {
            // Cancelled: `Task.sleep` would throw at once and the loop would spin on the main actor.
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            let size = webView.scrollView.contentSize
            if size == last, size != .zero { break }
            last = size
        }
    }
}
