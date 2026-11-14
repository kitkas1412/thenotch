//
//  ClipboardCrypto.swift
//  thenotch
//

import CryptoKit
import Foundation

/// Seals the history's files with AES-GCM.
///
/// Format: `TNCB` (4 bytes), version `0x01`, then the AES.GCM combined box
/// (12-byte nonce, ciphertext, 16-byte tag). The associated data is the
/// header, the file's role and the item's UUID bytes, so a blob can't be
/// swapped for another one or for the index.
struct ClipboardCrypto: Sendable {
    enum FileRole: String, Sendable {
        case index
        case blob
    }

    enum Error: Swift.Error, Equatable {
        /// Not one of our files (or truncated before the header).
        case badMagic
        /// Written by a newer version.
        case unsupportedVersion(UInt8)
        /// Wrong key, tampered with, truncated, or another file's box.
        case authenticationFailed
        case sealingFailed
    }

    static let magic = Data("TNCB".utf8)
    static let version: UInt8 = 0x01

    let key: SymmetricKey

    func seal(_ plaintext: Data, role: FileRole, itemID: UUID?) throws -> Data {
        let header = Self.header
        let combined: Data?
        do {
            combined = try AES.GCM.seal(
                plaintext, using: key,
                authenticating: Self.associatedData(header: header, role: role, itemID: itemID)
            ).combined
        } catch {
            throw Error.sealingFailed
        }
        guard let combined else { throw Error.sealingFailed }
        return header + combined
    }

    func open(_ sealed: Data, role: FileRole, itemID: UUID?) throws -> Data {
        let headerLength = Self.magic.count + 1
        guard sealed.count >= headerLength,
              sealed.prefix(Self.magic.count).elementsEqual(Self.magic)
        else { throw Error.badMagic }
        let version = sealed[sealed.startIndex + Self.magic.count]
        guard version == Self.version else { throw Error.unsupportedVersion(version) }
        do {
            let box = try AES.GCM.SealedBox(combined: sealed.dropFirst(headerLength))
            return try AES.GCM.open(
                box, using: key,
                authenticating: Self.associatedData(header: Self.header, role: role, itemID: itemID)
            )
        } catch {
            throw Error.authenticationFailed
        }
    }

    private static var header: Data { magic + [version] }

    private static func associatedData(header: Data, role: FileRole, itemID: UUID?) -> Data {
        var data = header
        data.append(Data(role.rawValue.utf8))
        if let itemID {
            data.append(withUnsafeBytes(of: itemID.uuid) { Data($0) })
        }
        return data
    }
}
