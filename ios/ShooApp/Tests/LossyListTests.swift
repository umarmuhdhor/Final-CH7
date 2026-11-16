import Foundation
import Testing
@testable import Shoo

/// Issue #493 part 1: one row the app can't read must not hide the whole list. `GET /scans` and
/// `GET /family/members` decode row by row: bad rows are dropped, good rows and the cursor stay.
struct LossyListTests {
    // MARK: Rows

    /// A scan row as contracts/scan-result.schema.json has it.
    private static func scan(_ id: String, score: String = "41", owner: String? = #""ownerDeviceId":"dev_mom","#,
                             signals: String = "[]") -> String {
        """
        {"id":"\(id)","url":"https://bca-verifikasi.site/login","domain":"bca-verifikasi.site","pageTitle":null,
         "faviconUrl":null,"score":\(score),"status":"warning","signals":\(signals),"screenshotUrl":null,
         \(owner ?? "")"ownerName":"Mom","detectedAt":"2026-10-21T04:05:00Z","verdict":null}
        """
    }

    /// Wrong type, missing required field, nested object of a shape the app doesn't know, and `null`.
    private static let badScans = [
        scan("bad_type", score: #""high""#),
        scan("bad_missing", owner: nil),
        scan("bad_nested", signals: #"[{"kind":"ml_v2","payload":{"x":1}}]"#),
        "null",
    ]

    private static func member(_ id: String, active: String = "true", name: String? = #""name":"Mom","#,
                               lastScan: String = "null") -> String {
        """
        {"deviceId":"\(id)",\(name ?? "")"avatarId":"avatar_03","extensionActive":\(active),"lastScan":\(lastScan)}
        """
    }

    private static let badMembers = [
        member("bad_type", active: #""yes""#),
        member("bad_missing", name: nil),
        member("bad_nested", lastScan: #"{"kind":"ml_v2","score":50}"#),
        "null",
    ]

    private static func scanPage(_ rows: [String], cursor: String? = "cur_2") -> String {
        #"{"items":[\#(rows.joined(separator: ","))],"nextCursor":\#(cursor.map { "\"\($0)\"" } ?? "null")}"#
    }

    private static func membersBody(_ rows: [String]) -> String {
        #"{"members":[\#(rows.joined(separator: ","))]}"#
    }

    // MARK: GET /scans

    @Test(arguments: badScans)
    func scansKeepTheGoodRowsAndTheCursorAroundOneBadRow(bad: String) async throws {
        let server = StubServer()
        let body = Self.scanPage([Self.scan("good_1"), bad, Self.scan("good_2")])
        server.reply { _ in .json(200, body) }
        let page = try await server.repository().scans(owner: .family, status: nil, cursor: nil)
        #expect(page.items.map(\.id) == ["good_1", "good_2"])
        #expect(page.nextCursor == "cur_2")
    }

    @Test func scansKeepTheGoodRowsAmongManyBadOnes() async throws {
        let server = StubServer()
        let body = Self.scanPage(Self.badScans + [Self.scan("good_1")] + Self.badScans)
        server.reply { _ in .json(200, body) }
        let page = try await server.repository().scans(owner: .me, status: nil, cursor: "cur_1")
        #expect(page.items.map(\.id) == ["good_1"])
        #expect(page.nextCursor == "cur_2")
    }

    @Test func scansPageOfOnlyBadRowsIsEmptyNotAnError() async throws {
        let server = StubServer()
        let body = Self.scanPage(Self.badScans)
        server.reply { _ in .json(200, body) }
        let page = try await server.repository().scans(owner: .family, status: nil, cursor: nil)
        #expect(page.items.isEmpty)
        // The next page may still have rows the app can read.
        #expect(page.nextCursor == "cur_2")
    }

    @Test func lastScansPageWithABadRowEndsWithoutACursor() async throws {
        let server = StubServer()
        let body = Self.scanPage([Self.scan("good_1"), Self.badScans[0]], cursor: nil)
        server.reply { _ in .json(200, body) }
        let page = try await server.repository().scans(owner: .family, status: nil, cursor: "cur_2")
        #expect(page.items.map(\.id) == ["good_1"])
        #expect(page.nextCursor == nil)
    }

    /// Only rows are forgiven: a page that isn't a page still breaks the contract.
    @Test(arguments: [
        #"{"items":{"id":"x"},"nextCursor":null}"#,
        #"{"nextCursor":null}"#,
        #"{"items":[],"nextCursor":42}"#,
        #"[]"#,
    ])
    func scansPageWithoutAnItemsListIsStillADecodingError(body: String) async {
        let server = StubServer()
        server.reply { _ in .json(200, body) }
        await #expect(throws: RepositoryError.decoding) {
            try await server.repository().scans(owner: .family, status: nil, cursor: nil)
        }
    }

    // MARK: GET /family/members

    @Test(arguments: badMembers)
    func familyKeepsTheGoodMembersAroundOneBadRow(bad: String) async throws {
        let server = StubServer()
        let body = Self.membersBody([Self.member("dev_mom"), bad, Self.member("dev_dad", active: "false")])
        server.reply { _ in .json(200, body) }
        let members = try await server.repository().familyMembers()
        #expect(members.map(\.deviceId) == ["dev_mom", "dev_dad"])
    }

    @Test func familyOfOnlyBadRowsIsEmptyNotAnError() async throws {
        let server = StubServer()
        let body = Self.membersBody(Self.badMembers)
        server.reply { _ in .json(200, body) }
        #expect(try await server.repository().familyMembers().isEmpty)
    }

    @Test(arguments: [#"{"members":null}"#, #"{}"#, #"{"members":"dev_mom"}"#])
    func familyWithoutAMembersListIsStillADecodingError(body: String) async {
        let server = StubServer()
        server.reply { _ in .json(200, body) }
        await #expect(throws: RepositoryError.decoding) {
            try await server.repository().familyMembers()
        }
    }

    // MARK: The list itself

    @Test func lossyListKeepsOrderAndSkipsEveryKindOfBadElement() throws {
        let json = #"[1, "two", null, 3, {"x":1}, [4], 5.5, 6]"#
        let list = try JSONDecoder.shoo.decode(LossyList<Int>.self, from: Data(json.utf8))
        #expect(list.elements == [1, 3, 6])
        #expect(list.dropped == 5)
    }

    /// The log names the contract field, never a value from the row (P6).
    @Test(arguments: [
        (badScans[0], "score"),
        (badScans[1], "ownerDeviceId"),
        (badScans[2], "signals.[].id"),
        (badScans[3], "(row)"),
    ])
    func lossyListNamesTheFieldThatFailedWithoutItsValue(bad: String, field: String) throws {
        let list = try JSONDecoder.shoo.decode(LossyList<ScanResult>.self, from: Data("[\(bad)]".utf8))
        #expect(list.elements.isEmpty && list.dropped == 1)
        #expect(list.firstProblem == field)
    }

    @Test func lossyListOfNothingIsEmpty() throws {
        let list = try JSONDecoder.shoo.decode(LossyList<Int>.self, from: Data("[]".utf8))
        #expect(list.elements.isEmpty)
        #expect(list.dropped == 0)
    }

    /// Encoding is unchanged: the mock and the fixtures round-trip as before.
    @Test func scanPageEncodesAsAPlainList() throws {
        let page = try JSONDecoder.shoo.decode(ScanPage.self, from: Data(Self.scanPage([Self.scan("good_1")]).utf8))
        let again = try JSONDecoder.shoo.decode(ScanPage.self, from: JSONEncoder.shoo.encode(page))
        #expect(again == page)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder.shoo.encode(page)) as? [String: Any])
        #expect((object["items"] as? [Any])?.count == 1)
    }
}
