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
    /// Called on 401 with the token that request carried: a late answer for an older session must not
    /// end the current one.
    private let onUnauthorized: @Sendable (_ usedToken: String) -> Void

    init(
        baseURL: URL,
        configuration: URLSessionConfiguration = APIClient.configuration(),
        token: @escaping @Sendable () throws -> String?,
        onUnauthorized: @escaping @Sendable (_ usedToken: String) -> Void = { _ in }
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

    deinit {
        // The session keeps its delegate alive until it is invalidated.
        session.finishTasksAndInvalidate()
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
            // No token: never registered, or the session was just cleared (delete, expiry). A missing
            // token at launch is handled by `AppEnvironment.checkStoredSession()`.
            guard let token = stored else {
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
        let usedToken = urlRequest.value(forHTTPHeaderField: "Authorization").map { String($0.dropFirst("Bearer ".count)) }
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
            let error = Self.error(status: http.statusCode, body: data, retryAfter: Self.retryAfter(http.value(forHTTPHeaderField: "Retry-After")))
            // Only the backend's own `unauthorized` body ends the session. A 401 from a captive portal,
            // proxy or edge has no contract body and must not wipe the token and the guardian link.
            if Self.isContractUnauthorized(data), request.reportsUnauthorized, let usedToken {
                onUnauthorized(usedToken)
            }
            throw error
        }
        return data
    }

    /// `{"error":{"code":"unauthorized"}}`, the body the backend sends with every 401 (backend/api/src/http/errors.ts).
    static func isContractUnauthorized(_ body: Data) -> Bool {
        guard let detail = try? JSONDecoder().decode(APIErrorBody.self, from: body).error else { return false }
        return APIErrorCode(rawValue: detail.code) == .unauthorized
    }

    /// The contract error body, or a common code from the HTTP status when the body is not one
    /// (a proxy page, an empty 502).
    static func error(status: Int, body: Data, retryAfter: TimeInterval? = nil) -> RepositoryError {
        if let detail = try? JSONDecoder().decode(APIErrorBody.self, from: body).error {
            let code = APIErrorCode(rawValue: detail.code)
            if status == 429, let retryAfter { return .throttled(code, message: detail.message, retryAfter: retryAfter) }
            return .api(code, message: detail.message)
        }
        let code: APIErrorCode = switch status {
        case 401: .unauthorized
        case 403: .forbidden
        case 404: .notFound
        case 413: .tooLarge
        case 429: .rateLimited
        default: .internal
        }
        if status == 429, let retryAfter { return .throttled(code, message: "HTTP 429", retryAfter: retryAfter) }
        return .api(code, message: "HTTP \(status)")
    }

    /// The longest wait taken from a `Retry-After`: a bad header can't lock a screen for days.
    static let maxRetryAfter: TimeInterval = 24 * 60 * 60

    /// `Retry-After` as seconds (what the backend sends) or an HTTP date (RFC 9110 §10.2.3); `nil` when absent or unreadable.
    static func retryAfter(_ value: String?, now: Date = Date()) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        let seconds: TimeInterval
        if let whole = Int(value) {
            seconds = TimeInterval(whole)
        } else if let date = httpDate.date(from: value) {
            seconds = date.timeIntervalSince(now).rounded(.up)
        } else {
            return nil
        }
        return min(max(seconds, 0), maxRetryAfter)
    }

    private static let httpDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
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
