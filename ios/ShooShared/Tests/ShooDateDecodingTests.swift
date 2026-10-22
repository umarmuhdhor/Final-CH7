import Foundation
import Testing
@testable import Shoo

/// `JSONDecoder.shoo` must read the backend's timestamps on every supported iOS (17+):
/// with no fraction, milliseconds and microseconds, all with a `Z` suffix.
struct ShooDateDecodingTests {
    private struct Stamp: Decodable {
        var at: Date
    }

    private func decode(_ text: String) throws -> Date {
        try JSONDecoder.shoo.decode(Stamp.self, from: Data(#"{"at":"\#(text)"}"#.utf8)).at
    }

    /// 2026-10-21T04:05:00Z
    private let whole = Date(timeIntervalSince1970: 1_792_555_500)

    @Test func decodesWithoutFraction() throws {
        #expect(try decode("2026-10-21T04:05:00Z") == whole)
    }

    @Test func decodesMilliseconds() throws {
        let date = try decode("2026-10-21T04:05:00.123Z")
        #expect(abs(date.timeIntervalSince(whole) - 0.123) < 0.0005)
    }

    @Test func decodesMicroseconds() throws {
        let date = try decode("2026-10-21T04:05:00.123456Z")
        #expect(abs(date.timeIntervalSince(whole) - 0.123456) < 0.001)
    }

    @Test(arguments: ["2026-10-21", "21/10/2026 04:05", "2026-13-40T99:99:99Z", ""])
    func rejectsInvalidDate(text: String) {
        #expect(throws: DecodingError.self) { try decode(text) }
    }

    @Test func encoderOutputStillDecodes() throws {
        let data = try JSONEncoder.shoo.encode(["at": whole])
        #expect(String(decoding: data, as: UTF8.self) == #"{"at":"2026-10-21T04:05:00Z"}"#)
        #expect(try JSONDecoder.shoo.decode(Stamp.self, from: data).at == whole)
    }
}
