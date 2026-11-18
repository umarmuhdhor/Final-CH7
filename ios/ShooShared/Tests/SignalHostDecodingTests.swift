import Foundation
import Testing
@testable import Shoo

/// #497: layer 1–2 address signals may carry `host: { marks, official }` (contracts/detector-interface.md "host").
/// The field is optional: scans stored before it, and every other signal, must keep decoding.
struct SignalHostDecodingTests {
    private func signal(_ extra: String) throws -> Signal {
        let json = #"{"id":"brand_plus_keyword","layer":2,"weight":14,"label":{"en":"a","id":"b"},"labelSimple":{"en":"c","id":"d"}"#
            + extra + "}"
        return try JSONDecoder.shoo.decode(Signal.self, from: Data(json.utf8))
    }

    @Test func decodesMarksAndOfficial() throws {
        let s = try signal(#","evidence":"bca · level 2 · verifikasi","host":{"marks":["bca","verifikasi"],"official":"bca.co.id"}"#)
        #expect(s.host == Signal.Host(marks: ["bca", "verifikasi"], official: "bca.co.id"))
    }

    @Test func decodesBrand() throws {
        let s = try signal(#","host":{"marks":["bca"],"official":"bca.co.id","brand":"BCA"}"#)
        #expect(s.host == Signal.Host(marks: ["bca"], official: "bca.co.id", brand: "BCA"))
        #expect(try signal(#","host":{"official":"bca.co.id"}"#).host?.brand == nil)
    }

    @Test func decodesMarksOnly() throws {
        let s = try signal(#","host":{"marks":[".site"]}"#)
        #expect(s.host?.marks == [".site"])
        #expect(s.host?.official == nil)
    }

    @Test func decodesOfficialOnly() throws {
        let s = try signal(#","host":{"official":"bca.co.id"}"#)
        #expect(s.host?.marks == nil)
        #expect(s.host?.official == "bca.co.id")
    }

    @Test func missingHostIsNil() throws {
        #expect(try signal("").host == nil)
        #expect(try signal(#","host":null"#).host == nil)
    }

    @Test func unknownKeysInHostAreIgnored() throws {
        let s = try signal(#","host":{"marks":["bca"],"later":1}"#)
        #expect(s.host?.marks == ["bca"])
    }

    @Test func encodesWithoutHostWhenNil() throws {
        let original = try signal("")
        let data = try JSONEncoder.shoo.encode(original)
        #expect(!String(decoding: data, as: UTF8.self).contains("host"))
        let withHost = try signal(#","host":{"marks":["p0stindonesia"],"official":"posindonesia.co.id"}"#)
        #expect(try JSONDecoder.shoo.decode(Signal.self, from: JSONEncoder.shoo.encode(withHost)) == withHost)
    }
}
