import Foundation
import Testing
@testable import Shoo

/// Repo paths, read straight from the Mac's file system (the simulator can see it).
enum RepoPaths {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ShooApp
        .deletingLastPathComponent()  // ios
        .deletingLastPathComponent()
    static let contractFixtures = root.appending(path: "contracts/fixtures")
    static let appFixtures = root.appending(path: "ios/ShooApp/Data/Fixtures")
}

struct FixtureTests {
    static let scanFixtures = ["blocked-92", "blocked-marked-safe", "blocked-verified-scam", "warning-41", "warning-63"]

    @Test(arguments: scanFixtures)
    func scanFixtureDecodesToShooSharedModel(name: String) throws {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "json"))
        let scan = try JSONDecoder.shoo.decode(ScanResult.self, from: Data(contentsOf: url))
        #expect(scan.score >= ScoreThreshold.firstWarning)
        #expect(!scan.signals.isEmpty)
        #expect(scan.status == (scan.score >= ScoreThreshold.blocked ? .blocked : .warning))
    }

    @Test func activityFamilyDecodesAsScanPage() throws {
        let url = try #require(Bundle.main.url(forResource: "activity-family", withExtension: "json"))
        let page = try JSONDecoder.shoo.decode(ScanPage.self, from: Data(contentsOf: url))
        #expect(page.items.count == 5)
        #expect(page.nextCursor == nil)
    }

    @Test func familyMembersDecode() throws {
        let url = try #require(Bundle.main.url(forResource: "family-members", withExtension: "json"))
        let response = try JSONDecoder.shoo.decode(FamilyMembersResponse.self, from: Data(contentsOf: url))
        #expect(response.members.map(\.deviceId) == ["dev_mom", "dev_dad"])
        #expect(response.members[0].lastScan?.score == 92)
        #expect(response.members[1].lastScan == nil)
        #expect(response.members[1].extensionActive == false)
    }

    /// The app's copies must not drift from contracts/fixtures (the source of truth).
    @Test(arguments: scanFixtures + ["family-members"])
    func appFixtureMatchesContract(name: String) throws {
        let contract = try Data(contentsOf: RepoPaths.contractFixtures.appending(path: "\(name).json"))
        let copy = try Data(contentsOf: RepoPaths.appFixtures.appending(path: "\(name).json"))
        #expect(contract == copy)
    }

    /// activity-family.json in the app = the contract's `$ref` list, inlined in the same order.
    @Test func inlinedActivityFamilyMatchesContractRefs() throws {
        struct RefPage: Decodable {
            struct Ref: Decodable { let ref: String; enum CodingKeys: String, CodingKey { case ref = "$ref" } }
            let items: [Ref]
        }
        let refs = try JSONDecoder().decode(
            RefPage.self, from: Data(contentsOf: RepoPaths.contractFixtures.appending(path: "activity-family.json"))
        )
        let expected = try refs.items.map {
            try JSONDecoder.shoo.decode(ScanResult.self, from: Data(contentsOf: RepoPaths.contractFixtures.appending(path: $0.ref)))
        }
        let inlined = try JSONDecoder.shoo.decode(
            ScanPage.self, from: Data(contentsOf: RepoPaths.appFixtures.appending(path: "activity-family.json"))
        )
        #expect(inlined.items == expected)
    }

    @Test func contractErrorBodyDecodes() throws {
        let json = #"{ "error": { "code": "code_expired", "message": "Code expired" } }"#
        let body = try JSONDecoder.shoo.decode(APIErrorBody.self, from: Data(json.utf8))
        #expect(APIErrorCode(rawValue: body.error.code) == .codeExpired)
    }

    @Test func deviceProfileDecodesWithNullGuardian() throws {
        let json = #"{ "deviceId": "d1", "name": "Mom", "avatarId": "avatar_03", "mode": "protected", "language": "id", "guardian": null }"#
        let profile = try JSONDecoder.shoo.decode(DeviceProfile.self, from: Data(json.utf8))
        #expect(profile.mode == .protected)
        #expect(profile.guardian == nil)
    }
}
