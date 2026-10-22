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
            kSecUseDataProtectionKeychain: true,
        ]
    }

    /// `nil` only when there is no item. Any other failure (e.g. `errSecInteractionNotAllowed` before
    /// the first unlock) throws, so a locked iPhone is never mistaken for a lost session.
    func read() throws -> String? {
        var request = query
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure.status(status) }
        return String(data: data, encoding: .utf8)
    }

    /// Updates in place, so a failed write never loses the old value; adds the item when there is none.
    func write(_ value: String) throws {
        let data = Data(value.utf8)
        let update: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: Self.accessibility]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw Failure.status(status) }
        var item = query
        item[kSecValueData] = data
        item[kSecAttrAccessible] = Self.accessibility
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure.status(added) }
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
