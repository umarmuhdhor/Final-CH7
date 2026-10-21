import Foundation

// App-only types shaped exactly like the JSON in contracts/api.md.
// Shared models (ScanResult, Signal, Verdict, UserMode) live in ShooShared — never redefine them here.

/// `POST /devices` response.
struct DeviceRegistration: Codable, Hashable, Sendable {
    var deviceId: String
    var token: String
    var avatarId: String
}

/// `guardian` object in `GET /devices/me` and `POST /family/join`.
struct GuardianInfo: Codable, Hashable, Sendable {
    var deviceId: String
    var name: String
    var avatarId: String
}

/// `POST /family/join` response.
struct JoinResponse: Codable, Hashable, Sendable {
    var guardian: GuardianInfo
}

/// `GET /devices/me` response.
struct DeviceProfile: Codable, Hashable, Sendable {
    var deviceId: String
    var name: String
    var avatarId: String
    var mode: UserMode
    var language: String?
    var guardian: GuardianInfo?
}

/// `PATCH /devices/me` body. `nil` fields are left out of the request.
struct DeviceUpdate: Codable, Hashable, Sendable {
    var name: String?
    var apnsToken: String?
    var language: String?
    var extensionLastSeenAt: Date?
}

/// `POST /family/code` response. Valid for 60 s.
struct FamilyCode: Codable, Hashable, Sendable {
    var code: String
    var expiresAt: Date
    var inviteUrl: URL
}

/// One entry of `GET /family/members`.
struct FamilyMember: Codable, Hashable, Identifiable, Sendable {
    struct LastScan: Codable, Hashable, Sendable {
        var status: ScanStatus
        var score: Int
        var url: URL
        var detectedAt: Date
    }

    var deviceId: String
    var name: String
    var avatarId: String
    var extensionActive: Bool
    var lastScan: LastScan?

    var id: String { deviceId }
}

/// `GET /family/members` response.
struct FamilyMembersResponse: Codable, Hashable, Sendable {
    var members: [FamilyMember]
}

/// `GET /scans` response.
struct ScanPage: Codable, Hashable, Sendable {
    var items: [ScanResult]
    var nextCursor: String?
}

/// `POST /verdicts` response.
struct VerdictResponse: Codable, Hashable, Sendable {
    var verdict: Verdict
}

/// `owner=` filter of `GET /scans`.
enum ScanOwnerFilter: Hashable, Sendable {
    case me
    /// The guardian's own scans plus their protected members' (contracts/api.md).
    case family
    case device(String)

    var queryValue: String {
        switch self {
        case .me: "me"
        case .family: "family"
        case .device(let id): id
        }
    }
}

/// Error codes from contracts/api.md. Open set: unknown server codes still decode.
struct APIErrorCode: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    var rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }

    // Common
    static let invalidBody: APIErrorCode = "invalid_body"
    static let badJSON: APIErrorCode = "bad_json"
    static let tooLarge: APIErrorCode = "too_large"
    static let rateLimited: APIErrorCode = "rate_limited"
    static let `internal`: APIErrorCode = "internal"
    // Backend-specific (plan/alief/ref/R3 §1)
    static let unauthorized: APIErrorCode = "unauthorized"
    static let forbidden: APIErrorCode = "forbidden"
    static let notFound: APIErrorCode = "not_found"
    static let codeUnavailable: APIErrorCode = "code_unavailable"
    // Join (PR-01, PR-03)
    static let codeInvalid: APIErrorCode = "code_invalid"
    static let codeExpired: APIErrorCode = "code_expired"
    static let familyFull: APIErrorCode = "family_full"
    static let tooManyAttempts: APIErrorCode = "too_many_attempts"
    static let alreadyConnected: APIErrorCode = "already_connected"
    // Verdicts (GD-07)
    static let verdictNotAllowed: APIErrorCode = "verdict_not_allowed"
}

/// `{ "error": { "code", "message" } }` body (contracts/api.md).
struct APIErrorBody: Codable, Hashable, Sendable {
    struct Detail: Codable, Hashable, Sendable {
        var code: String
        var message: String
    }

    var error: Detail
}

/// Everything a `ShooRepository` call can throw.
enum RepositoryError: Error, Hashable, Sendable {
    /// The backend answered with a contract error code.
    case api(APIErrorCode, message: String)
    /// No connection, timeout, TLS failure.
    case network
    /// The response did not match the contract.
    case decoding

    var apiCode: APIErrorCode? {
        if case .api(let code, _) = self { return code }
        return nil
    }
}
