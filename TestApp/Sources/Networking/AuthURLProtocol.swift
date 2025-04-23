//
//  AuthURLProtocol.swift
//  TestApp
//
//  Created by Shuvra Karmakar on 22/04/25.
//

import Foundation

class AuthURLProtocol: URLProtocol {
    private var dataTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        return URLProtocol.property(forKey: "Handled", in: request) == nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        AuthInterceptor.shared.intercept(request: request) { authorizedRequest in
            guard let mutableRequest = (self.request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
                self.client?.urlProtocol(self, didFailWithError: NSError(domain: "InvalidRequest", code: -1, userInfo: nil))
                return
            }

            URLProtocol.setProperty(true, forKey: "Handled", in: mutableRequest)

            let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
            self.dataTask = session.dataTask(with: mutableRequest as URLRequest) { data, response, error in
                if let response = response as? HTTPURLResponse, response.statusCode == 401 {
                    AuthInterceptor.shared.handle401(for: mutableRequest as URLRequest) { _ in
                        self.client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired))
                    }
                } else {
                    if let data = data {
                        self.client?.urlProtocol(self, didLoad: data)
                    }
                    if let response = response {
                        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    }
                    self.client?.urlProtocolDidFinishLoading(self)
                }
            }
            self.dataTask?.resume()
        }
    }

    override func stopLoading() {
        dataTask?.cancel()
    }
}
