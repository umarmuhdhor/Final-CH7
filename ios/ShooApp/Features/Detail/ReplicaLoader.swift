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
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > Self.maxHTMLBytes { throw ReplicaLoadError.unavailable }
        }
        guard let html = String(data: data, encoding: .utf8) else { throw ReplicaLoadError.unavailable }
        return html
    }

    /// Our Worker's `/replicas/` path only, over HTTPS (SECURITY §3 P5);
    /// plain HTTP only for the local Worker (`wrangler dev`) in Debug builds.
    static func isAllowed(_ url: URL, host allowedHost: String) -> Bool {
        guard let host = url.host(), host == allowedHost,
              url.path().hasPrefix("/replicas/"), !url.path().contains("..")
        else { return false }
        if url.scheme == "https" { return url.port == nil }
        #if DEBUG
        return url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host)
        #else
        return false
        #endif
    }
}
