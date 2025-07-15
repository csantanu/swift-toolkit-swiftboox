//
//  ImageCacheManager.swift
//  TestApp
//
//  Created by Shuvra Karmakar on 19/06/25.
//

import UIKit

class ImageCacheManager {
    static let shared = ImageCacheManager()
    let cache = NSCache<NSString, UIImage>()

    private init() {}
    
    func clear() {
        cache.removeAllObjects()
    }

    func image(forKey key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}
