import Foundation

// App-only types shaped exactly like the JSON in contracts/api.md.
// Shared models (ScanResult, Signal, Verdict, UserMode) live in ShooShared — never redefine them here.

/// `POST /devices` response.
struct DeviceRegistration: Codable, Hashable, Sendable {
    var deviceId: String
    var token: String
    var avatarId: String
}

/// `POST /devices/me/protected` (PF-01 proposed, "Punya kode undangan?"): the new protected device
/// that replaced this guardian device, and the guardian it joined.
struct ProtectedSwitch: Codable, Hashable, Sendable {
    var deviceId: String
    var token: String
    var avatarId: String
    var guardian: GuardianInfo

    var registration: DeviceRegistration { DeviceRegistration(deviceId: deviceId, token: token, avatarId: avatarId) }
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

/// `stats` in `GET /devices/me` (PF-01, proposed in backend/API.md): lifetime counters, kept past the
/// 14-day retention, and when the device registered.
struct ProfileStats: Codable, Hashable, Sendable {
    var blocked: Int
    var warnings: Int
    var since: Date
}

/// `GET /devices/me` response.
struct DeviceProfile: Codable, Hashable, Sendable {
    var deviceId: String
    var name: String
    var avatarId: String
    var mode: UserMode
    var language: String?
    var guardian: GuardianInfo?
    /// PF-01 proposed; `nil` from a server without it (the stats row is hidden).
    var stats: ProfileStats?
    /// PF-01 proposed (Pengaturan/Notifikasi): the phone's IANA zone the server uses for quiet hours.
    var timeZone: String?
    /// PF-01 proposed; `nil` from a server without it (the page shows the defaults).
    var notifications: NotificationSettings?
}

/// PF-01 "Pengaturan/Notifikasi" (proposed). Kept on the server, which decides which pushes go out.
struct NotificationSettings: Codable, Hashable, Sendable {
    /// "Situs berbahaya": your own warning scans.
    var warning: Bool
    /// "Situs diblokir": your own blocked scans.
    var blocked: Bool
    /// Guardian: "Aktivitas orang dilindungi".
    var family: Bool
    /// Guardian: "Perlindungan mati".
    var protectionOff: Bool
    /// "Ringkasan mingguan", Monday 08:00.
    var weeklySummary: Bool
    /// "Jam tenang": warnings wait; blocked sites still push.
    var quietHours: Bool
    /// Local 24-hour "HH:MM".
    var quietStart: String
    var quietEnd: String

    /// The server's defaults (migration 20261028130000).
    static let defaults = NotificationSettings(
        warning: true, blocked: true, family: true, protectionOff: true, weeklySummary: false,
        quietHours: true, quietStart: "22:00", quietEnd: "06:00"
    )
}

extension NotificationSettings {
    /// These settings with the keys `update` sets.
    func applying(_ update: NotificationSettingsUpdate) -> NotificationSettings {
        var s = self
        if let v = update.warning { s.warning = v }
        if let v = update.blocked { s.blocked = v }
        if let v = update.family { s.family = v }
        if let v = update.protectionOff { s.protectionOff = v }
        if let v = update.weeklySummary { s.weeklySummary = v }
        if let v = update.quietHours { s.quietHours = v }
        if let v = update.quietStart { s.quietStart = v }
        if let v = update.quietEnd { s.quietEnd = v }
        return s
    }

    /// A failed update undone: the `keys` it still owns go back to `before`; every other key keeps what is on
    /// screen now (fase 27i, K11).
    func reverting(_ keys: Set<NotificationSettingsUpdate.Key>, to before: NotificationSettings) -> NotificationSettings {
        var s = self
        for key in keys {
            switch key {
            case .warning: s.warning = before.warning
            case .blocked: s.blocked = before.blocked
            case .family: s.family = before.family
            case .protectionOff: s.protectionOff = before.protectionOff
            case .weeklySummary: s.weeklySummary = before.weeklySummary
            case .quietHours: s.quietHours = before.quietHours
            case .quietStart: s.quietStart = before.quietStart
            case .quietEnd: s.quietEnd = before.quietEnd
            }
        }
        return s
    }
}

/// Only the switches that changed; `nil` keys are left out of `PATCH /devices/me`.
struct NotificationSettingsUpdate: Codable, Hashable, Sendable {
    var warning: Bool?
    var blocked: Bool?
    var family: Bool?
    var protectionOff: Bool?
    var weeklySummary: Bool?
    var quietHours: Bool?
    var quietStart: String?
    var quietEnd: String?

