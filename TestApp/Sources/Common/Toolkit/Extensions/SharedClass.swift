//
//  Copyright 2021 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import UIKit
import Foundation
import DeviceCheck

class APILink {
    
    // PRODUCTION
//    static let SITE_URL = "https://swiftboox.app/controlcenter/"
//    static let SITE_URL = "http://139.59.78.111/laravel/index.php/api/"
    static let SITE_URL = "https://swiftboox.app/laravel/index.php/api/"
    static let RESOURCE_IMAGES_PATH = "https://swiftboox.app/laravel/resources/assets/images/"
    static let COVER_PATH = RESOURCE_IMAGES_PATH + "product_images/"
    static let USER_PROFILE_PICS_PATH = RESOURCE_IMAGES_PATH + "user_profile/"
    static let CONSUMER_KEY = "7317b3421578662816a7ca806a"
    static let CONSUMER_SECRET = "a54e136d15786628168150910e"
    static let ONE_SIGNAL_APP_ID = "0b168cbe-e74a-4a3b-b36a-e27edafa17db"
    
    // DEV
//    static let SITE_URL = "https://dev.swiftboox.app/"
//    static let CONSUMER_KEY = "b79af61515620772648791af4d"
//    static let CONSUMER_SECRET = "7971287d1562077264f86fa19b"
//    static let ONE_SIGNAL_APP_ID = "51ade5bd-f6de-4a45-95c6-d5039dd5399d"
    
    static let REGISTER_DEVICE = "registerdevices"
    
    static let BASE_URL = SITE_URL // + "app/"
//    static let BASE_URL = SITE_URL + "app/"
    
    static let LOGIN = "processloginapp" // "processlogin"
    static let LOGOUT = "processlogoutapp" // "processlogout"
    static let GET_CUSTOMER_BOOKS = "getcustomersbooklist" // "getcustomersbooklist" // "getcustomersbookrecords"
    static let DOWNLOAD_BOOK = "getbookdetail" // "getbookdetail" // "getcustomersbookrecordsdetail"
    static let REMOVE_BOOK = "removecustomersbook" // "removecustomersbook" // "removecustomersbooks"
    static let REFRESH_TOKEN = "processrefresstoken"
}

class SharedFunctions {
    
    class func setRequestHeader (request: URLRequest, method: String) -> URLRequest {
        var req = request
        let time = Int(NSDate().timeIntervalSince1970)
        let deviceId = UIDevice.current.identifierForVendor!.uuidString
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(APILink.CONSUMER_KEY.md5(), forHTTPHeaderField: "consumer-key")
        req.setValue(APILink.CONSUMER_SECRET.md5(), forHTTPHeaderField: "consumer-secret")
        req.setValue("\(time)", forHTTPHeaderField: "consumer-nonce")
        req.setValue(deviceId, forHTTPHeaderField: "consumer-device-id")
        req.httpMethod = method
        return req
    }
    
    class func clearUserData(controller: Any? = nil) {
        // clear stored tokens
        TokenManager.shared.clearTokens()
        UserDefaults.standard.setValue(nil, forKey: "user_profile_picture")
        UserDefaults.standard.setValue(nil, forKey: "user_full_name")
        // clear image cache
        ImageCacheManager.shared.clear()
        // remove all books
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: {
            NotificationCenter.default.post(name: .removeAllBooksNotification, object: nil, userInfo: ["controller" : controller ?? 1])
        })
    }
}

extension String {
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    static let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
}

func print(_ objects: Any...) {
    #if DEBUG
    for item in objects {
        Swift.print(item)
    }
    #endif
}

func print(_ object: Any) {
    #if DEBUG
    Swift.print(object)
    #endif
}

enum BookFilter: Int {
    case all = 0
    case purchased
    case samples
    case downloaded
}
