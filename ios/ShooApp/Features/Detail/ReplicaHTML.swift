import Foundation

/// Makes a page replica safe to hand to `WKWebView.loadHTMLString` (K11, K12).
/// The Worker's CSP header is lost once the HTML is a string, and the CSP `<meta>` inside the file was
/// written by the device, so the app adds its own lock in front and refuses markup a real capture never has.
enum ReplicaHTML {
    /// Same as the Worker's REPLICA_CSP, except fonts: the device's binary fonts are not loaded, system fonts only.
    static let csp = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src 'none'; form-action 'none'; base-uri 'none'"

    /// Second layer under `LockedWebView`: inline `!important` page styles can beat these, the native lock can't be beaten.
    static let lockStyle = """
        *{-webkit-user-select:none!important;-webkit-touch-callout:none!important;animation:none!important;transition:none!important}\
        input,textarea,select,button{pointer-events:none!important;-webkit-user-modify:read-only!important}
        """

    /// Tags replica.js never writes (stylesheets become `<style>`, `<` in text and attributes is escaped).
    /// `preconnect`/`dns-prefetch` links may get past the content rule list, so any of these means a modified device.
    /// A tag name only counts when the name ends there, so SVG's `<linearGradient` is not `<link`.
    private static let refusedTags = [
        "<link", "<base", "<script", "<iframe", "<frame", "<frameset", "<object", "<embed", "<noscript",
    ]

    /// The HTML with our CSP, DNS-prefetch-off and lock style first, or `nil` when it must not be rendered.
    static func locked(_ html: String) -> String? {
        guard passesGate(html) else { return nil }
        let lock = """
            <meta http-equiv="Content-Security-Policy" content="\(csp)">\
            <meta http-equiv="x-dns-prefetch-control" content="off">\
            <style>\(lockStyle)</style>
            """
        // Before the doctype would put the page in quirks mode; after it, nothing else comes first.
        // A BOM or whitespace before the doctype is still a doctype (no quirks mode, marks stay in place).
        if let doctype = html.range(of: #"^\x{FEFF}?\s*<!doctype[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
            return html[..<doctype.upperBound] + lock + html[doctype.upperBound...]
        }
        return lock + html
    }

    /// Fail-closed lexical gate (K11), case-insensitive. A real capture has exactly one `<meta http-equiv>` (its CSP).
    /// `http-equiv` is counted anywhere in the file, not per tag: a `>` inside an attribute can't hide a second one.
    /// One linear pass over the bytes, so a hostile 3 MB file stays fast (`<meta <meta …` flood, review H1).
    static func passesGate(_ html: String) -> Bool {
        let utf8 = html.utf8
        return utf8.withContiguousStorageIfAvailable(passesGate)
            ?? Array(utf8).withUnsafeBufferPointer(passesGate)
    }

    private static let refusedNames: [[UInt8]] = refusedTags.map { Array($0.utf8.dropFirst()) }
    private static let firstLetters = Set(refusedNames.compactMap(\.first))

    private static func passesGate(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let base = bytes.baseAddress else { return true }
        let count = bytes.count
        // ASCII-only lowercasing: every needle is ASCII.
        @inline(__always) func lower(_ byte: UInt8) -> UInt8 { byte >= 65 && byte <= 90 ? byte | 0x20 : byte }
        @inline(__always) func matches(_ needle: some Collection<UInt8>, at start: Int) -> Bool {
            guard start >= 0, start + needle.count <= count else { return false }
            var k = start
            for byte in needle {
                if lower(base[k]) != byte { return false }
                k += 1
            }
            return true
        }
        // memchr jumps to the next `<` / `-`; only those spots are compared.
        func positions(of byte: UInt8, _ body: (Int) -> Bool) -> Bool {
            var from = 0
            while from < count, let hit = memchr(base + from, Int32(byte), count - from) {
                let at = base.distance(to: hit.assumingMemoryBound(to: UInt8.self))
                if !body(at) { return false }
                from = at + 1
            }
            return true
        }
        let tagsOK = positions(of: UInt8(ascii: "<")) { at in
            guard at + 1 < count, firstLetters.contains(lower(base[at + 1])) else { return true }
            for name in refusedNames where matches(name, at: at + 1) {
                // The name must end there, so SVG's `<linearGradient` is not `<link`.
                let end = at + 1 + name.count
                guard end < count else { return false }
                let next = base[end]
                if next == 0x20 || (0x09...0x0D).contains(next) || next == UInt8(ascii: "/") || next == UInt8(ascii: ">") {
                    return false
                }
            }
            return true
        }
        guard tagsOK else { return false }
        var equivs = 0
        return positions(of: UInt8(ascii: "-")) { at in
            guard matches("http".utf8, at: at - 4), matches("equiv".utf8, at: at + 1) else { return true }
            equivs += 1
            return equivs <= 1
        }
    }
}
