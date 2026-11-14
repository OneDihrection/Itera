//
//  CareChannel.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import CryptoKit
import Foundation

/// The end-to-end encrypted link between one doctor and one patient (ADR-008 revision).
///
/// One 128-bit secret, created on the doctor's iPad and handed over only in person (QR code or
/// a 26-character code), derives everything: record names in the public database and the AES-GCM
/// key for every payload. Anyone can read the public database, but without the secret record
/// names cannot be found and payloads cannot be opened or forged.
struct CareChannel: Equatable {
    /// RFC 4648 base32: no 0, 1, 8 or 9, so it reads aloud and types without look-alikes.
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    static let codeLength = 26
    static let qrPrefix = "itera-pair:"

    let secret: Data

    static func random() -> CareChannel {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return CareChannel(secret: Data(bytes))
    }

    init(secret: Data) {
        self.secret = secret
    }

    /// From a scanned QR payload or a typed code; dashes, spaces and case are ignored.
    init?(code raw: String) {
        let cleaned = raw
            .replacingOccurrences(of: Self.qrPrefix, with: "")
            .uppercased()
            .replacingOccurrences(of: "0", with: "O")
            .replacingOccurrences(of: "1", with: "I")
            .replacingOccurrences(of: "8", with: "B")
            .filter { Self.alphabet.contains($0) }

        guard cleaned.count == Self.codeLength else {
            return nil
        }

        var bits = 0
        var value = 0
        var bytes: [UInt8] = []

        for character in cleaned {
            guard let index = Self.alphabet.firstIndex(of: character) else {
                return nil
            }

            value = (value << 5) | index
            bits += 5

            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((value >> bits) & 0xFF))
            }
        }

        guard bytes.count == 16 else {
            return nil
        }

        secret = Data(bytes)
    }

    /// 26 characters for typing, also the QR payload after `qrPrefix`.
    var code: String {
        var bits = 0
        var value = 0
        var output = ""

        for byte in secret {
            value = (value << 8) | Int(byte)
            bits += 8

            while bits >= 5 {
                bits -= 5
                output.append(Self.alphabet[(value >> bits) & 31])
            }
        }

        if bits > 0 {
            output.append(Self.alphabet[(value << (5 - bits)) & 31])
        }

        return output
    }

    /// "ABCDE FGHIJ KLMNO PQRST UVWXYZ", easier to read across a desk.
    var groupedCode: String {
        let characters = Array(code)
        var start = 0

        return [5, 5, 5, 5, 6].map { size in
            defer { start += size }
            return String(characters[start..<start + size])
        }
        .joined(separator: " ")
    }

    // MARK: - Derived values

    private func derived(_ info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            salt: Data("itera.care".utf8),
            info: Data(info.utf8),
            outputByteCount: 32
        )
    }

    /// The public-database record name for one logical item, such as `prescriptions` or
    /// `results-2026-11`. Unlinkable to the patient without the secret.
    func recordName(_ logical: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(logical.utf8), using: derived("names"))
        return "c" + mac.prefix(20).map { String(format: "%02x", $0) }.joined()
    }

    /// Encrypts with AES-GCM, binding the logical name so one record cannot be swapped for another.
    func seal<Value: Encodable>(_ value: Value, as logical: String) throws -> Data {
        let plain = try JSONEncoder().encode(value)
        let box = try AES.GCM.seal(plain, using: derived("box"), authenticating: Data(logical.utf8))

        guard let combined = box.combined else {
            throw CocoaError(.coderInvalidValue)
        }

        return combined
    }

    func open<Value: Decodable>(_ type: Value.Type, from data: Data, as logical: String) throws -> Value {
        let box = try AES.GCM.SealedBox(combined: data)
        let plain = try AES.GCM.open(box, using: derived("box"), authenticating: Data(logical.utf8))
        return try JSONDecoder().decode(type, from: plain)
    }
}