    enum Key: Hashable, CaseIterable { case warning, blocked, family, protectionOff, weeklySummary, quietHours, quietStart, quietEnd }

    /// The keys this update sets.
    var keys: Set<Key> {
        let set: [(Key, Bool)] = [
            (.warning, warning != nil), (.blocked, blocked != nil), (.family, family != nil),
            (.protectionOff, protectionOff != nil), (.weeklySummary, weeklySummary != nil),
            (.quietHours, quietHours != nil), (.quietStart, quietStart != nil), (.quietEnd, quietEnd != nil),
        ]
        return Set(set.filter(\.1).map(\.0))
    }
}

/// `PATCH /devices/me` body. `nil` fields are left out of the request.
struct DeviceUpdate: Codable, Hashable, Sendable {
    var name: String?
    var apnsToken: String?
    var language: String?
    var extensionLastSeenAt: Date?
    /// PF-01 proposed: "iPhone 15" and "26" on the guardian's member detail.
    var deviceModel: String?
    var osVersion: String?
    /// PF-01 proposed "Ubah foto": one of the onboarding avatars.
    var avatarId: String?
    /// PF-01 proposed: IANA zone ("Asia/Makassar") for quiet hours and the weekly summary.
    var timeZone: String?
    var notifications: NotificationSettingsUpdate?
    /// EX-03 (#49): `Activity<ScoreActivityAttributes>.pushToStartTokenUpdates` as hex; `.clear` sends `null`.
    var liveActivityStartToken: Clearable<String>?
    /// EX-03 (#49): the running island's `id` and `pushTokenUpdates` token; `.clear` (`null`) once it ended.
    var liveActivityUpdateToken: Clearable<LiveActivityUpdateToken>?
}

/// `{ activityId, token }` of `PATCH /devices/me` (contracts/api.md "Live score (Dynamic Island)").
struct LiveActivityUpdateToken: Codable, Hashable, Sendable {
    var activityId: String
    var token: String
}

/// A `PATCH` field that can be set or cleared: `.set(x)` encodes `x`, `.clear` encodes JSON `null`.
/// (A plain optional can't say "clear": `nil` leaves the key out.)
enum Clearable<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    case set(Value)
    case clear

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = container.decodeNil() ? .clear : .set(try container.decode(Value.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .set(let value): try container.encode(value)
        case .clear: try container.encodeNil()
        }
    }
}

/// `POST /family/code` response. 6 digits, valid 30 min, `inviteUrl` = `https://<api host>/j/<code>`.
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

    /// `stats` of a member (PF-01 proposed).
    struct Stats: Codable, Hashable, Sendable {
        var blocked: Int
        var warnings: Int
    }

    var deviceId: String
    var name: String
    var avatarId: String
    var extensionActive: Bool
    var lastScan: LastScan?
    // PF-01 proposed (backend/API.md): `nil` from a server without them, and the row is hidden.
    /// "Terhubung sejak".
    var connectedAt: Date?
    /// Last extension heartbeat ("aktif 2 mnt lalu").
    var lastSeenAt: Date?
    var deviceModel: String?
    var osVersion: String?
    /// "Kabari saya".
    var notify: Bool?
    /// Last "Ingatkan" push.
    var remindedAt: Date?
    var stats: Stats?

    var id: String { deviceId }
}

/// `GET /family/members` response.
struct FamilyMembersResponse: Codable, Hashable, Sendable {
    var members: [FamilyMember]
}

/// One line of the Home card "Scam terbaru di pengguna Shoo" (Figma 955:10323). Not in contracts/ yet.
struct ScamCase: Hashable, Identifiable, Sendable {
    let id: String
    /// "Situs palsu BCA minta PIN m-banking".
    let title: String
    /// "Hari ini · lewat link SMS".
    let detail: String
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
    // Member reminder (PF-01 proposed)
    static let pushUnavailable: APIErrorCode = "push_unavailable"
    static let remindTooSoon: APIErrorCode = "remind_too_soon"
    // Guardian → Protected (PF-01 proposed)
    static let hasMembers: APIErrorCode = "has_members"
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
    /// A 429 (`rate_limited`, `too_many_attempts`) that said how long to wait (`Retry-After`, contracts/api.md).
    case throttled(APIErrorCode, message: String, retryAfter: TimeInterval)

    var apiCode: APIErrorCode? {
        switch self {
        case .api(let code, _), .throttled(let code, _, _): code
        case .network, .decoding: nil
        }
    }

    /// Seconds the server asked to wait before the next try, when it said.
    var retryAfter: TimeInterval? {
        if case .throttled(_, _, let seconds) = self { return seconds }
        return nil
    }
}
