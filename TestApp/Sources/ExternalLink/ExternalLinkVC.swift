//
//  ExternalLinkVC.swift
//  TestApp
//
//  Created by Shuvra Karmakar on 17/06/25.
//

import UIKit

class ExternalLinkVC: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    @IBAction func didTapContinueButton(_ sender: Any) {
        self.dismiss(animated: true) {
            if let url = URL(string: "https://swiftboox.app/?profile") {
                UIApplication.shared.open(url)
            }
        }
    }
    
    @IBAction func didTapCancelButton(_ sender: Any) {
        self.dismiss(animated: true)
    }
    
    @IBAction func didTapLearnMoreButton(_ sender: Any) {
        self.dismiss(animated: true) {
            if let url = URL(string: "https://apps.apple.com/story/id1614232807") {
                UIApplication.shared.open(url)
            }
        }
    }
}
