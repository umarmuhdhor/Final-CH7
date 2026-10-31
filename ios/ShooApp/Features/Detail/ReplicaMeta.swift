import Foundation

/// What the extension wrote into `<meta name="shoo-replica" content="…">` (replica.js `headMeta`).
/// The device writes it, so every field is untrusted: anything off means "render from the top" (K13).
struct ReplicaMeta: Equatable, Sendable {
    /// The meta sits in `<head>`, but `<html style>` can carry a data URI before it.
    static let searchLimit = 64 * 1024
    /// Longest "Copied from …" text on the Detail screen.
    static let maxCopiedFromLength = 80

    var url: URL?
    var capturedAt: Date
    /// Document y to scroll to first (the sensitive form, else what was on screen). Never negative.
    var focusY: Double
    var truncated: Bool

    private static let marker = #"<meta name="shoo-replica" content=""#
    private static let keys: Set<String> = ["v", "url", "capturedAt", "viewport", "focusY", "truncated"]
    /// replica.js metaToken (`shoo` + up to 8 base-36 chars + `-meta`). Seeing it inside the value means
    /// `$&` in the page URL made `String.replace` paste the token back in (replica.js:279, C26).
    private static let leakedToken = try! Regex("shoo[a-z0-9]{0,8}-meta")

    private struct Wire: Decodable {
        var v: Int
        var url: String?
        var capturedAt: Date
        var focusY: Double?
        var truncated: Bool?
    }

    /// `nil` when the meta is missing or broken in any way; the caller then starts at the top.
    static func read(from html: String) -> ReplicaMeta? {
        let head = headPrefix(of: html)
        guard let start = head.range(of: marker)?.upperBound,
              let end = head[start...].firstIndex(of: "\"")
        else { return nil }
        // escapeAttr (replica.js:56) wrote these four; one pass, `&amp;` last so `&amp;quot;` stays `&quot;`.
        let value = head[start..<end]
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
        guard value.firstMatch(of: leakedToken) == nil else { return nil }
        let data = Data(value.utf8)
        // Strict: one JSON object with known keys only. `$'` in the URL pastes the rest of the page in.
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: keys),
              let wire = try? JSONDecoder.shoo.decode(Wire.self, from: data),
              wire.v == 1
        else { return nil }
        // JSON.stringify(NaN) is null.
        let focusY = wire.focusY.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
        return ReplicaMeta(
            url: wire.url.flatMap(URL.init(string:)),
            capturedAt: wire.capturedAt,
            focusY: focusY,
            truncated: wire.truncated ?? false
        )
    }

    /// Time for "Copy of the page · …": the device clock, kept near the scan (K14). No meta → `detectedAt`.
    static func capturedAt(_ meta: ReplicaMeta?, detectedAt: Date) -> Date {
        guard let meta else { return detectedAt }
        let earliest = detectedAt.addingTimeInterval(-24 * 60 * 60)
        let latest = detectedAt.addingTimeInterval(5 * 60)
        return min(max(meta.capturedAt, earliest), latest)
    }

    /// "Copied from <host+path>" when the copy came from another page of the same site (24-hour reuse, K4).
    /// Only for the scan's domain or a subdomain: the device could write any URL here. Plain text, shortened.
    func copiedFrom(scanURL: URL, domain: String) -> String? {
        guard let url, url != scanURL, ["http", "https"].contains(url.scheme?.lowercased()),
              let host = url.host()?.lowercased()
        else { return nil }
        let domain = domain.lowercased()
        guard host == domain || host.hasSuffix("." + domain) else { return nil }
        // The decoded path is device text: no line breaks or bidi controls that could reorder the line.
        let path = String(String.UnicodeScalarView(url.path(percentEncoded: false).unicodeScalars.filter { scalar in
            ![.control, .format, .lineSeparator, .paragraphSeparator].contains(scalar.properties.generalCategory)
        }))
        let text = host + path
        guard text.count > Self.maxCopiedFromLength else { return text }
        return String(text.prefix(Self.maxCopiedFromLength - 1)) + "…"
    }

    private static func headPrefix(of html: String) -> Substring {
        let limit = html.utf8.index(html.startIndex, offsetBy: min(searchLimit, html.utf8.count))
        let window = html[..<limit]
        guard let headEnd = window.range(of: "</head>", options: .caseInsensitive) else { return window }
        return window[..<headEnd.lowerBound]
    }
}
