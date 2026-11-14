//
//  CareKeychain.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation
import Security

/// Channel secrets live in the Keychain, never in the JSON files beside the patient list.
/// Items stay on this device (not synced through iCloud Keychain) and are readable after the
/// first unlock, so a refresh can run while the iPad is locked.
enum CareKeychain {
    private static let service = "com.itera.care-channel"

    static func save(_ channel: CareChannel, account: String) {
        delete(account: account)

        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: channel.secret,
        ]
        let status = SecItemAdd(item as CFDictionary, nil)

        if status != errSecSuccess {
            NSLog("Care keychain save failed status=%d", status)
        }
    }

    static func channel(account: String) -> CareChannel? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?

        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, data.count == 16 else {
            return nil
        }

        return CareChannel(secret: data)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
