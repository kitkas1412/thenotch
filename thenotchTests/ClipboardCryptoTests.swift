//
//  ClipboardCryptoTests.swift
//  thenotchTests
//

import CryptoKit
import Foundation
import Testing
@testable import thenotch

struct ClipboardCryptoTests {
    let crypto = ClipboardCrypto(key: SymmetricKey(size: .bits256))
    let plain = Data("clipboard secret".utf8)

    @Test func roundTripForIndexAndBlob() throws {
        let id = UUID()
        let index = try crypto.seal(plain, role: .index, itemID: nil)
        let blob = try crypto.seal(plain, role: .blob, itemID: id)
        #expect(try crypto.open(index, role: .index, itemID: nil) == plain)
        #expect(try crypto.open(blob, role: .blob, itemID: id) == plain)
        #expect(index.prefix(5) == Data("TNCB".utf8) + [1])
        #expect(!index.contains(subsequence: plain))
    }

    @Test func sealingTwiceGivesDifferentOutput() throws {
        let a = try crypto.seal(plain, role: .index, itemID: nil)
        let b = try crypto.seal(plain, role: .index, itemID: nil)
        #expect(a != b)
    }

    @Test func wrongKeyFailsAuthentication() throws {
        let sealed = try crypto.seal(plain, role: .index, itemID: nil)
        let other = ClipboardCrypto(key: SymmetricKey(size: .bits256))
        #expect(throws: ClipboardCrypto.Error.authenticationFailed) {
            try other.open(sealed, role: .index, itemID: nil)
        }
    }

    @Test func tamperedByteFailsAuthentication() throws {
        var sealed = try crypto.seal(plain, role: .index, itemID: nil)
        sealed[sealed.count - 1] ^= 0x01
        #expect(throws: ClipboardCrypto.Error.authenticationFailed) {
            try crypto.open(sealed, role: .index, itemID: nil)
        }
    }

    @Test func truncatedBoxFailsAuthentication() throws {
        let sealed = try crypto.seal(plain, role: .index, itemID: nil)
        #expect(throws: ClipboardCrypto.Error.authenticationFailed) {
            try crypto.open(sealed.prefix(8), role: .index, itemID: nil)
        }
    }

    @Test func wrongRoleFails() throws {
        let sealed = try crypto.seal(plain, role: .blob, itemID: nil)
        #expect(throws: ClipboardCrypto.Error.authenticationFailed) {
            try crypto.open(sealed, role: .index, itemID: nil)
        }
    }

    @Test func swappedItemIDFails() throws {
        let sealed = try crypto.seal(plain, role: .blob, itemID: UUID())
        #expect(throws: ClipboardCrypto.Error.authenticationFailed) {
            try crypto.open(sealed, role: .blob, itemID: UUID())
        }
        #expect(throws: ClipboardCrypto.Error.authenticationFailed) {
            try crypto.open(sealed, role: .blob, itemID: nil)
        }
    }

    @Test(arguments: [Data(), Data("TNC".utf8), Data("XXXX\u{1}rest-of-file".utf8)])
    func badMagic(bytes: Data) {
        #expect(throws: ClipboardCrypto.Error.badMagic) {
            try crypto.open(bytes, role: .index, itemID: nil)
        }
    }

    @Test func unsupportedVersionReportsIt() throws {
        var sealed = try crypto.seal(plain, role: .index, itemID: nil)
        sealed[4] = 0x02
        #expect(throws: ClipboardCrypto.Error.unsupportedVersion(2)) {
            try crypto.open(sealed, role: .index, itemID: nil)
        }
    }
}

private extension Data {
    func contains(subsequence: Data) -> Bool { range(of: subsequence) != nil }
}
