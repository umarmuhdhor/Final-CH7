import Foundation
import Testing
@testable import Shoo

/// #493: a status or verdict value this build does not know decodes to `.unknown` instead of throwing,
/// so one new server value can't make a whole list (`GET /scans`, `GET /family/members`) fail.
struct ShooEnumDecodingTests {
    private struct StatusBox: Codable, Equatable {
        var status: ScanStatus
    }

    private struct ValueBox: Codable, Equatable {
        var value: Verdict.Value
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.shoo.decode(type, from: Data(json.utf8))
    }

    @Test func unknownStatusDecodesToUnknown() throws {
        #expect(try decode(StatusBox.self, #"{"status":"reviewing"}"#).status == .unknown)
    }

    @Test func unknownVerdictValueDecodesToUnknown() throws {
        #expect(try decode(ValueBox.self, #"{"value":"maybe"}"#).value == .unknown)
    }

    @Test(arguments: [ScanStatus.warning, .blocked])
    func knownStatusRoundTrips(status: ScanStatus) throws {
        let data = try JSONEncoder.shoo.encode(StatusBox(status: status))
        #expect(String(decoding: data, as: UTF8.self) == #"{"status":"\#(status.rawValue)"}"#)
        #expect(try JSONDecoder.shoo.decode(StatusBox.self, from: data).status == status)
    }

    @Test(arguments: [Verdict.Value.safe, .notSafe])
    func knownVerdictValueRoundTrips(value: Verdict.Value) throws {
        let data = try JSONEncoder.shoo.encode(ValueBox(value: value))
        #expect(try JSONDecoder.shoo.decode(ValueBox.self, from: data).value == value)
    }

    @Test func notSafeKeepsItsWireName() throws {
        #expect(try decode(ValueBox.self, #"{"value":"not_safe"}"#).value == .notSafe)
        let data = try JSONEncoder.shoo.encode(ValueBox(value: .notSafe))
        #expect(String(decoding: data, as: UTF8.self) == #"{"value":"not_safe"}"#)
    }

    @Test func unknownEncodesAsUnknown() throws {
        let data = try JSONEncoder.shoo.encode(StatusBox(status: .unknown))
        #expect(String(decoding: data, as: UTF8.self) == #"{"status":"unknown"}"#)
    }

    /// A non-string value is still malformed JSON for the contract, not a new enum value.
    @Test func nonStringStillThrows() {
        #expect(throws: DecodingError.self) { try decode(StatusBox.self, #"{"status":3}"#) }
    }

    /// The case from the issue: a full scan whose status and verdict are both new still decodes.
    @Test func scanWithNewValuesDecodes() throws {
        let json = #"""
        {"id":"s1","url":"https://example.com/","domain":"example.com","score":70,"status":"reviewing",
         "signals":[],"ownerDeviceId":"d1","ownerName":"Maria","detectedAt":"2026-10-21T04:05:00Z",
         "verdict":{"value":"maybe","byDeviceId":"g1","byName":"Virellia","decidedAt":"2026-10-21T05:00:00Z"}}
        """#
        let scan = try decode(ScanResult.self, json)
        #expect(scan.status == .unknown)
        #expect(scan.verdict?.value == .unknown)
    }
}
