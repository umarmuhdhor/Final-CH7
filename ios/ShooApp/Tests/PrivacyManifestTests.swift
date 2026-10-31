import Foundation
import Testing
@testable import Shoo

/// Fase 24 K12 (SECURITY §3 P1/P2): the app's privacy manifest declares everything the backend keeps,
/// linked to the device, for App Functionality only, never tracking.
struct PrivacyManifestTests {
    private static func manifest() throws -> [String: Any] {
        let url = RepoPaths.root.appending(path: "ios/ShooApp/PrivacyInfo.xcprivacy")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test func declaresEveryKeptDataType() throws {
        let manifest = try Self.manifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        let types = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let names = Set(types.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        let expected: Set<String> = [
            "Name", "BrowsingHistory", "OtherUserContent", "DeviceID",
            "UserID", "ProductInteraction", "CoarseLocation", "OtherDataTypes",
        ]
        #expect(names == Set(expected.map { "NSPrivacyCollectedDataType\($0)" }))
        for type in types {
            #expect(type["NSPrivacyCollectedDataTypeLinked"] as? Bool == true)
            #expect(type["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
            #expect(type["NSPrivacyCollectedDataTypePurposes"] as? [String] == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        }
    }
}
