import Foundation
import Testing
import UIKit
@testable import Shoo

/// SECURITY §3 P8 (copy) and P9 (screenshot) for the Detail screen.
@MainActor
struct LinkCopyTests {
    final class FakePasteboard: PasteboardWriting {
        var items: [[String: Any]] = []
        var options: [UIPasteboard.OptionsKey: Any] = [:]

        func setItems(_ items: [[String: Any]], options: [UIPasteboard.OptionsKey: Any]) {
            self.items = items
            self.options = options
        }
    }

    @Test func copiedLinkStaysOnThisDevice() throws {
        let pasteboard = FakePasteboard()
        let url = try #require(URL(string: "https://bca-verifikasi.site/login?ref=wa"))
        LinkCopy.copy(url, to: pasteboard)
        #expect(pasteboard.options[.localOnly] as? Bool == true)
        #expect(pasteboard.items.count == 1)
        #expect(pasteboard.items[0]["public.plain-text"] as? String == "https://bca-verifikasi.site/login?ref=wa")
    }
}

/// Answers every request from `handler` instead of the network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let (status, data) = Self.handler?(request) ?? (404, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct ScreenshotLoaderTests {
    static let url = URL(string: "https://shoo-api.example.workers.dev/screenshots/abc?v=dev&exp=1&sig=x")!

    private func loader() -> URLSessionScreenshotLoader {
        let configuration = URLSessionScreenshotLoader.configuration()
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionScreenshotLoader(configuration: configuration)
    }

    private static let png: Data = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    @Test func sessionNeverWritesToDisk() {
        let configuration = URLSessionScreenshotLoader.configuration()
        #expect(configuration.urlCache?.diskCapacity == 0)
        #expect((configuration.urlCache?.memoryCapacity ?? 0) > 0)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.urlCredentialStorage == nil)
    }

    @Test func loadsImageWithoutAuthorizationHeader() async throws {
        StubURLProtocol.requests = []
        StubURLProtocol.handler = { _ in (200, Self.png) }
        let data = try await loader().imageData(at: Self.url)
        #expect(UIImage(data: data) != nil)
        let request = try #require(StubURLProtocol.requests.last)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func goneScreenshotThrows() async {
        StubURLProtocol.handler = { _ in (404, Data()) }
        await #expect(throws: ScreenshotLoadError.unavailable) {
            try await loader().imageData(at: Self.url)
        }
    }

    @Test func nonImageBodyThrows() async {
        StubURLProtocol.handler = { _ in (200, Data("<html>".utf8)) }
        await #expect(throws: ScreenshotLoadError.unavailable) {
            try await loader().imageData(at: Self.url)
        }
    }

    @Test func oversizedBodyThrows() async {
        StubURLProtocol.handler = { _ in (200, Data(count: URLSessionScreenshotLoader.maxBytes + 1)) }
        await #expect(throws: ScreenshotLoadError.unavailable) {
            try await loader().imageData(at: Self.url)
        }
    }

    @Test func plainHTTPIsRefused() async {
        StubURLProtocol.requests = []
        await #expect(throws: ScreenshotLoadError.unavailable) {
            try await loader().imageData(at: URL(string: "http://example.com/a.png")!)
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }
}
