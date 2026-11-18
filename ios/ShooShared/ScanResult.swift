import Foundation

/// Mirrors contracts/scan-result.schema.json. Change the contract first, then this file.
struct ScanResult: Codable, Identifiable, Hashable {
    var id: String
    var url: URL
    var domain: String
    var pageTitle: String?
    var faviconUrl: URL?
    var score: Int
    var status: ScanStatus
    var signals: [Signal]
    var screenshotUrl: URL?
    var pageReplicaUrl: URL?
    var ownerDeviceId: String
    var ownerName: String
    var detectedAt: Date
    var verdict: Verdict?
}

/// `unknown` = a status this build does not know (a newer backend, #493). Decoding never throws on a new
/// string, so one new value can't make a whole list fail; show it as "unknown status", don't drop the row.
enum ScanStatus: String, Codable, Hashable {
    case warning
    case blocked
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ScanStatus(rawValue: raw) ?? .unknown
    }
}

struct Signal: Codable, Hashable {
    var id: String
    var layer: Int
    var weight: Int
    var label: LocalizedText
    var labelSimple: LocalizedText
    var evidence: String?
    /// Layer 1–2 address signals only (#497, DT-04 address card). nil = mark the whole domain.
    var host: Host?

    /// contracts/scan-result.schema.json#/$defs/SignalHost, rules in contracts/detector-interface.md "host".
    struct Host: Codable, Hashable {
        /// Substrings of `ScanResult.domain` to highlight, as written there (lowercase, punycode), max 4, in reading
        /// order. nil = no precise part. Ignore a mark not found in the domain.
        var marks: [String]?
        /// The brand's real domain (e.g. "bca.co.id"), only on `lookalike_domain` and `brand_plus_keyword`.
        var official: String?
        /// The brand's display name (e.g. "BCA"), sent with `official`. Detail's "Ringkasan" names it (DT-04).
        var brand: String?
    }
}

/// Text in both app languages (contracts/scan-result.schema.json#/$defs/LocalizedText).
struct LocalizedText: Codable, Hashable {
    var en: String
    var id: String

    /// Picks the text for a language code ("id" → Bahasa Indonesia, anything else → English).
    func text(for languageCode: String?) -> String {
        languageCode == "id" ? id : en
    }
}

struct Verdict: Codable, Hashable {
    /// `unknown` = a verdict this build does not know (#493), decoded instead of throwing. Read-only:
    /// never send it back (`POST /verdicts` takes `safe` / `not_safe` only).
    enum Value: String, Codable, Hashable {
        case safe
        case notSafe = "not_safe"
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Value(rawValue: raw) ?? .unknown
        }
    }

    var value: Value
    var byDeviceId: String
    var byName: String
    var decidedAt: Date
}

/// Built-in score thresholds (PRD §5 defaults). The live values come from `GET /config/public`; see #383. Owner: lead.
enum ScoreThreshold {
    static let firstWarning = 30
    static let secondWarning = 50
    static let blocked = 80
}

extension JSONDecoder {
    /// Decoder matching the API: ISO 8601 UTC dates, with or without fractional seconds
    /// (the backend sends `2026-10-21T04:05:00.123Z`; blocklist cursors carry microseconds).
    /// `.iso8601` alone rejects fractions on older Foundation (iOS 17), so try both shapes.
    static var shoo: JSONDecoder {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = withFraction.date(from: text) ?? withoutFraction.date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected an ISO 8601 date, got \"\(text)\"")
        }
        return decoder
    }
}

extension JSONEncoder {
    static var shoo: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
