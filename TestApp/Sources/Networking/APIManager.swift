//
//  APIManager.swift
//  TestApp
//
//  Created by Shuvra Karmakar on 22/04/25.
//

import Foundation

class APIManager {
    static let shared = APIManager()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.protocolClasses = [AuthURLProtocol.self]
        self.session = URLSession(configuration: config)
    }

    func login(email: String, password: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://yourapi.com/api/login") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ["email": email, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        session.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let access = json["accessToken"],
                  let refresh = json["refreshToken"] else {
                completion(false)
                return
            }

            TokenManager.shared.save(accessToken: access, refreshToken: refresh)
            completion(true)
        }.resume()
    }

    func logout() {
        TokenManager.shared.clearTokens()
    }
}
