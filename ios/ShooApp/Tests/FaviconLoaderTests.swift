import Foundation
import Testing
@testable import Shoo

/// SECURITY §3 P9 (D-alief-A41): favicons only from our Worker's signed link, memory only.
struct FaviconLoaderTests {
    @Test(arguments: [
        ("https://api.shoo.test/favicons/abc.png?exp=1&sig=x", true),
        ("https://evil.example/favicons/abc.png", false),
        ("https://api.shoo.test/screenshots/abc.jpg", false),
        ("https://api.shoo.test/favicon.ico", false),
        ("http://api.shoo.test/favicons/abc.png", false),
        ("https://bca-verifikasi.site/favicon.ico", false),
    ])
    func onlyOurWorkersFaviconPathIsLoaded(link: String, allowed: Bool) throws {
        let url = try #require(URL(string: link))
        #expect(URLSessionFaviconLoader.isAllowed(url, host: "api.shoo.test") == allowed)
    }

    @Test func localWorkerOverHTTPInDebugOnly() throws {
        let url = try #require(URL(string: "http://localhost:8787/favicons/abc.png"))
        #if DEBUG
        #expect(URLSessionFaviconLoader.isAllowed(url, host: "localhost"))
        #else
        #expect(!URLSessionFaviconLoader.isAllowed(url, host: "localhost"))
        #endif
    }

    @Test func otherHostsAreNeverContacted() async throws {
        let loader = URLSessionFaviconLoader(configuration: URLSessionScreenshotLoader.configuration(), allowedHost: "api.shoo.test")
        let url = try #require(URL(string: "https://bca-verifikasi.site/favicon.ico"))
        await #expect(throws: FaviconLoadError.unavailable) {
            _ = try await loader.image(at: url)
        }
    }

    @Test func sessionKeepsNothingOnDisk() {
        let configuration = URLSessionScreenshotLoader.configuration()
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.httpAdditionalHeaders?["Authorization"] == nil)
    }
}
