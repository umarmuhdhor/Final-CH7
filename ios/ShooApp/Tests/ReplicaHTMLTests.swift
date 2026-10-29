import Foundation
import Testing
@testable import Shoo

/// K11: our CSP goes first, and markup a real capture never has is not rendered at all.
struct ReplicaHTMLTests {
    /// What replica.js + replica-build.js produce: one CSP meta, styles inline, text escaped.
    static let extensionSample = """
        <!doctype html><html lang="id"><head><meta charset="utf-8">\
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; form-action 'none'; base-uri 'none'">\
        <meta name="viewport" content="width=390"><meta name="shoo-replica" content="{&quot;v&quot;:1}">\
        <title>KlikBCA</title><style>body{font:16px sans-serif}</style></head>\
        <body><p title="a&quot;&gt;&lt;script&gt;">&lt;link rel=preconnect&gt; &amp; co</p>\
        <form data-shoo-href="https://x.site/login"><input type="password"></form></body></html>
        """

    @Test func extensionOutputPasses() throws {
        let locked = try #require(ReplicaHTML.locked(Self.extensionSample))
        #expect(locked.hasPrefix("<!doctype html><meta http-equiv=\"Content-Security-Policy\" content=\"\(ReplicaHTML.csp)\">"))
        #expect(locked.hasSuffix(String(Self.extensionSample.dropFirst("<!doctype html>".count))))
    }

    @Test func lockComesBeforeAnyPageElement() throws {
        let locked = try #require(ReplicaHTML.locked(Self.extensionSample))
        let afterDoctype = locked.dropFirst("<!doctype html>".count)
        let csp = try #require(afterDoctype.range(of: "Content-Security-Policy\" content=\"\(ReplicaHTML.csp)"))
        let prefetch = try #require(afterDoctype.range(of: #"<meta http-equiv="x-dns-prefetch-control" content="off">"#))
        let style = try #require(afterDoctype.range(of: "<style>\(ReplicaHTML.lockStyle)</style>"))
        let html = try #require(afterDoctype.range(of: "<html"))
        #expect(csp.lowerBound < prefetch.lowerBound)
        #expect(prefetch.lowerBound < style.lowerBound)
        #expect(style.upperBound <= html.lowerBound)
    }

    @Test func noDoctypeMeansLockFirst() throws {
        let page = String(Self.extensionSample.dropFirst("<!doctype html>".count))
        let locked = try #require(ReplicaHTML.locked(page))
        #expect(locked.hasPrefix("<meta http-equiv=\"Content-Security-Policy\""))
        #expect(locked.hasSuffix(page))
    }

    @Test func upperCaseDoctypeStaysFirst() throws {
        let locked = try #require(ReplicaHTML.locked("<!DOCTYPE html><html><body>x</body></html>"))
        #expect(locked.hasPrefix("<!DOCTYPE html><meta http-equiv=\"Content-Security-Policy\""))
    }

    @Test func appCSPLoadsNoFontsAndNoRemoteAnything() {
        #expect(ReplicaHTML.csp.contains("font-src 'none'"))
        #expect(ReplicaHTML.csp.contains("default-src 'none'"))
        #expect(ReplicaHTML.csp.contains("img-src data:"))
        #expect(ReplicaHTML.csp.contains("form-action 'none'"))
        #expect(ReplicaHTML.csp.contains("base-uri 'none'"))
    }

    @Test(arguments: [
        #"<link rel="stylesheet" href="https://x.site/a.css">"#,
        #"<link rel=preconnect href="https://tracker.example">"#,
        #"<link rel="dns-prefetch" href="//tracker.example">"#,
        #"<base href="https://x.site/">"#,
        "<script>alert(1)</script>",
        "<svg><script>alert(1)</script></svg>",
        #"<iframe src="https://x.site"></iframe>"#,
        #"<frameset><frame src="https://x.site"></frameset>"#,
        #"<object data="https://x.site/a.swf"></object>"#,
        #"<embed src="https://x.site/a.swf">"#,
        "<noscript><img src=x></noscript>",
        #"<LiNk rel=preconnect href="https://tracker.example">"#,
        #"<SCRIPT src="https://x.site/a.js"></SCRIPT>"#,
    ])
    func refusedMarkupIsNotRendered(tag: String) {
        let page = Self.extensionSample.replacingOccurrences(of: "<title>KlikBCA</title>", with: "<title>KlikBCA</title>\(tag)")
        #expect(ReplicaHTML.locked(page) == nil)
    }

    @Test func secondHttpEquivMetaIsRefused() {
        let refresh = Self.extensionSample.replacingOccurrences(
            of: "<title>", with: #"<meta http-equiv="refresh" content="0;url=https://x.site"><title>"#
        )
        #expect(ReplicaHTML.locked(refresh) == nil)
        let upper = Self.extensionSample.replacingOccurrences(
            of: "<title>", with: #"<META content="0" HTTP-EQUIV="Refresh"><title>"#
        )
        #expect(ReplicaHTML.locked(upper) == nil)
    }

    @Test func escapedTextIsNotATag() {
        // `&lt;link` in the sample is page text, not markup.
        #expect(ReplicaHTML.passesGate(Self.extensionSample))
    }
}
