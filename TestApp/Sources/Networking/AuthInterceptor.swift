//
//  AuthInterceptor.swift.swift
//  TestApp
//
//  Created by Shuvra Karmakar on 22/04/25.
//

import Foundation
import UIKit

class AuthInterceptor {
    static let shared = AuthInterceptor()

    private var isRefreshing = false
    private var pendingRequests: [(URLRequest) -> Void] = []

    func intercept(request: URLRequest, completion: @escaping (URLRequest) -> Void) {
        print("\ncall intercepted")
        guard let newRequest = buildNewRequestWithNewAccessToken(request: request) else {
            print("error building new request")
            if let libraryVC = AuthURLProtocol.libraryVC {
                libraryVC.startStopRefresh(shouldStart: false)
            }
            return
        }
        completion(newRequest)
    }
    
    func buildNewRequestWithNewAccessToken(request: URLRequest) -> URLRequest? {
        if var bodyString = AuthURLProtocol.requestBodyString,
           let newAccessToken = TokenManager.shared.getAccessToken(),
           let url = request.url,
           let method = request.httpMethod {
            print("\nold token bodyString: ", bodyString)
            if let lastElement = bodyString.components(separatedBy: "access_token=").last,
               let oldAccessToken = lastElement.components(separatedBy: "&").first,
               oldAccessToken.count > 0 {
                bodyString = bodyString.replacingOccurrences(of: oldAccessToken, with: newAccessToken)
            }
            print("new token bodyString: ", bodyString)
            
            var newBuildRequest = URLRequest(url: url)
            newBuildRequest = SharedFunctions.setRequestHeader(request: newBuildRequest, method: method)
            newBuildRequest.httpBody = bodyString.data(using: .utf8)
            let config = URLSessionConfiguration.default
            config.protocolClasses = [AuthURLProtocol.self]
            AuthURLProtocol.requestBodyString = bodyString
            
            return newBuildRequest
        }
        return nil
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
            
            if success {
                for callback in retries {
                    guard let newBuildRequest = buildNewRequestWithNewAccessToken(request: originalRequest) else {
                        print("error building new request")
                        if let libraryVC = AuthURLProtocol.libraryVC {
                            libraryVC.startStopRefresh(shouldStart: false)
                        }
                        return
                    }
                    callback(newBuildRequest)
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
              let url = URL(string: APILink.BASE_URL + APILink.REFRESH_TOKEN) else {
            completion(false)
            return
        }
        let uuid = UIDevice.current.identifierForVendor?.uuidString ?? ""
        var request = URLRequest(url: url)
        request = SharedFunctions.setRequestHeader(request: request, method: "POST")
        let postString = "refresh_token=\(refreshToken)&device_id=\(uuid)"
        print("\nrefresh token url: ", url)
        print("refresh token data: ", postString)
        request.httpBody = postString.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let response = response as? HTTPURLResponse,
                  error == nil else {
                print("error", error ?? "Unknown error")
                if let libraryVC = AuthURLProtocol.libraryVC {
                    libraryVC.startStopRefresh(shouldStart: false)
                }
                return
            }
            
            guard (200 ... 299) ~= response.statusCode else {
                print("statusCode should be 2xx, but is \(response.statusCode)")
                print("response = \(response)")
                if let libraryVC = AuthURLProtocol.libraryVC {
                    libraryVC.startStopRefresh(shouldStart: false)
                }
                return
            }

            do {
                let parsedData = try JSONSerialization.jsonObject(with: data) as! [String:Any]
                print("\nrefresh token parsedData: ", parsedData)
                if let success = parsedData["success"] as? String {
                    if success == "1",
                       let data = parsedData["data"] as? [String:String],
                       let newAccess = data["access_token"],
                       let newRefresh = data["refresh_token"],
                       newAccess.count > 0,
                       newRefresh.count > 0 {
                        TokenManager.shared.save(accessToken: newAccess, refreshToken: newRefresh)
                        completion(true)
                    } else {
                        print("logout")
                        // clear user data
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                            SharedFunctions.clearUserData()
                            if let appdel = UIApplication.shared.delegate as? AppDelegate {
                                let alert = UIAlertController(title: "Session Ended", message: "Your session has expired or this device has been de-authorized.", preferredStyle: .alert)
                                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in }))
                                appdel.window?.rootViewController?.present(alert, animated: true)
                            }
                            completion(false)
                        })
                    }
                } else {
                    completion(false)
                    return
                }
            } catch let error as NSError {
                print(error)
                completion(false)
            }
        }.resume()
    }
}
