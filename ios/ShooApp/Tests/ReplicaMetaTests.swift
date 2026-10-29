import Foundation
import Testing
@testable import Shoo

/// K13 + K14 + K4: the replica's own metadata, written by the device and trusted for nothing.
struct ReplicaMetaTests {
    static let detectedAt = Date(timeIntervalSince1970: 1_793_260_800) // 2026-10-29T08:00:00Z

    /// The head replica.js writes, with `content` escaped the way escapeAttr does it.
    static func page(content: String, before: String = "") -> String {
        """
        <!doctype html><html lang="id"\(before)><head><meta charset="utf-8">\
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'">\
        <meta name="viewport" content="width=390"><meta name="shoo-replica" content="\(content)">\
        <title>KlikBCA</title></head><body><p>Saldo</p></body></html>
        """
    }

    static func escaped(_ json: String) -> String {
        json.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static let valid = #"{"v":1,"url":"https://klikbca-login.site/masuk?a=1&b=2","capturedAt":"2026-10-29T08:00:01.123Z","viewport":{"width":390,"height":844},"focusY":1284,"truncated":false}"#

    @Test func readsValidMeta() throws {
        let meta = try #require(ReplicaMeta.read(from: Self.page(content: Self.escaped(Self.valid))))
        #expect(meta.url == URL(string: "https://klikbca-login.site/masuk?a=1&b=2"))
        #expect(meta.capturedAt == Date(timeIntervalSince1970: 1_793_260_801.123))
        #expect(meta.focusY == 1284)
        #expect(meta.truncated == false)
    }

    @Test func decodesEntitiesOnceWithAmpLast() throws {
        // A title of `&quot;` in the URL is written `&amp;quot;`: it must come back as `&quot;`, not `"`.
        let json = #"{"v":1,"url":"https://x.site/a&quot;b","capturedAt":"2026-10-29T08:00:00Z","focusY":0,"truncated":false}"#
        let meta = try #require(ReplicaMeta.read(from: Self.page(content: Self.escaped(json))))
        #expect(meta.url?.absoluteString == "https://x.site/a&quot;b")
    }

    @Test func truncatedIsRead() throws {
        let json = #"{"v":1,"url":"https://x.site/","capturedAt":"2026-10-29T08:00:00Z","focusY":0,"truncated":true}"#
        #expect(try #require(ReplicaMeta.read(from: Self.page(content: Self.escaped(json)))).truncated)
    }

    @Test(arguments: [
        "not json",
        #"{"v":1,"capturedAt":"2026-10-29T08:00:00Z""#,
        #"[1,2]"#,
        #"{"v":2,"url":"https://x.site/","capturedAt":"2026-10-29T08:00:00Z"}"#,
        #"{"v":1,"url":"https://x.site/","capturedAt":"2026-10-29T08:00:00Z","script":"x"}"#,
        #"{"v":1,"url":"https://x.site/","capturedAt":"yesterday"}"#,
        #"{"v":1,"url":"https://x.site/"}"#,
    ])
    func brokenMetaMeansStartAtTheTop(json: String) {
        #expect(ReplicaMeta.read(from: Self.page(content: Self.escaped(json))) == nil)
    }

    @Test func missingMeta() {
        #expect(ReplicaMeta.read(from: "<!doctype html><html><head><title>x</title></head><body></body></html>") == nil)
        #expect(ReplicaMeta.read(from: "") == nil)
    }

    @Test func metaAfterHeadIsIgnored() {
        let html = "<html><head></head><body><meta name=\"shoo-replica\" content=\"\(Self.escaped(Self.valid))\"></body></html>"
        #expect(ReplicaMeta.read(from: html) == nil)
    }

    @Test func metaPast64KBIsIgnored() {
        let padding = #" style="background:url(data:image/png;base64,\#(String(repeating: "A", count: ReplicaMeta.searchLimit)))""#
        #expect(ReplicaMeta.read(from: Self.page(content: Self.escaped(Self.valid), before: padding)) == nil)
    }

    @Test func metaAfterAShortHtmlStyleIsFound() {
        let padding = #" style="background:url(data:image/png;base64,\#(String(repeating: "A", count: 1000)))""#
        #expect(ReplicaMeta.read(from: Self.page(content: Self.escaped(Self.valid), before: padding)) != nil)
    }

    /// replica.js:279 passes the meta as a replacement string, so `$'` pastes the rest of the document in.
    @Test func dollarQuoteInTheURLBreaksTheMeta() {
        let rest = #"">\#u{3C}title>KlikBCA</title></head><body>"#
        let content = Self.escaped(#"{"v":1,"url":"https://x.site/a"#) + rest
        #expect(ReplicaMeta.read(from: Self.page(content: content)) == nil)
    }

    /// …and `$&` pastes the token back in: the JSON stays valid but the URL is not the page's.
    @Test func dollarAmpInTheURLBreaksTheMeta() {
        let json = #"{"v":1,"url":"https://x.site/ashoo4k2j9x0q-metab","capturedAt":"2026-10-29T08:00:00Z","focusY":900,"truncated":false}"#
        #expect(ReplicaMeta.read(from: Self.page(content: Self.escaped(json))) == nil)
    }

    @Test(arguments: [(-50.0, 0.0), (0.0, 0.0), (12.5, 12.5)])
    func focusYIsNeverNegative(raw: Double, expected: Double) throws {
        let json = #"{"v":1,"url":"https://x.site/","capturedAt":"2026-10-29T08:00:00Z","focusY":\#(raw),"truncated":false}"#
        #expect(try #require(ReplicaMeta.read(from: Self.page(content: Self.escaped(json)))).focusY == expected)
    }

    @Test func nanFocusYStartsAtTheTop() throws {
        // JSON.stringify(NaN) is null.
        let json = #"{"v":1,"url":"https://x.site/","capturedAt":"2026-10-29T08:00:00Z","focusY":null,"truncated":false}"#
        #expect(try #require(ReplicaMeta.read(from: Self.page(content: Self.escaped(json)))).focusY == 0)
    }

    @Test func capturedAtIsClampedNearTheScan() {
        func meta(_ offset: TimeInterval) -> ReplicaMeta {
            ReplicaMeta(url: nil, capturedAt: Self.detectedAt.addingTimeInterval(offset), focusY: 0, truncated: false)
        }
        let at = Self.detectedAt
        #expect(ReplicaMeta.capturedAt(meta(-60), detectedAt: at) == at.addingTimeInterval(-60))
        #expect(ReplicaMeta.capturedAt(meta(-3 * 86400), detectedAt: at) == at.addingTimeInterval(-86400))
        #expect(ReplicaMeta.capturedAt(meta(3600), detectedAt: at) == at.addingTimeInterval(300))
        #expect(ReplicaMeta.capturedAt(nil, detectedAt: at) == at)
    }

    @Test func copiedFromOnlyForTheSameSite() throws {
        let scanURL = try #require(URL(string: "https://klikbca-login.site/masuk"))
        func copied(_ link: String) -> String? {
            ReplicaMeta(url: URL(string: link), capturedAt: Self.detectedAt, focusY: 0, truncated: false)
                .copiedFrom(scanURL: scanURL, domain: "klikbca-login.site")
        }
        #expect(copied("https://klikbca-login.site/masuk") == nil)
        #expect(copied("https://klikbca-login.site/otp?x=1") == "klikbca-login.site/otp")
        #expect(copied("https://m.klikbca-login.site/otp") == "m.klikbca-login.site/otp")
        #expect(copied("https://klikbca.com/") == nil)
        #expect(copied("https://notklikbca-login.site/") == nil)
        let long = try #require(copied("https://klikbca-login.site/" + String(repeating: "a", count: 200)))
        #expect(long.count == ReplicaMeta.maxCopiedFromLength)
        #expect(long.hasSuffix("…"))
    }
}
