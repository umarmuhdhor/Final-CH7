import Testing
@testable import Shoo

struct DeviceInfoTests {
    @Test(arguments: [
        ("iPhone15,4", "iPhone", "iPhone 15"),
        ("iPhone99,1", "iPhone", "iPhone"),
        ("iPad99,1", "iPad", "iPad"),
    ])
    func modelNameUsesTheTableOrTheFamily(identifier: String, fallback: String, expected: String) {
        #expect(DeviceInfo.modelName(identifier: identifier, fallback: fallback) == expected)
    }

    /// The backend accepts only `^[A-Za-z0-9 ()]{1,40}$`.
    @Test func everyKnownNamePassesTheBackendRule() {
        for identifier in ["iPhone12,8", "iPhone15,4", "iPhone17,1", "iPhone18,1"] {
            let name = DeviceInfo.modelName(identifier: identifier, fallback: "iPhone")
            #expect(name.count <= 40)
            #expect(name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || " ()".contains($0)) })
        }
    }

    @Test func osVersionIsMajorOnly() {
        #expect(DeviceInfo.osMajorVersion.allSatisfy { $0.isNumber })
    }
}
