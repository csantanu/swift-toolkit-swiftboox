//
//  Copyright 2021 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import UIKit
import SwiftUI

struct HowToUseView: UIViewControllerRepresentable {
    
    typealias UIViewControllerType = HowToViewController
    
    func makeUIViewController(context: Context) -> HowToViewController {
        let vc = HowToViewController()
        vc.isHowToUse = 1
        return vc
    }
    
    func updateUIViewController(_ uiViewController: HowToViewController, context: Context) {
        
    }
}

struct HowToReadView: UIViewControllerRepresentable {
    
    typealias UIViewControllerType = HowToViewController
    var isHowToUse = 1
    
    func makeUIViewController(context: Context) -> HowToViewController {
        let vc = HowToViewController()
        vc.isHowToUse = 0
        return vc
    }
    
    func updateUIViewController(_ uiViewController: HowToViewController, context: Context) {
        
    }
}

class HowToViewController: UIViewController {
    
    var isHowToUse = 1
    
    override func viewDidLoad() {
        view.backgroundColor = .white
        
        var howToTitle = "How to use"
        if isHowToUse == 0 {
            howToTitle = "How to read"
        }
        
        let navBar = UINavigationBar(frame: CGRect(x: 0, y: 0, width: view.frame.size.width, height: 44))
        view.addSubview(navBar)
        let navItem = UINavigationItem(title: howToTitle)
        let closeItem = UIBarButtonItem(barButtonSystemItem: .done, target: nil, action: #selector(closeHowTo))
        navItem.rightBarButtonItem = closeItem
        navBar.setItems([navItem], animated: false)
        
        let textView = UITextView(frame: CGRect(x: 20, y: navBar.frame.size.height + 20, width: view.frame.size.width - 40, height: view.frame.size.height - 20))
        textView.isEditable = false
        
        if isHowToUse == 1 {
            textView.text = load(file: "howtouse")
        } else {
            textView.text = load(file: "howtoread")
        }
        view.addSubview(textView)
        
        super.viewDidLoad()
    }
    
    @objc func closeHowTo(){
        self.dismiss(animated: true, completion: nil)
    }
    
    func load(file name:String) -> String {
        if let path = Bundle.main.path(forResource: name, ofType: "txt") {
            if let contents = try? String(contentsOfFile: path) {
                return contents
            } else {
                print("Error! - This file doesn't contain any text.")
            }
        } else {
            print("Error! - This file doesn't exist.")
        }
        return ""
    }
    
}
