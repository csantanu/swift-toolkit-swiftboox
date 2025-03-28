//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import ReadiumShared
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UITabBarControllerDelegate {
    var window: UIWindow?

    private var app: AppModule!
    private var subscriptions = Set<AnyCancellable>()
    var isRefreshingLibrary = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        app = try! AppModule()

        func makeItem(title: String, image: String) -> UITabBarItem {
            UITabBarItem(
                title: NSLocalizedString(title, comment: "Library tab title"),
                image: UIImage(named: image),
                tag: 0
            )
        }

        // Library
        let libraryViewController = app.library.rootViewController
        libraryViewController.tabBarItem = makeItem(title: "bookshelf_tab", image: "bookshelf")

        // OPDS Feeds
        let opdsViewController = app.opds.rootViewController
        opdsViewController.tabBarItem = makeItem(title: "catalogs_tab", image: "catalogs")
        
        // Discover
        let storeVC = StoreVC()
        storeVC.tabBarItem = makeItem(title: "catalogs_tab", image: "catalogs")

        // About
        let aboutViewController = app.aboutViewController
        aboutViewController.tabBarItem = makeItem(title: "about_tab", image: "about")

        let tabBarController = UITabBarController()
        tabBarController.delegate = self
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = .white
        tabBarController.tabBar.standardAppearance = tabBarAppearance
        tabBarController.tabBar.scrollEdgeAppearance = tabBarAppearance
        tabBarController.viewControllers = [
            libraryViewController,
            storeVC,
            aboutViewController,
        ]

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = tabBarController
        window?.makeKeyAndVisible()

        return true
    }

    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard let url = url.anyURL.absoluteURL, let vc = window?.rootViewController else {
            return false
        }

        Task {
            do {
                try await app.library.importPublication(from: url, sender: vc, progress: { _ in })
            } catch {
                guard let error = error as? UserErrorConvertible else {
                    print(error)
                    return
                }
                vc.alert(error)
            }
        }

        return true
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if (viewController.isKind(of: StoreVC.classForCoder())) {
            let alert = UIAlertController(title: "Swiftboox", message: "This app does not support purchasing. Books purchased from our website are available to read in the Swiftboox app.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in }))
            viewController.present(alert, animated: true)
            return false
        } else {
            return true
        }
    }

    func openStore() {
        // open http://swiftboox.app/ in safari
        if let url = URL(string: "http://swiftboox.app/") {
            UIApplication.shared.open(url)
        } else {
            let alert = UIAlertController(title: "Oops!", message: "There were some problem opening http://swiftboox.app/. Please visit using your browser app.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in }))
            self.window?.rootViewController?.present(alert, animated: true)
        }
    }
}
