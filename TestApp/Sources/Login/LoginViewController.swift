//
//  Copyright 2021 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import UIKit

protocol LoginDelegate {
    func refreshLibrary()
}

class LoginViewController: UIViewController, UITextFieldDelegate {
    
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    
    var delegate : LoginDelegate?
    
    private lazy var closeButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(closeModal))
    
    override func viewDidLoad() {
        self.navigationItem.rightBarButtonItem = closeButton
        self.navigationItem.title = "Login"
        
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.emailTextField.becomeFirstResponder()
#if DEBUG
        emailTextField.text = "sanchari.som@gmail.com"//"shuvra@zabingo.com"
        passwordTextField.text = "3ab4b67f"//"ae3adc81"
#endif
        super.viewDidAppear(animated)
    }
    
    @objc func closeModal() {
        self.dismiss(animated: true) {}
    }
    
    @IBAction func forgotPasswordButtonTapped(_ sender: Any) {
        let alert = UIAlertController(title: "Forgot Password?", message: "Click on the side menu of the web store and go to profile to change your password.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in }))
        self.present(alert, animated: true)
    }
    
    @IBAction func loginButtonTapped(_ sender: Any) {
        login()
    }
    
    func login() {
        if (!Reachability.isConnectedToNetwork()) {
            toast("Network connection problem.", on: self.view, duration: 2)
            return
        }
        
        let uuid = UIDevice.current.identifierForVendor?.uuidString ?? ""
        var app_version = ""
        if let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            app_version = ver
        }
        let ram = ProcessInfo.processInfo.physicalMemory / 1073741824
        var systemInfo = utsname()
        uname(&systemInfo)
        let processor = withUnsafePointer(to: &systemInfo.machine.0) { ptr in
            return String(cString: ptr)
        }
        let device_model = UIDevice.current.name
        let device_os = UIDevice.current.systemVersion
        var isVirtual = 0
#if targetEnvironment(simulator)
        isVirtual = 1
#endif
        
#if DEBUG
        isVirtual = 0
#endif
        var postString = ""
        if let email = emailTextField.text, let pass = passwordTextField.text {
            if (email.count > 0 && pass.count > 0) {
                postString = "email=\(email)&password=\(pass)&device_type=iOS&device_id=\(uuid)&uuid=\(uuid)&app_version=\(app_version)&ram=\(ram)GB&processor=\(processor)&device_os=\(device_os)&device_model=\(device_model)&manufacturer=Apple&serial=NA&isVirtual=\(isVirtual)&isRooted=0"
            } else { return }
        } else { return }
        print("login data: ", postString)
        let hideActivity = toastActivity(on: view)
        
        let loginUrl = URL(string: APILink.BASE_URL + APILink.LOGIN)!
        var request = URLRequest(url: loginUrl)
        request = SharedFunctions.setRequestHeader(request: request, method: "POST")
        // postString = "email=test1@test.com&password=12345"
        
        request.httpBody = postString.data(using: .utf8)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            
            DispatchQueue.main.async {
                hideActivity()
            }
            
            guard let data = data,
                  let response = response as? HTTPURLResponse,
                  error == nil else {
                print("error", error ?? "Unknown error")
                return
            }
            
            guard (200 ... 299) ~= response.statusCode else {
                print("statusCode should be 2xx, but is \(response.statusCode)")
                print("response = \(response)")
                return
            }
            
            do {
                let parsedData = try JSONSerialization.jsonObject(with: data) as! [String:Any]
                print(parsedData)
                
                if (parsedData["success"] as! String == "1") {
                    if let singleObjArray = parsedData["data"] as? Array<Any> {
                        if (singleObjArray.count > 0) {
                            if let dataObj = singleObjArray[0] as? [String:Any] {
                                if let access_token = dataObj["access_token"] as? String,
                                   let refresh_token = dataObj["refresh_token"] as? String {
                                    TokenManager.shared.save(accessToken: access_token, refreshToken: refresh_token)
                                }
                                if let cusPic = dataObj["customers_picture"] as? String {
                                    let cusPicUrl = APILink.SITE_URL + cusPic
                                    UserDefaults.standard.setValue(cusPicUrl, forKey: "user_profile_picture")
                                }
                                if let cusFName = dataObj["customers_firstname"] as? String {
                                    var cusName = cusFName
                                    if let cusLName = dataObj["customers_lastname"] as? String {
                                        cusName = cusFName + " " + cusLName
                                    }
                                    
                                    if (cusName.count > 0) {
                                        UserDefaults.standard.setValue(cusName, forKey: "user_full_name")
                                    }
                                }
                                // show logout & sync library
                                DispatchQueue.main.async {
                                    NotificationCenter.default.post(name: .reloadAboutTableNotification, object: nil, userInfo: ["controller" : self])
                                }
                            }
                        }
                    }
                    DispatchQueue.main.async {
                        self.closeModal()
                    }
                } else {
                    if let msg = parsedData["message"] as? String {
                        DispatchQueue.main.async {
                            let alert = UIAlertController(title: "Login error", message: msg, preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in }))
                            self.present(alert, animated: true)
                        }
                    }
                }
            } catch let error as NSError {
                print(error)
            }
        }
        
        task.resume()
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if (textField == emailTextField) {
            passwordTextField.becomeFirstResponder()
        } else if (textField == passwordTextField) {
            login()
        }
        return true
    }
}
