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
        
        doVersionCheckingStuff()
//        UserDefaults.standard.set("1.4", forKey: "app_version")
//        UserDefaults.standard.set(false, forKey: "version_checking_done")
        
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
        let externalLinkVC  = ExternalLinkVC(nibName: "ExternalLinkVC", bundle: nil)
        externalLinkVC.tabBarItem = makeItem(title: "catalogs_tab", image: "catalogs")

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
            externalLinkVC,
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
    
    func doVersionCheckingStuff() {
        // read version_checking_done bool value
        let versionCheckingDone = UserDefaults.standard.bool(forKey: "version_checking_done")
        // check if version checking is done
        if !versionCheckingDone {
            // read old version
            let oldVersion_og = UserDefaults.standard.string(forKey: "app_version")
            if let oldVersionStr = oldVersion_og, oldVersionStr.count > 0 {
                let oldVersionFlat = oldVersionStr.replacingOccurrences(of: ".", with: "")
                // read current version
                if let currentVersion_og = String.appVersion, currentVersion_og.count > 0 {
                    let currentVersionFlat = currentVersion_og.replacingOccurrences(of: ".", with: "")
                    // convert both to int
                    if let oldVersionInt = Int(oldVersionFlat),
                       let currentVersionInt = Int(currentVersionFlat) {
                        // copmpare & check if updated
                        if currentVersionInt > oldVersionInt {
                            // app has been updated
                            // logout user, delete old database file
                            deleteDatabaseFileBooksLogoutUser()
                            // set app_version to current version
                            UserDefaults.standard.set(currentVersion_og, forKey: "app_version")
                        }
                    }
                }
            } else {
                // logout user, delete old database file
                deleteDatabaseFileBooksLogoutUser()
                // set app_version to current version
                if let currentVersion_og = String.appVersion, currentVersion_og.count > 0 {
                    UserDefaults.standard.set(currentVersion_og, forKey: "app_version")
                }
            }
            // set version_checking_done to true
            UserDefaults.standard.set(true, forKey: "version_checking_done")
        }
    }
    
    func deleteDatabaseFileBooksLogoutUser() {
        // clear user data
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: {
            SharedFunctions.clearUserData()
        })
        
        // delete old database file
        let file = Paths.library.appendingPath("database.db", isDirectory: false)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: file.path) {
            do {
                try fileManager.removeItem(at: file.url)
                print("old database deleted")
            } catch {
                print("Failed to delete old database")
            }
            
            do {
                // delete book files
                let fileUrls = try fileManager.contentsOfDirectory(atPath: Paths.library.path)
                for fileUrl in fileUrls {
                    if fileUrl.hasSuffix("epub") ||
                        fileUrl.hasSuffix("pdf") {
                        let file = Paths.library.appendingPath(fileUrl, isDirectory: false)
                        if fileManager.fileExists(atPath: file.path) {
                            do {
                                try fileManager.removeItem(at: file.url)
                            }
                        }
                    }
                }
            } catch {
                print("Failed to delete old books")
            }
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
