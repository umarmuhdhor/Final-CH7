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
    /// `http-equiv` is counted anywhere in the file, not per tag: a `>` inside an attribute can't hide a second one,
    /// and the scan stays linear on a hostile 3 MB file (one pass per needle).
    static func passesGate(_ html: String) -> Bool {
        let lower = html.lowercased()
        guard !refusedTags.contains(where: { containsTag($0, in: lower) }) else { return false }
        var httpEquiv = 0
        var from = lower.startIndex
        while let hit = lower.range(of: "http-equiv", range: from..<lower.endIndex) {
            httpEquiv += 1
            if httpEquiv > 1 { return false }
            from = hit.upperBound
        }
        return true
    }

    /// `tag` followed by whitespace, `/`, `>` or the end of the file. One pass per needle, like `passesGate`.
    private static func containsTag(_ tag: String, in lower: String) -> Bool {
        var from = lower.startIndex
        while let hit = lower.range(of: tag, range: from..<lower.endIndex) {
            guard hit.upperBound < lower.endIndex else { return true }
            let next = lower[hit.upperBound]
            if next.isWhitespace || next == "/" || next == ">" { return true }
            from = hit.upperBound
        }
        return false
    }
}
