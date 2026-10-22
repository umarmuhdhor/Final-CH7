import Foundation

/// HTTP client for the Shoo backend (contracts/api.md). JSON in and out, ISO 8601 dates,
/// `Authorization: Bearer <token>` on every call except `POST /devices`.
///
/// Privacy (SECURITY §3 P6, P9, P13): an ephemeral session without URL cache, cookies or credential
/// storage, so no answer is ever written to disk; the token and request bodies are never logged.
final class APIClient: Sendable {
    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    struct Request: Sendable {
        var method: Method
        /// Path segments, percent-encoded one by one (`["scans", id]` → `/scans/<id>`).
        var path: [String]
        var query: [URLQueryItem] = []
        var body: (any Encodable & Sendable)?
        /// `false` only for `POST /devices`.
        var authorized = true
        /// A 401 here means "already gone" to the caller (e.g. `DELETE /devices/me`), not a broken session.
        var reportsUnauthorized = true
    }

    let baseURL: URL
    private let session: URLSession
    private let token: @Sendable () throws -> String?
    /// Called on 401, or when an authorized call has no token at all (backup restored onto another iPhone).
    private let onUnauthorized: @Sendable () -> Void

    init(
        baseURL: URL,
        configuration: URLSessionConfiguration = APIClient.configuration(),
        token: @escaping @Sendable () throws -> String?,
        onUnauthorized: @escaping @Sendable () -> Void = {}
    ) {
        self.baseURL = baseURL
        session = URLSession(configuration: configuration, delegate: RedirectRefusal(), delegateQueue: nil)
        self.token = token
        self.onUnauthorized = onUnauthorized
    }

    /// Nothing about our users stays on disk (P13): no URL cache, no cookies, no credentials.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return configuration
    }

    func send<Response: Decodable>(_ request: Request, as type: Response.Type = Response.self) async throws -> Response {
        let data = try await perform(request)
        do {
            return try JSONDecoder.shoo.decode(Response.self, from: data)
        } catch {
            Log.data.error("Response did not match the contract", request.path.first ?? "")
            throw RepositoryError.decoding
        }
    }

    func urlRequest(for request: Request) throws -> URLRequest {
        // Ids come from the server and from deep links (`shoo://scan/{id}`, T15): a segment that isn't a
        // plain id (`..`, `/`, `%2e`) never leaves the app; to the caller it is a scan that doesn't exist.
        guard request.path.allSatisfy(Self.isPlainSegment) else {
            throw RepositoryError.api(.notFound, message: "Invalid id")
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.percentEncodedPath = "/" + request.path.joined(separator: "/")
        components?.queryItems = request.query.isEmpty ? nil : request.query
        guard let url = components?.url else { throw RepositoryError.decoding }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.authorized {
            let stored: String?
            do {
                stored = try token()
            } catch {
                // Keychain locked (before the first unlock): try later, the session is fine.
                throw RepositoryError.network
            }
            guard let token = stored else {
                if request.reportsUnauthorized { onUnauthorized() }
                throw RepositoryError.api(.unauthorized, message: "No device session")
            }
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = request.body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONEncoder.shoo.encode(body)
        }
        return urlRequest
    }

    private func perform(_ request: Request) async throws -> Data {
        let urlRequest = try urlRequest(for: request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            if error.isCancellation || Task.isCancelled { throw CancellationError() }
            throw RepositoryError.network
        }
        guard let http = response as? HTTPURLResponse else { throw RepositoryError.network }
        guard (200..<300).contains(http.statusCode) else {
            let error = Self.error(status: http.statusCode, body: data)
            if error.apiCode == .unauthorized, request.authorized, request.reportsUnauthorized {
                onUnauthorized()
            }
            throw error
        }
        return data
    }

    /// The contract error body, or a common code from the HTTP status when the body is not one
    /// (a proxy page, an empty 502).
    static func error(status: Int, body: Data) -> RepositoryError {
        if let detail = try? JSONDecoder().decode(APIErrorBody.self, from: body).error {
            return .api(APIErrorCode(rawValue: detail.code), message: detail.message)
        }
        let code: APIErrorCode = switch status {
        case 401: .unauthorized
        case 403: .forbidden
        case 404: .notFound
        case 413: .tooLarge
        case 429: .rateLimited
        default: .internal
        }
        return .api(code, message: "HTTP \(status)")
    }
}

/// `{ "ok": true }` answers.
struct OkResponse: Decodable, Sendable {
    var ok: Bool
}

extension APIClient {
    /// Route names and ids: letters, digits, `_` and `-` only (UUIDs, `dev_…`), at most 128.
    static func isPlainSegment(_ segment: String) -> Bool {
        (1...128).contains(segment.count)
            && segment.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-") }
    }
}

/// The backend never redirects; following one could send the Bearer token over another scheme or path.
private final class RedirectRefusal: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
