//
//  ClipboardKeyStore.swift
//  thenotch
//

import CryptoKit
import Foundation
import Security

/// The key the clipboard history is sealed with. Never written to a file
/// or a log.
protocol ClipboardKeyProviding: Sendable {
    /// The key, created if there's none yet.
    func key() throws -> SymmetricKey
    /// Replaces the key with a new one (what was sealed with the old one
    /// can't be read any more).
    func rotate() throws -> SymmetricKey
    /// Deletes the key (no error if there's none).
    func delete() throws
}

enum ClipboardKeyError: Error, Equatable {
    case keychain(OSStatus)
    /// The stored item isn't a 256-bit key.
    case invalidKeyData
    case randomFailed(OSStatus)
}

/// The key as a generic password in the login keychain (the file-based
/// keychain: the data protection keychain needs a Team ID), never synced.
/// `kSecAttrAccessible` is set for a future move to the data protection
/// keychain; the file-based keychain ignores it (its items are readable
/// while the login keychain is unlocked, by the apps its access list allows).
struct KeychainKeyStore: ClipboardKeyProviding {
    var service = "\(AppIdentity.bundleID).clipboard"
    var account = "history-key"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    func key() throws -> SymmetricKey {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else {
                throw ClipboardKeyError.invalidKeyData
            }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return try add()
        default:
            throw ClipboardKeyError.keychain(status)
        }
    }

    func rotate() throws -> SymmetricKey {
        try delete()
        return try add()
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ClipboardKeyError.keychain(status)
        }
    }

    private func add() throws -> SymmetricKey {
        var bytes = Data(count: 32)
        let random = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard random == errSecSuccess else { throw ClipboardKeyError.randomFailed(random) }
        var query = baseQuery
        query[kSecValueData as String] = bytes
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecAttrLabel as String] = "\(AppIdentity.name) clipboard history"
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw ClipboardKeyError.keychain(status) }
        return SymmetricKey(data: bytes)
    }
}
