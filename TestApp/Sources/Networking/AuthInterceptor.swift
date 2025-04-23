//
//  AuthInterceptor.swift.swift
//  TestApp
//
//  Created by Shuvra Karmakar on 22/04/25.
//

import Foundation

class AuthInterceptor {
    static let shared = AuthInterceptor()

    private var isRefreshing = false
    private var pendingRequests: [(URLRequest) -> Void] = []

    func intercept(request: URLRequest, completion: @escaping (URLRequest) -> Void) {
        guard let accessToken = TokenManager.shared.getAccessToken() else {
            completion(request)
            return
        }

        var newRequest = request
        newRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        completion(newRequest)
    }
    
    func handle401(for originalRequest: URLRequest, retry: @escaping (URLRequest) -> Void) {
        pendingRequests.append(retry)

        guard !isRefreshing else { return }

        isRefreshing = true
        refreshToken { [weak self] success in
            guard let self = self else { return }
            self.isRefreshing = false

            let retries = self.pendingRequests
            self.pendingRequests.removeAll()

            if success, let newAccessToken = TokenManager.shared.getAccessToken() {
                for callback in retries {
                    var newRequest = originalRequest
                    newRequest.setValue("Bearer \(newAccessToken)", forHTTPHeaderField: "Authorization")
                    callback(newRequest)
                }
            } else {
                for callback in retries {
                    callback(originalRequest) // Let the request fail or handle logout
                }
            }
        }
    }

    private func refreshToken(completion: @escaping (Bool) -> Void) {
        guard let refreshToken = TokenManager.shared.getRefreshToken(),
              let url = URL(string: "https://yourapi.com/api/refreshToken") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["refreshToken": refreshToken]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let newAccess = json["accessToken"],
                  let newRefresh = json["refreshToken"] else {
                completion(false)
                return
            }

            TokenManager.shared.save(accessToken: newAccess, refreshToken: newRefresh)
            completion(true)
        }.resume()
    }
}
