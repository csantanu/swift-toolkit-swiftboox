//
//  ExternalLinkVC.swift
//  TestApp
//
//  Created by Shuvra Karmakar on 17/06/25.
//

import UIKit
import StoreKit

class ExternalLinkVC: UIViewController {
    @IBAction func didTapLink(_ sender: Any) {
        Task {
            do {
                if await ExternalLinkAccount.canOpen {
                    try await ExternalLinkAccount.open()
                }
            } catch {
                print("Failed to open external account link: \(error)")
            }
        }
    }
}
