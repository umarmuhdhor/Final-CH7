import Foundation
import Security

/// One generic-password item in the app's Keychain (SECURITY §3 P4, T3).
/// `AfterFirstUnlockThisDeviceOnly`: readable in the background after the first unlock, never synced
/// to iCloud Keychain and never restored onto another iPhone from a backup.
struct KeychainItem: Sendable {
    let service: String
    let account: String

    enum Failure: Error, Equatable {
        case status(OSStatus)
    }

    /// Stored on every write; a test reads it back (P4).
    static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    private var query: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
    }

    func read() -> String? {
        var request = query
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces any older value. Deleting first also drops an item stored with weaker accessibility.
    func write(_ value: String) throws {
        delete()
        var item = query
        item[kSecValueData] = Data(value.utf8)
        item[kSecAttrAccessible] = Self.accessibility
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.status(status) }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }

    /// The protection class actually stored (tests only).
    func storedAccessibility() -> String? {
        var request = query
        request[kSecReturnAttributes] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [CFString: Any]
        else { return nil }
        return attributes[kSecAttrAccessible] as? String
    }
}
