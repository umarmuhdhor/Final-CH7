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
        let expiry = try #require(pasteboard.options[.expirationDate] as? Date)
        #expect(expiry > Date() && expiry <= Date().addingTimeInterval(LinkCopy.lifetime))
        #expect(pasteboard.items.count == 1)
        #expect(pasteboard.items[0]["public.plain-text"] as? String == "https://bca-verifikasi.site/login?ref=wa")
    }
}

/// Answers every request from `handler` instead of the network. Shared state is behind a lock:
/// URL loading runs on its own thread. Only `ScreenshotLoaderTests` (serialized) uses it.
final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) private static var _requests: [URLRequest] = []

    static func reset(_ handler: (@Sendable (URLRequest) -> (Int, Data))?) {
        lock.withLock {
            _handler = handler
            _requests = []
        }
    }

    static var requests: [URLRequest] { lock.withLock { _requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock {
            Self._requests.append(request)
            return Self._handler
        }
        let (status, data) = handler?(request) ?? (404, Data())
        if status == 302 {
            let elsewhere = URL(string: "https://evil.example/x.png")!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": elsewhere.absoluteString]
            )!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: elsewhere), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
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
        return URLSessionScreenshotLoader(configuration: configuration, allowedHost: "shoo-api.example.workers.dev")
    }

    private static let png: Data = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    @Test func sessionKeepsNoCopy() {
        let configuration = URLSessionScreenshotLoader.configuration()
        // No URLCache at all (P9 + P13): every view asks the Worker, which re-checks access.
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.urlCredentialStorage == nil)
    }

    @Test func loadsImageWithoutAuthorizationHeader() async throws {
        let png = Self.png
        StubURLProtocol.reset { _ in (200, png) }
        let data = try await loader().imageData(at: Self.url)
        #expect(UIImage(data: data) != nil)
        let request = try #require(StubURLProtocol.requests.last)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func goneScreenshotThrows() async {
        StubURLProtocol.reset { _ in (404, Data()) }
        await #expect(throws: ScreenshotLoadError.unavailable) {
            try await loader().imageData(at: Self.url)
        }
    }

    @Test func nonImageBodyThrows() async {
        StubURLProtocol.reset { _ in (200, Data("<html>".utf8)) }
        await #expect(throws: ScreenshotLoadError.unavailable) {
            try await loader().imageData(at: Self.url)
        }
    }

    @Test func oversizedBodyThrows() async {
        StubURLProtocol.reset { _ in (200, Data(count: URLSessionScreenshotLoader.maxBytes + 1)) }
        await #expect(throws: ScreenshotLoadError.unavailable) {
            try await loader().imageData(at: Self.url)
        }
    }

    @Test func hugeDimensionsAreRefused() async {
        // A tiny PNG whose header claims 30000 × 30000 px (decompression bomb).
        let bomb = Self.pngHeader(width: 30000, height: 30000)
        StubURLProtocol.reset { _ in (200, bomb) }
        await #expect(throws: ScreenshotLoadError.unavailable) {
            try await loader().imageData(at: Self.url)
        }
    }

    @Test func otherHostsAreRefused() async {
        StubURLProtocol.reset { _ in (200, Self.png) }
        await #expect(throws: ScreenshotLoadError.unavailable) {
            try await loader().imageData(at: URL(string: "https://evil.example/screenshots/abc")!)
        }
        await #expect(throws: ScreenshotLoadError.unavailable) {
            try await loader().imageData(at: URL(string: "https://shoo-api.example.workers.dev/devices/me")!)
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test func redirectsAreNotFollowed() async {
        StubURLProtocol.reset { request in
            request.url?.host() == "evil.example" ? (200, Self.png) : (302, Data())
        }
        await #expect(throws: ScreenshotLoadError.unavailable) {
            try await loader().imageData(at: Self.url)
        }
        #expect(StubURLProtocol.requests.allSatisfy { $0.url?.host() != "evil.example" })
    }

    @Test func decodeDownsamplesLargeImages() throws {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1000)).pngData { _ in }
        let image = try #require(ScreenshotDecoder.image(from: data, maxPixelSize: 1024))
        #expect(max(image.size.width * image.scale, image.size.height * image.scale) <= 1024)
    }

    /// PNG signature + IHDR + IEND, no pixel data.
    private static func pngHeader(width: UInt32, height: UInt32) -> Data {
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let typeBytes = Array(type.utf8)
            let length = withUnsafeBytes(of: UInt32(body.count).bigEndian, Array.init)
            let crc = withUnsafeBytes(of: crc32(typeBytes + body).bigEndian, Array.init)
            return length + typeBytes + body + crc
        }
        let ihdr = withUnsafeBytes(of: width.bigEndian, Array.init) + withUnsafeBytes(of: height.bigEndian, Array.init)
            + [8, 6, 0, 0, 0]
        let bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", ihdr) + chunk("IEND", [])
        return Data(bytes)
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
        }
        return ~crc
    }

    @Test func plainHTTPIsRefused() async {
        StubURLProtocol.reset(nil)
        await #expect(throws: ScreenshotLoadError.unavailable) {
            try await loader().imageData(at: URL(string: "http://example.com/a.png")!)
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }
}
