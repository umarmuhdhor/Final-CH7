import Foundation
import SwiftUI

enum ReplicaLoadError: Error, Equatable {
    /// Gone (deleted, retention, disconnected: the Worker answers 404), expired, too big, or not text.
    case unavailable
    /// 429: too many views; the screen says "Try again later" and does not ask for a new link.
    case rateLimited
}

/// Loads the page replica behind `pageReplicaUrl`.
protocol ReplicaLoading: Sendable {
    func html(at url: URL) async throws -> String
}

extension EnvironmentValues {
    @Entry var replicaLoader: any ReplicaLoading = URLSessionReplicaLoader.shared
}

/// SECURITY §3 P9 + P13: the replica lives in memory only, like the screenshot.
/// The Worker sends the stored gzip with `Content-Encoding: gzip`; URLSession inflates it, and the inflated
/// size is capped here because the backend only checks the compressed size on some paths (K2 plan B).
struct URLSessionReplicaLoader: ReplicaLoading {
    /// Same as `MAX_HTML_BYTES` in replica-build.js and `MAX_REPLICA_HTML` in the Worker.
    static let maxHTMLBytes = 3_145_728
    static let shared = URLSessionReplicaLoader(configuration: URLSessionScreenshotLoader.configuration())

    private let session: URLSession
    /// `pageReplicaUrl` always points at our Worker; nothing else is fetched.
    private let allowedHost: String?

    init(configuration: URLSessionConfiguration, allowedHost: String? = AppConfig.apiBaseURL.host()) {
        session = URLSession(configuration: configuration, delegate: RedirectRefuser(), delegateQueue: nil)
        self.allowedHost = allowedHost
    }

    func html(at url: URL) async throws -> String {
        guard let allowedHost, Self.isAllowed(url, host: allowedHost) else { throw ReplicaLoadError.unavailable }
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(from: url)
        } catch let error as URLError where error.code != .cancelled {
            throw ReplicaLoadError.unavailable
        }
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 429 { throw ReplicaLoadError.rateLimited }
        guard status == 200 else { throw ReplicaLoadError.unavailable }
        // Counted after inflating: a 300 KB gzip can hold far more than 3 MB.
        // Bytes go into a reserved buffer (not `Data` one by one); a dropped connection mid-body is
        // "unavailable" like one that never started, never an expired link.
        var buffer: [UInt8] = []
        buffer.reserveCapacity(Int(min(max(response.expectedContentLength, 64 * 1024), Int64(Self.maxHTMLBytes))))
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count > Self.maxHTMLBytes { throw ReplicaLoadError.unavailable }
            }
        } catch let error as URLError where error.code != .cancelled {
            throw ReplicaLoadError.unavailable
        }
        let data = Data(buffer)
        guard let html = String(data: data, encoding: .utf8) else { throw ReplicaLoadError.unavailable }
        return html
    }

    /// Our Worker's `/replicas/` path only, over HTTPS (SECURITY §3 P5);
    /// plain HTTP only for the local Worker (`wrangler dev`) in Debug builds.
    static func isAllowed(_ url: URL, host allowedHost: String) -> Bool {
        guard let host = url.host(), host == allowedHost,
              url.path().hasPrefix("/replicas/"), !url.path(percentEncoded: false).contains(".."), url.user() == nil
        else { return false }
        if url.scheme == "https" { return url.port == nil }
        #if DEBUG
        return url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host)
        #else
        return false
        #endif
    }
}

#if DEBUG
/// The page copy `MockRepository` links to with `-debug.replicaFixture YES`: a stand-in bank login page as
/// replica.js writes it (CSP meta, `shoo-replica` meta with marks), so previews and the UI gate show the
/// copy, the "Copy of the page" line and both spotlight variants.
struct FixtureReplicaLoader: ReplicaLoading {
    func html(at url: URL) async throws -> String {
        let meta = #"{&quot;v&quot;:1,&quot;url&quot;:&quot;https://bca-verifikasi.site/login/pin&quot;,&quot;capturedAt&quot;:&quot;2026-10-31T03:42:00Z&quot;,&quot;focusY&quot;:300,&quot;truncated&quot;:false,&quot;marks&quot;:[{&quot;signalId&quot;:&quot;asks_pin&quot;,&quot;x&quot;:24,&quot;y&quot;:332,&quot;w&quot;:342,&quot;h&quot;:52},{&quot;signalId&quot;:&quot;unreasonable_request&quot;,&quot;x&quot;:24,&quot;y&quot;:420,&quot;w&quot;:342,&quot;h&quot;:44},{&quot;signalId&quot;:&quot;unreasonable_request&quot;,&quot;x&quot;:24,&quot;y&quot;:560,&quot;w&quot;:342,&quot;h&quot;:52}]}"#
        // Absolute positions, so the marks above sit exactly on their elements.
        func box(_ top: Int, _ height: Int, _ style: String, _ text: String = "") -> String {
            #"<div style="position:absolute;left:24px;width:342px;top:\#(top)px;height:\#(height)px;\#(style)">\#(text)</div>"#
        }
        let field = "box-sizing:border-box;border:1px solid #c9d3df;border-radius:10px;background:#fff"
        let body = [
            #"<div style="position:absolute;left:0;top:0;width:390px;height:64px;background:#0a5cab;color:#fff;font-weight:700;font-size:20px;line-height:64px;text-indent:24px">KlikBCA</div>"#,
            box(92, 30, "font-size:22px;font-weight:700", "Verifikasi Akun Anda"),
            box(130, 44, "font-size:15px;color:#4b5868", "Akun Anda dibekukan sementara. Selesaikan verifikasi dalam 15 menit."),
            box(304, 20, "font-size:14px;font-weight:600", "PIN KlikBCA (6 digit)"),
            box(332, 52, field),
            box(420, 44, "font-size:15px;color:#b42318;font-weight:600", "Transfer biaya aktivasi Rp 150.000 untuk membuka akun"),
            box(532, 20, "font-size:14px;font-weight:600", "Nomor rekening tujuan"),
            box(560, 52, field),
            box(644, 52, "border-radius:26px;background:#0a5cab;color:#fff;text-align:center;line-height:52px;font-weight:700", "Verifikasi Sekarang"),
        ].joined()
        return """
            <!doctype html><html><head><meta charset="utf-8">\
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">\
            <meta name="viewport" content="width=device-width,initial-scale=1">\
            <meta name="shoo-replica" content="\(meta)"><title>KlikBCA - Verifikasi Akun</title></head>\
            <body style="margin:0;position:relative;height:1000px;font-family:-apple-system,Helvetica,sans-serif;background:#f3f6fa;color:#1d2733">\
            \(body)</body></html>
            """
    }
}
#endif

