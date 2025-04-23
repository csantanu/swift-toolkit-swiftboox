//
//  TokenManager.swift
//  TestApp
//
//  Created by Shuvra Karmakar on 22/04/25.
//

import Foundation

class TokenManager {
    static let shared = TokenManager()
    private init() {}

    private let accessTokenKey = "accessToken"
    private let refreshTokenKey = "refreshToken"

    func save(accessToken: String, refreshToken: String) {
        KeychainHelper.standard.save(accessToken, service: "token", account: accessTokenKey)
        KeychainHelper.standard.save(refreshToken, service: "token", account: refreshTokenKey)
    }

    func getAccessToken() -> String? {
        return KeychainHelper.standard.read(service: "token", account: accessTokenKey)
    }

    func getRefreshToken() -> String? {
        return KeychainHelper.standard.read(service: "token", account: refreshTokenKey)
    }

    func clearTokens() {
        KeychainHelper.standard.delete(service: "token", account: accessTokenKey)
        KeychainHelper.standard.delete(service: "token", account: refreshTokenKey)
    }
}
