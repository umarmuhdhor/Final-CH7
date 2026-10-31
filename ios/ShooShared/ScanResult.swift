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

enum ScanStatus: String, Codable, Hashable {
    case warning
    case blocked
}

struct Signal: Codable, Hashable {
    var id: String
    var layer: Int
    var weight: Int
    var label: LocalizedText
    var labelSimple: LocalizedText
    var evidence: String?
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
    enum Value: String, Codable, Hashable {
        case safe
        case notSafe = "not_safe"
    }

    var value: Value
    var byDeviceId: String
    var byName: String
    var decidedAt: Date
}

/// Score thresholds from PRD §5. Owner: lead.
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
