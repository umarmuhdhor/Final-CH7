import Foundation
import Network
import Testing
import WebKit
@testable import Shoo

/// Counts TCP connections on 127.0.0.1. WKWebView does not go through `URLProtocol`, so a real listener
/// is the only way to see whether the replica reached out.
final class LocalListener: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var _connections = 0

    var connections: Int { lock.withLock { _connections } }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.lock.withLock { self?._connections += 1 }
            connection.cancel()
        }
    }

    /// Starts listening and returns the port.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready: if once.take() { continuation.resume(returning: listener.port!.rawValue) }
                case let .failed(error): if once.take() { continuation.resume(throwing: error) }
                default: break
                }
            }
            listener.start(queue: .global())
        }
    }

    deinit { listener.cancel() }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func take() -> Bool { lock.withLock { defer { done = true }; return !done } }
}

/// Waits for an ordinary web view's first load (the control: proves the listener can be reached).
@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(for webView: WKWebView, html: String) async {
        webView.navigationDelegate = self
        await withCheckedContinuation { continuation = $0; webView.loadHTMLString(html, baseURL: nil) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish() }
    private func finish() { continuation?.resume(); continuation = nil }
}

@MainActor
@Suite(.serialized)
struct ReplicaViewTests {
    /// Every way a static page can reach the network, without JS.
    static func leakyPage(port: UInt16) -> String {
        let base = "http://127.0.0.1:\(port)"
        return """
            <!doctype html><html><head>\
            <meta http-equiv="refresh" content="1;url=\(base)/refresh">\
            <link rel="stylesheet" href="\(base)/a.css"><link rel="preconnect" href="\(base)">\
            <style>@font-face{font-family:x;src:url(\(base)/f.woff)}body{font-family:x;background:url(\(base)/bg.png)}</style>\
            </head><body><img src="\(base)/a.png"><iframe src="\(base)/frame"></iframe>\
            <form action="\(base)/login" method="post"><input name="p" value="x"></form>\
            <a href="\(base)/link">link</a></body></html>
            """
    }

    private func lockedController(focusY: Double = 0) async throws -> ReplicaWebController {
        let rules = try #require(await ReplicaRules.compiled())
        return ReplicaWebController(ruleList: rules, focusY: focusY)
    }

    private func load(_ controller: ReplicaWebController, _ html: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            let done = { if !resumed { resumed = true; continuation.resume() } }
            controller.onFinish = done
            controller.onFailure = done
            controller.load(html)
        }
    }

    @Test func rulesCompile() async {
        #expect(await ReplicaRules.compiled() != nil)
    }

    @Test func plainWebViewReachesTheListener() async throws {
        // Control: without the lock the same page does connect, so zero below means something.
        let listener = try LocalListener()
        let port = try await listener.start()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        await LoadWaiter().wait(for: webView, html: Self.leakyPage(port: port))
        try await Task.sleep(for: .milliseconds(500))
        #expect(listener.connections > 0)
    }

    @Test func lockedViewMakesNoConnectionsAndStaysPut() async throws {
        let listener = try LocalListener()
        let port = try await listener.start()
        let controller = try await lockedController()
        controller.webView.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        // Raw page, no `ReplicaHTML` lock: the web view layer alone must hold.
        await load(controller, Self.leakyPage(port: port))
        // Past the 1 s meta refresh.
        try await Task.sleep(for: .milliseconds(1800))
        #expect(listener.connections == 0)
        #expect(controller.webView.url?.scheme == "about")
    }

    @Test func secondNavigationIsRefused() async throws {
        let controller = try await lockedController()
        await load(controller, "<html><body>x</body></html>")
        controller.webView.load(URLRequest(url: URL(string: "https://example.com/")!))
        try await Task.sleep(for: .milliseconds(300))
        #expect(controller.refusedNavigations >= 1)
        #expect(controller.webView.url?.scheme == "about")
    }

    @Test func noJavaScriptNoStorageNoInspector() async throws {
        let controller = try await lockedController()
        let configuration = controller.webView.configuration
        #expect(configuration.defaultWebpagePreferences.allowsContentJavaScript == false)
        #expect(configuration.websiteDataStore.isPersistent == false)
        #expect(configuration.mediaTypesRequiringUserActionForPlayback == .all)
        #expect(configuration.dataDetectorTypes == [])
        #expect(controller.webView.isInspectable == false)
        #expect(controller.webView.allowsLinkPreview == false)
    }

    @Test func noEditMenuEvenWhenThePageAllowsSelection() async throws {
        let controller = try await lockedController()
        await load(controller, #"<html><body><p style="-webkit-user-select:text!important">Saldo</p></body></html>"#)
        let webView = controller.webView
        #expect(webView.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil) == false)
        #expect(webView.canPerformAction(#selector(UIResponderStandardEditActions.selectAll(_:)), withSender: nil) == false)
        #expect(webView.canBecomeFirstResponder == false)
        #expect(webView.becomeFirstResponder() == false)
    }

    @Test(arguments: [
        (1284.0, 1.0, 3000.0, 844.0, 1284.0),
        (1284.0, 0.5, 3000.0, 844.0, 642.0),
        (5000.0, 1.0, 3000.0, 844.0, 2156.0),
        (-10.0, 1.0, 3000.0, 844.0, 0.0),
        (Double.nan, 1.0, 3000.0, 844.0, 0.0),
        (400.0, 1.0, 600.0, 844.0, 0.0),
    ])
    func focusOffsetStaysInsideThePage(focusY: Double, zoom: Double, content: Double, bounds: Double, expected: Double) {
        let y = ReplicaWebController.focusOffset(
            focusY: focusY, zoomScale: zoom, contentHeight: content, boundsHeight: bounds
        )
        #expect(Double(y) == expected, "got \(y)")
    }
}
