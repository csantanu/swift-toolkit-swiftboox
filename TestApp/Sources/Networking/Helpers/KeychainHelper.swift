//
//  KeychainHelper.swift
//  TestApp
//
//  Created by Shuvra Karmakar on 22/04/25.
//

import Foundation
import Security

final class KeychainHelper {

    static let standard = KeychainHelper()

    private init() {}

    func save(_ data: String, service: String, account: String) {
        guard let encodedData = data.data(using: .utf8) else { return }

        // Delete any existing item first
        delete(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account,
            kSecValueData as String   : encodedData
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account,
            kSecReturnData as String  : true,
            kSecMatchLimit as String  : kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard
            status == errSecSuccess,
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return value
    }

    func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
