import Foundation
import UIKit

/// PF-01 member detail ("iPhone 15 · iOS 26"): the marketing name and the major iOS version only,
/// sent with `PATCH /devices/me` and shown to the guardian. Nothing that identifies this one device.
enum DeviceInfo {
    /// "iPhone 15", or "iPhone" / "iPad" for a model this table does not know yet.
    @MainActor
    static var modelName: String {
        modelName(identifier: identifier, fallback: UIDevice.current.model)
    }

    /// "26".
    static var osMajorVersion: String {
        String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    /// Pure, so tests cover the table. `fallback` is `UIDevice.model` ("iPhone", "iPad").
    static func modelName(identifier: String, fallback: String) -> String {
        if let name = names[identifier] { return name }
        return fallback.hasPrefix("iPad") ? "iPad" : "iPhone"
    }

    /// "iPhone15,4"; the simulator reports the model it simulates.
    private static var identifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    /// iPhones that run iOS 26 and later. Only letters, digits, spaces and parentheses (backend rule).
    private static let names: [String: String] = [
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,3": "iPhone 17", "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,4": "iPhone Air",
    ]
}
