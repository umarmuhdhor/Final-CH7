import Foundation

/// Links that open the app (contracts/app-group-keys.md "Deep links"). Anything unknown or malformed
/// is `.unknown` and opens Shield. Nothing here acts on its own: a join link only fills in the code.
enum DeepLink: Equatable {
    /// `shoo://join?code=1234`, or the invite page `https://<api host>/join?code=1234` (QR, PR-03).
    case join(code: String)
    /// `shoo://scan/{scanId}`: Detail on the Activity tab (D-alief-C13).
    case scan(id: String)
    /// `shoo://activity`: the Activity list.
    case activity
    case unknown

    /// Hosts whose `/join` page is ours: the backend this build talks to, and the cloud Worker.
    static let inviteHosts: Set<String> = Set([AppConfig.apiBaseURL.host(), "shoo-api.afindo-mi01.workers.dev"].compactMap { $0 })

    init(url: URL, inviteHosts: Set<String> = DeepLink.inviteHosts) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let scheme = url.scheme?.lowercased()
        if scheme == "shoo" {
            switch url.host()?.lowercased() {
            case "join": self = Self.join(from: components)
            case "scan":
                let id = url.pathComponents.dropFirst().first ?? ""
                self = APIClient.isPlainSegment(id) && url.pathComponents.count == 2 ? .scan(id: id) : .unknown
            case "activity": self = .activity
            default: self = .unknown
            }
        } else if scheme == "https" || scheme == "http",
                  let host = url.host()?.lowercased(), inviteHosts.contains(host), url.path() == "/join" {
            self = scheme == "https" || Self.isLocalWorker(url) ? Self.join(from: components) : .unknown
        } else {
            self = .unknown
        }
    }

    /// `http` only for the Worker this build talks to over http (`wrangler dev` in Debug): same host and
    /// port. Release talks https only, so no http link is ever accepted there.
    static func isLocalWorker(_ url: URL, api: URL = AppConfig.apiBaseURL) -> Bool {
        api.scheme == "http" && url.scheme?.lowercased() == "http"
            && url.host()?.lowercased() == api.host()?.lowercased() && url.port == api.port
    }

    /// Exactly four ASCII digits, the only code shape the backend issues (R4 §1, T13).
    static func isCode(_ text: String) -> Bool {
        text.count == 4 && text.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
    }

    private static func join(from components: URLComponents?) -> DeepLink {
        let codes = (components?.queryItems ?? []).filter { $0.name == "code" }
        guard codes.count == 1, let code = codes[0].value, isCode(code) else { return .unknown }
        return .join(code: code)
    }
}
