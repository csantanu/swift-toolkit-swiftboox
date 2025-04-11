//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI

extension Notification.Name {
    static let reloadAboutTableNotification = Notification.Name("reloadAboutTableNotification")
    static let removeAllBooksNotification = Notification.Name("removeAllBooksNotification")
}

struct AboutView: View {
    
    @State private var presenHowToUse = false
    @State private var presenHowToRead = false
    @State private var presenLogoutConfirmation = false
    @State private var presenCantLogout = false
    @State private var showAccountSection = false
    @State var showLoggedOutAlert = false
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .center, spacing: 20) {
                versionSection
                helpSection
                supportSection
                if showAccountSection {
                    logoutSection
                }
            }
            .padding(.horizontal, 16)
        }.sheet(isPresented: $presenHowToUse) {
            HowToUseView()
        }.sheet(isPresented: $presenHowToRead) {
            HowToReadView()
        }.alert("Confirm Logout", isPresented: $presenLogoutConfirmation) {
            Button(NSLocalizedString("confirm_button", comment: ""), role: .destructive) {
                showAccountSection = false
                // clear stored user id
                UserDefaults.standard.setValue(nil, forKey: "user_id")
                UserDefaults.standard.setValue(nil, forKey: "user_profile_picture")
                UserDefaults.standard.setValue(nil, forKey: "user_full_name")
                // remove all books
                NotificationCenter.default.post(name: .removeAllBooksNotification, object: nil, userInfo: ["controller" : self])
            }
            Button(NSLocalizedString("cancel_button", comment: ""), role: .cancel) {}
        } message: {
            Text("All your downloaded books will be removed from this device. Are you sure you want to log out?")
        }.alert("Can't Logout", isPresented: $presenCantLogout) {
            Button(NSLocalizedString("ok_button", comment: ""), role: .cancel) {}
        } message: {
            Text("Library refresh is in progress. Can't log out now. Try after refreshing is done.")
        }
        .alert("Logged out", isPresented: $showLoggedOutAlert) {
            Button("OK", role: .cancel) {}
        } message: {}
        .onReceive(NotificationCenter.default.publisher(for: .reloadAboutTableNotification, object: nil)) { _ in
            showAccountSection = true
        }
        .onAppear {
            if let userId = UserDefaults.standard.value(forKey: "user_id") as? String,
               userId.count > 0 {
                showAccountSection = true
            }
        }
    }

    private var versionSection: some View {
        AboutSectionView(
            title: "Version",
            icon: .app
        ) {
            VStack {
                HStack {
                    Text("App Version:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(.appVersion ?? "")
                        .foregroundColor(.primary)
                }

                HStack(spacing: 10) {
                    Text("Build Version:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(.buildVersion ?? "")
                        .foregroundColor(.primary)
                }
            }
        }
    }

    private var helpSection: some View {
        AboutSectionView(
            title: "Help",
            icon: .help
        ) {
            VStack {
                Button(action: {
                    presenHowToUse = true
                }, label: {
                    HStack {
                        Text("How to use this app")
                            .foregroundColor(.secondary)
                        Spacer()
                        Image(systemName: "greaterthan.circle")
                    }
                    .padding(.bottom)
                })
                Button(action: {
                    presenHowToRead = true
                }, label: {
                    HStack(spacing: 10) {
                        Text("How to read eBooks in the app")
                            .foregroundColor(.secondary)
                        Spacer()
                        Image(systemName: "greaterthan.circle")
                    }
                })
            }
        }
    }

    private var supportSection: some View {
        AboutSectionView(
            title: "Support",
            icon: .support
        ) {
            VStack() {
                Text("For any problem or queries, send us an email to swiftboox@gmail.com")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var logoutSection: some View {
        AboutSectionView(
            title: "Account",
            icon: .account
        ) {
            VStack() {
                if let userName = UserDefaults.standard.value(forKey: "user_full_name") as? String,
                   userName.count > 0 {
                    Text("Signed in as \(userName)")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.bottom)
                }
                HStack {
                    Button(action: { // logout
                        if let appdel = UIApplication.shared.delegate as? AppDelegate {
                            if (appdel.isRefreshingLibrary == false) {
                                presenLogoutConfirmation = true
                            } else {
                                presenCantLogout = true
                            }
                        }
                    }, label: {
                        Text("Logout")
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.red)
                    })
                }
            }
        }
    }
}

struct About_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}

private extension String {
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    static let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
}

private extension URL {
    static let edrlab = URL(string: "https://www.edrlab.org/")!
    static let license = URL(string: "https://opensource.org/licenses/BSD-3-Clause")!
}
