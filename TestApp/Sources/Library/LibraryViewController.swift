//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Kingfisher
import MobileCoreServices
import ReadiumNavigator
import ReadiumOPDS
import ReadiumShared
import ReadiumStreamer
import UIKit
import UniformTypeIdentifiers
import WebKit

protocol LibraryViewControllerFactory {
    func make() -> LibraryViewController
}

class LibraryViewController: UIViewController, Loggable, LoginDelegate {
    typealias Factory = DetailsTableViewControllerFactory

    var factory: Factory!
    private var books: [Book] = []
    var isRetrying : Bool = false
    var isAutoRefreshing : Bool = false

    weak var lastFlippedCell: PublicationCollectionViewCell?

    var library: LibraryService!

    weak var libraryDelegate: LibraryModuleDelegate?

    private var subscriptions = Set<AnyCancellable>()

    lazy var loadingIndicator = PublicationIndicator()

    private lazy var addBookButton = UIBarButtonItem(
        systemItem: .add,
        menu: UIMenu(
            children: [
                UIAction(title: "Import local publication") { [weak self] _ in
                    self?.addBookFromDevice()
                },
                UIAction(title: "Stream publication over HTTP") { [weak self] _ in
                    self?.addBookForStreaming()
                },
            ]
        )
    )
    
    private lazy var refreshLibraryButton = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshLibrary))
    
    private lazy var loginButton = UIBarButtonItem(title: "Login", style: .plain, target: self, action: #selector(invokeLogin))
    
    let activityIndicatorView = UIActivityIndicatorView.init(frame: CGRect.init(x: 0, y: 0, width: 25, height: 25))
    
    private lazy var refreshLoader = UIBarButtonItem.init(customView: activityIndicatorView)

    @IBOutlet var collectionView: UICollectionView! {
        didSet {
            collectionView.backgroundColor = #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            collectionView.contentInset = UIEdgeInsets(top: 15, left: 20,
                                                       bottom: 20, right: 20)
            collectionView.register(UINib(nibName: "PublicationCollectionViewCell", bundle: nil),
                                    forCellWithReuseIdentifier: "publicationCollectionViewCell")
            collectionView.delegate = self
            collectionView.dataSource = self
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        library.allBooks()
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case let .failure(error) = completion {
                    self.libraryDelegate?.presentError(UserError(error), from: self)
                }
            } receiveValue: { newBooks in
                self.books = newBooks
                self.collectionView.reloadData()
            }
            .store(in: &subscriptions)

        // Add long press gesture recognizer.
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))

        recognizer.minimumPressDuration = 0.5
        recognizer.delaysTouchesBegan = true
        collectionView.addGestureRecognizer(recognizer)
        collectionView.accessibilityLabel = NSLocalizedString("library_a11y_label", comment: "Accessibility label for the library collection view")

        setRightBarButton()
    }
    
    

    override func viewWillAppear(_ animated: Bool) {
        navigationController?.setNavigationBarHidden(false, animated: animated)
        
        setUserProfilePicture()
        
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(removeAllBooksNotificationHandler(_:)),
            name: .removeAllBooksNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkLoginAndStartRefresh(_:)),
            name: .reloadAboutTableNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkLoginAndStartRefresh(_:)),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        super.viewDidAppear(animated)
        
        autoRefreshLibrary()
    }

    override func viewWillDisappear(_ animated: Bool) {
        lastFlippedCell?.flipMenu()
        // NotificationCenter.default.removeObserver(self)
        super.viewWillDisappear(animated)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        collectionView?.collectionViewLayout.invalidateLayout()
    }

    static let iPadLayoutNumberPerRow: [ScreenOrientation: Int] = [.portrait: 4, .landscape: 5]
    static let iPhoneLayoutNumberPerRow: [ScreenOrientation: Int] = [.portrait: 3, .landscape: 4]

    static let layoutNumberPerRow: [UIUserInterfaceIdiom: [ScreenOrientation: Int]] = [
        .pad: LibraryViewController.iPadLayoutNumberPerRow,
        .phone: LibraryViewController.iPhoneLayoutNumberPerRow,
    ]

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        guard let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let screenWidth = view.bounds.width
        let screenHeight = view.bounds.height
        let isPortrait = screenHeight >= screenWidth
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        
        var itemWidth: CGFloat = 0.0
        
        if isPad {
            if isPortrait {
                // iPad Portrait
                itemWidth = screenWidth < 800.0 ? 160.0 : 180.0
            } else {
                // iPad Landscape
                itemWidth = screenHeight < 800.0 ? 160.0 : 180.0
            }
        } else {
            if isPortrait {
                // iPhone Portrait
                itemWidth = screenWidth < 380.0 ? 100.0 : screenWidth < 420.0 ? 110.0 : 120.0
            } else {
                // iPhone Landscape
                itemWidth = 140.0
            }
        }

        flowLayout.itemSize = CGSize(width: itemWidth, height: (itemWidth * 1.9))
        flowLayout.invalidateLayout() // Refresh the layout
    }
    
    func setRightBarButton() {
        if TokenManager.shared.isLoggedIn {
            self.navigationItem.rightBarButtonItem = refreshLibraryButton
        } else {
            self.navigationItem.rightBarButtonItem = loginButton
        }
    }
    
    func showRefreshLoader(status:Bool = false) {
        if status {
            self.navigationItem.rightBarButtonItem = refreshLoader
            activityIndicatorView.startAnimating()
            self.navigationItem.title = "Refreshing Library"
        } else {
            activityIndicatorView.stopAnimating()
            self.navigationItem.rightBarButtonItem = refreshLibraryButton
            self.navigationItem.title = "Library"
        }
    }
    
    @objc func showLoggedInUser() {
        if let userName = UserDefaults.standard.value(forKey: "user_full_name") as? String, userName.count > 0 {
            let alert = UIAlertController(title: "Swiftboox", message: "Logged in as \(userName)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("ok_button", comment: ""), style: .default, handler: nil))
            DispatchQueue.main.async {
                self.present(alert, animated: true)
            }
        }
    }
    
    fileprivate func setUserProfilePicture() {
        if ((self.navigationItem.leftBarButtonItem) != nil) {
            return
        }
        let userPic = UserDefaults.standard.value(forKey: "user_profile_picture")
        if let userPicUrl = userPic as? String, userPicUrl.count > 0 {
            DispatchQueue.global().async { [weak self] in
                if let data = try? Data(contentsOf: URL(string: userPicUrl)!) {
                    if let image = UIImage(data: data) {
                        DispatchQueue.main.async {
                            let size = CGSize(width: 30, height: 30)
                            let button = UIButton()
                            button.setImage(image, for: .normal)
                            button.frame = CGRect(origin: CGPoint.zero, size: size)
                            button.layer.cornerRadius = size.width / 2
                            button.clipsToBounds = true
                            button.addTarget(self, action: #selector(self!.showLoggedInUser), for: .touchUpInside)
                            
                            let leftBarButton = UIBarButtonItem()
                            leftBarButton.customView = button
                            self!.navigationItem.leftBarButtonItem = leftBarButton
                            
                            leftBarButton.customView?.translatesAutoresizingMaskIntoConstraints = false
                            leftBarButton.customView?.heightAnchor.constraint(equalToConstant: size.height).isActive = true
                            leftBarButton.customView?.widthAnchor.constraint(equalToConstant: size.width).isActive = true
                        }
                    }
                }
            }
        }
    }
    
    @objc func refreshLibrary() {
        if (!Reachability.isConnectedToNetwork()) {
            if !self.isAutoRefreshing {
                toast("Network connection problem", on: self.view, duration: 2)
            }else {
                self.isAutoRefreshing = false
            }
            return
        }
        
        DispatchQueue.main.async {
            self.refreshBooks()
        }
    }
    
    @objc func invokeLogin() {
        let loginvc = LoginViewController.init(nibName: "LoginViewController", bundle: nil)
        loginvc.delegate = self
        let nav = UINavigationController(rootViewController: loginvc)
        loginvc.modalPresentationStyle = .fullScreen
        self.navigationController?.present(nav, animated: true, completion: {})
    }
    
    func refreshBooks () {
        startStopRefresh(shouldStart: true)
        let url = URL(string: APILink.BASE_URL + APILink.GET_CUSTOMER_BOOKS)!
        var request = URLRequest(url: url)
        request = SharedFunctions.setRequestHeader(request: request, method: "POST")
        let uuid = UIDevice.current.identifierForVendor?.uuidString ?? ""
        guard let access_token = TokenManager.shared.getAccessToken() else {
            startStopRefresh(shouldStart: false)
            return
        }
        let postString = "access_token=\(access_token)&uuid=\(uuid)"
        request.httpBody = postString.data(using: .utf8)
        if !isAutoRefreshing {
            toast("Fetching your books", on: self.view, duration: 2)
        }
        let config = URLSessionConfiguration.default
        config.protocolClasses = [AuthURLProtocol.self]
        AuthURLProtocol.requestBodyString = postString
        AuthURLProtocol.libraryVC = self
        let session = URLSession(configuration: config)
        print("\noriginal library refresh url: ", url)
        print("original library refresh postString: ", postString)
        let task = session.dataTask(with: request) { data, response, error in
            guard let data = data,
                let response = response as? HTTPURLResponse,
                error == nil else {
                print("error", error ?? "Unknown error")
                self.startStopRefresh(shouldStart: false, toastMessege: "Error fetching records")
                return
            }

            guard (200 ... 299) ~= response.statusCode else {
                print("statusCode should be 2xx, but is \(response.statusCode)")
                print("response = \(response)")
                self.startStopRefresh(shouldStart: false, toastMessege: "Error fetching records")
                return
            }
            
            do {
                let parsedData = try JSONSerialization.jsonObject(with: data) as! [String:Any]
                // print("parsedData: ", parsedData)
                print("\nlibrary data parsed successfully")
                if let customersbooks_data = parsedData["customersbooks_data"] as? Array<Any> {
                    print("\ntotal books found: \(customersbooks_data.count)")
                    if (customersbooks_data.count == 0) {
                        self.startStopRefresh(shouldStart: false, toastMessege: "You have no purchased books")
                        return
                    } else if (customersbooks_data.count == self.books.count) {
                        if self.isAutoRefreshing {
                            self.startStopRefresh(shouldStart: false)
                            return
                        }
                        let alert = UIAlertController(title: "Confirm Resync", message: "Your library is already synched. Are you sure you want to synch again?", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: NSLocalizedString("confirm_button", comment: ""), style: .default, handler: { _ in self.buildBooksList(customersbooks_data: customersbooks_data) }))
                        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel_button", comment: ""), style: .default, handler: { _ in
                            self.startStopRefresh(shouldStart: false)
                        }))
                        DispatchQueue.main.async {
                            self.present(alert, animated: true)
                        }
                    } else {
                        self.buildBooksList(customersbooks_data: customersbooks_data)
                    }
                }
            } catch let error as NSError {
                print(error)
                self.startStopRefresh(shouldStart: false)
            }
        }

        task.resume()
    }
    
    func buildBooksList(customersbooks_data: Array<Any>) {
        if !self.isAutoRefreshing {
            DispatchQueue.main.async {
                toast("Syncing library with \(customersbooks_data.count) books", on: self.view, duration: 2)
            }
        }
        
        var userBookDataArray : Array<Any> = []
        
        for item in customersbooks_data {
            // print("refreshBooks: \(item)")
            if let obj = item as? [String:Any] {
                var elemet : [String:Any] = [:]
                elemet["id"] = obj["id"]
                elemet["order_id"] = obj["order_id"]
                elemet["is_sample"] = obj["is_sample"]
                elemet["cover"] = obj["cover"]
                elemet["customer_id"] = obj["customer_id"]
                elemet["product_title"] = obj["product_title"]
                userBookDataArray.append(elemet)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now(), execute: {
            self.collectionView.numberOfItems(inSection: 0)
            self.loadBooks(userBookDataArray: userBookDataArray)
        })
    }
    
    func loadBooks (userBookDataArray: Array<Any>) {
        DispatchQueue.main.async {
            self.startStopRefresh(shouldStart: true)
            
            // remove deleted books
            
            for book in self.books {
                if let userBookDataArray = userBookDataArray as? [[String: Any]] {
                    let exists = userBookDataArray.contains { dict in
                        if let id = dict["id"] as? Int {
                            return id == book.bookId
                        }
                        return false
                    }
                    if exists {
                        // print("Book with ID \(book.bookId) exists.")
                    } else {
                        // print("Book \(book.title) not found.")
                        Task {
                            do {
                                _ = try await self.library.remove(book)
                            } catch {
                                print(error)
                            }
                        }
                    }
                }
            }
            
            // download new books
            
            var isSampleArray : [Bool] = []
            var bookIdArray : [Int] = []
            var bookTitleArray : [String] = []
            var bookCoverArray : [String] = []
            for item in userBookDataArray {
                if let obj = item as? [String:Any] {
                    var bookExists = false
                    var bookTitle = ""
                    var bookCover = ""
                    guard let bookId = obj["id"] as? Int else {
                        self.isAutoRefreshing = false
                        toast("Sync error", on: self.view, duration: 2)
                        return
                    }
                    for book in self.books {
                        if book.bookId == bookId {
                            if book.isSample == true &&
                                (obj["order_id"] as? Int) != nil {
                                // user purchased a book, previously there as a sample
                                // remove the sample & it will add it back as purchased
                                print("sample purchased")
                                Task {
                                    do {
                                        _ = try await self.library.remove(book)
                                    } catch {
                                        print(error)
                                    }
                                }
                            } else {
                                bookExists = true
                                break
                            }
                        }
                    }
                    if !bookExists {
                        if (obj["order_id"] as? Int) != nil {
                            isSampleArray.append(false)
                        } else {
                            isSampleArray.append(true)
                        }
                        if let product_title = obj["product_title"] as? String,
                           product_title.count > 0 {
                            bookTitle = product_title
                        }
                        if let cover = obj["cover"] as? String,
                           cover.count > 0 {
                            bookCover = cover
                        }
                        
                        if let lastPathComp = bookCover.components(separatedBy: "/").last {
                            bookCover = "\(APILink.COVER_PATH)\(lastPathComp)"
                        }
                        bookIdArray.append(bookId)
                        bookTitleArray.append(bookTitle)
                        bookCoverArray.append(bookCover)
                    }
                }
            }
            
            func retry() {
                if (self.isRetrying) {
                    self.loadBooks(userBookDataArray: userBookDataArray)
                }
            }
            
            self.isRetrying = false
//            self.startStopRefresh(shouldStart: false)
            
            Task {
                do {
                    try await self.library.insertAllBookData(isSamples: isSampleArray,
                                                             bookIds: bookIdArray,
                                                             bookTitles: bookTitleArray,
                                                             bookCovers: bookCoverArray,
                                                             sender: self) { result in
                        if result {
                            self.isRetrying = false
                            print("books data fetching completed successfully")
                            self.startStopRefresh(shouldStart: false, toastMessege: "Completed syncing your books")
                        } else {
                            if (!self.isRetrying) {
                                self.isRetrying = true
                                retry()
                            } else {
                                self.isRetrying = false
                                print("books download completed with errors")
                                self.startStopRefresh(shouldStart: false, toastMessege: "Completed syncing with errors")
                            }
                        }
                    }
                } catch {
                    self.isRetrying = false
                    print("books download completed with errors")
                    self.startStopRefresh(shouldStart: false, toastMessege: "Completed syncing with errors")
                }
            }
        }
    }
    
    fileprivate func removeAllBooks() async {
        do {
            try await self.library.clearAllFilesAndDataBase(bookArray: self.books)
            self.collectionView.reloadData()
            print("all books removed")
        } catch {
            print(error)
        }
    }
    
    fileprivate func autoRefreshLibrary() {
        if TokenManager.shared.isLoggedIn {
            isAutoRefreshing = true
            refreshLibrary()
        }
    }
    
    fileprivate func removeProfilePicture() {
        self.navigationItem.leftBarButtonItem = nil
    }
    
    @objc func checkLoginAndStartRefresh (_ notification: Notification) {
        autoRefreshLibrary()
    }
    
    @objc func removeAllBooksNotificationHandler (_ notification: Notification) {
        Task {
            await removeAllBooks()
        }
        removeProfilePicture()
        setRightBarButton()
        if let aboutView = notification.userInfo?["controller"] as? AboutView {
            DispatchQueue.main.async {
                aboutView.showLoggedOutAlert = true
            }
        }
    }
    
    func removeBookFromCloudLibrary (book: Book) {
        guard TokenManager.shared.isLoggedIn else {
            DispatchQueue.main.async {
                toast("Error removing book from cloud", on: self.view, duration: 2)
            }
            return
        }
        
        guard let bookId = book.bookId else {
            DispatchQueue.main.async {
                toast("Error removing book from cloud", on: self.view, duration: 2)
            }
            return
        }
        
        guard let access_token = TokenManager.shared.getAccessToken() else { return }
        let postString = "access_token=\(access_token)&products_id=\(bookId)"
        
        let hideActivity = toastActivity(on: view)
        
        let removeUrl = URL(string: APILink.BASE_URL + APILink.REMOVE_BOOK)!
        var request = URLRequest(url: removeUrl)
        request = SharedFunctions.setRequestHeader(request: request, method: "POST")
        request.httpBody = postString.data(using: .utf8)
        let config = URLSessionConfiguration.default
        config.protocolClasses = [AuthURLProtocol.self]
        AuthURLProtocol.requestBodyString = postString
        AuthURLProtocol.libraryVC = self
        let session = URLSession(configuration: config)
        let task = session.dataTask(with: request) { data, response, error in
            
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
                if let success = parsedData["success"] as? String, success == "1" {
                    DispatchQueue.main.async {
                        toast("Removed book sample from library", on: self.view, duration: 2)
                    }
                }
            } catch let error as NSError {
                print(error)
            }
        }
        
        task.resume()
    }

    @objc func addBookFromDevice() {
        var types = DocumentTypes.main.supportedUTTypes
        types.append(UTType.text)

        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }

    @objc func addBookForStreaming() {
        let ac = UIAlertController(title: "Stream publication", message: nil, preferredStyle: .alert)
        ac.addTextField { tf in
            tf.placeholder = "HTTP URL"
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        let addAction = UIAlertAction(title: "Add", style: .default) { [unowned ac, weak self] _ in
            guard
                let urlText = ac.textFields?.getOrNil(0)?.text,
                let url = HTTPURL(string: urlText)
            else {
                self?.addBookForStreaming()
                return
            }

            self?.importPublication(from: url)
        }

        ac.addAction(cancelAction)
        ac.addAction(addAction)
        ac.preferredAction = addAction

        present(ac, animated: true)
    }

    private func importPublication(from url: HTTPURL) {
        Task {
            do {
                try await library.importPublication(from: url, sender: self, progress: { _ in })
            } catch {
                alert(UserError(error))
            }
        }
    }
    
    func startStopRefresh(shouldStart start:Bool, toastMessege: String? = nil) {
        DispatchQueue.main.async {
            if !self.isAutoRefreshing {
                if let toastMessege = toastMessege {
                    toast(toastMessege, on: self.view, duration: 2)
                }
                if let appdel = UIApplication.shared.delegate as? AppDelegate {
                    appdel.isRefreshingLibrary = start
                }
            }
            if !start {
                self.isAutoRefreshing = false
            }
            self.showRefreshLoader(status: start)
        }
    }
}

extension LibraryViewController {
    @objc func handleLongPress(gestureRecognizer: UILongPressGestureRecognizer) {
        if gestureRecognizer.state != UIGestureRecognizer.State.began {
            return
        }

        let location = gestureRecognizer.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: location) {
            let book = books[indexPath.item]
            if let bookurl = book.url, bookurl.count > 0 ||
                book.isSample == true {
                let cell = collectionView.cellForItem(at: indexPath) as! PublicationCollectionViewCell
                cell.flipMenu()
            }
        }
    }
}

// MARK: - UIDocumentPickerDelegate.

extension LibraryViewController: UIDocumentPickerDelegate {
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        importFiles(at: urls)
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        importFiles(at: [url])
    }

    private func importFiles(at urls: [URL]) {
        Task {
            do {
                try await library.importPublications(from: urls, sender: self)
            } catch {
                libraryDelegate?.presentError(UserError(error), from: self)
            }
        }
    }
}

// MARK: - CollectionView Datasource.

extension LibraryViewController: UICollectionViewDelegateFlowLayout, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if books.isEmpty {
            let noPublicationLabel = UILabel(frame: collectionView.frame.insetBy(dx: 20, dy: 0))
            noPublicationLabel.numberOfLines = 3
            if TokenManager.shared.isLoggedIn {
                noPublicationLabel.text = NSLocalizedString("library_empty_message", comment: "Hint message when the library is empty")
            } else {
                noPublicationLabel.text = NSLocalizedString("login_message", comment: "Hint message when the library is empty")
            }
            noPublicationLabel.textColor = UIColor.gray
            noPublicationLabel.textAlignment = .center
            collectionView.backgroundView = noPublicationLabel
        } else {
            collectionView.backgroundView = nil
        }

        return books.count
    }

    fileprivate func setTextImageOnCell(_ collectionView: UICollectionView, _ book: Book, _ cell: PublicationCollectionViewCell) {
        DispatchQueue.main.async {
            let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
            let description = book.title
            let textView = self.defaultCover(layout: flowLayout, description: description)
            cell.coverImageView.image = UIImage.imageWithTextView(textView: textView)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "publicationCollectionViewCell", for: indexPath) as! PublicationCollectionViewCell
        cell.coverImageView.image = nil
        cell.progress = 0

        cell.isAccessibilityElement = true
        cell.accessibilityHint = NSLocalizedString("library_publication_a11y_hint", comment: "Accessibility hint for the publication collection cell")

        let book = books[indexPath.item]
        cell.delegate = self
        cell.accessibilityLabel = book.title
        cell.titleLabel.text = book.title
        cell.authorLabel.text = book.authors

        if let isSample = book.isSample, isSample == true {
            cell.sampleRibbonImageView.isHidden = false
        } else {
            cell.sampleRibbonImageView.isHidden = true
        }
        
        if let isReading = book.isReading, isReading == true {
            cell.currentlyReadingLabel.isHidden = false
        } else {
            cell.currentlyReadingLabel.isHidden = true
        }
        
        if let bookurl = book.url, bookurl.count > 0 {
            cell.cloudDownloadImageView.isHidden = true
        } else {
            cell.cloudDownloadImageView.isHidden = false
            cell.cloudDownloadImageView.layer.cornerRadius = 4.0
        }
        
        // Load image and then apply the shadow.
        if let coverPath = book.coverPath,
           let url = URL(string: coverPath) {
            URLSession.shared.dataTask(with: url) { (data, response, error) in
                if let imageData = data,
                let img = UIImage(data: imageData) {
                    DispatchQueue.main.async {
                        cell.coverImageView.image = img
                    }
                } else {
                    self.setTextImageOnCell(collectionView, book, cell)
                }
            }.resume()
        } else {
            setTextImageOnCell(collectionView, book, cell)
        }

        return cell
    }

    internal func defaultCover(layout: UICollectionViewFlowLayout?, description: String) -> UITextView {
        let width = layout?.itemSize.width ?? 0
        let height = layout?.itemSize.height ?? 0
        let titleTextView = UITextView(frame: CGRect(x: 0, y: 0, width: width, height: height))

        titleTextView.layer.borderWidth = 5.0
        titleTextView.layer.borderColor = #colorLiteral(red: 0.08269290555, green: 0.2627741129, blue: 0.3623990017, alpha: 1).cgColor
        titleTextView.backgroundColor = #colorLiteral(red: 0.05882352963, green: 0.180392161, blue: 0.2470588237, alpha: 1)
        titleTextView.textColor = #colorLiteral(red: 0.8639426257, green: 0.8639426257, blue: 0.8639426257, alpha: 1)
        titleTextView.text = description.appending("\n_________") // Dirty styling.

        return titleTextView
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Task {
            guard
                let libraryDelegate = libraryDelegate,
                let cell = collectionView.cellForItem(at: indexPath)
            else {
                return
            }
            cell.contentView.addSubview(self.loadingIndicator)
            collectionView.isUserInteractionEnabled = false

            defer {
                loadingIndicator.removeFromSuperview()
                collectionView.isUserInteractionEnabled = true
            }

            let book = books[indexPath.item]

            if let bookurl = book.url, bookurl.count > 0 {
                do {
                    guard let pub = try await library.openBook(book, sender: self) else {
                        return
                    }
                    libraryDelegate.libraryDidSelectPublication(pub, book: book)
                } catch {
                    libraryDelegate.presentError(UserError(error), from: self)
                }
            } else if let bookid = book.bookId, bookid > 0 {
                // download book
                guard let access_token = TokenManager.shared.getAccessToken() else { return }
                self.startStopRefresh(shouldStart: true)
                let url = URL(string: APILink.BASE_URL + APILink.DOWNLOAD_BOOK)!
                var request = URLRequest(url: url)
                request = SharedFunctions.setRequestHeader(request: request, method: "POST")
                let uuid = UIDevice.current.identifierForVendor?.uuidString ?? ""
                let postString = "access_token=\(access_token)&uuid=\(uuid)&book_id=\(bookid)&device_type=iOS"
                request.httpBody = postString.data(using: .utf8)
                toast("Downloading book", on: self.view, duration: 2)
                let config = URLSessionConfiguration.default
                config.protocolClasses = [AuthURLProtocol.self]
                AuthURLProtocol.requestBodyString = postString
                AuthURLProtocol.libraryVC = self
                let session = URLSession(configuration: config)
                print("\noriginal book download url: ", url)
                print("original book download postString: ", postString)
                let task = session.dataTask(with: request) { data, response, error in
                    guard let data = data,
                          let response = response as? HTTPURLResponse,
                          error == nil else {
                        print("error", error ?? "Unknown error")
                        self.startStopRefresh(shouldStart: false, toastMessege: "Error fetching records")
                        return
                    }
                    
                    guard (200 ... 299) ~= response.statusCode else {
                        print("statusCode should be 2xx, but is \(response.statusCode)")
                        print("response = \(response)")
                        self.startStopRefresh(shouldStart: false, toastMessege: "Error fetching books")
                        return
                    }
                    print("\nbook downloaded")
                    
                    // Save to local file
                    let fileManager = FileManager.default
                    let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                    var fileURL = docsURL.appendingPathComponent("tmpFile.epub")
                    if let mimeType = response.mimeType,
                       mimeType.count > 0,
                       mimeType.contains("pdf") {
                        fileURL = docsURL.appendingPathComponent("tmpFile")
                    }
                    do {
                        try data.write(to: fileURL, options: .atomic)
                        if let aburl = fileURL.absoluteURL {
                            Task {
                                do {
                                    try await self.library.updateBookRecord(for: bookid, from: aburl, sender: self) { progress in
                                        print("progress: ", progress)
                                    }
                                    print("book saved")
                                    await self.startStopRefresh(shouldStart: false, toastMessege: "Book downloaded")
                                } catch {
                                    print(error)
                                    await self.startStopRefresh(shouldStart: false, toastMessege: "Book download failed")
                                }
                            }
                        }
                    } catch let error as NSError {
                        print(error)
                        self.startStopRefresh(shouldStart: false)
                    }
                }
                self.startStopRefresh(shouldStart: true)
                task.resume()
                
            }
        }
    }
}

extension LibraryViewController: PublicationCollectionViewCellDelegate {
    func removePublicationFromLibrary(forCellAt indexPath: IndexPath) {
        let book = books[indexPath.item]

        var alertMsg = NSLocalizedString("library_delete_alert_message", comment: "Message of the publication remove confirmation alert")
        if let isSample = book.isSample {
            if (isSample) {
                alertMsg = NSLocalizedString("library_delete_alert_message_sample", comment: "Message of the publication remove confirmation alert")
            }
        }
        
        let removePublicationAlert = UIAlertController(
            title: NSLocalizedString("library_delete_alert_title", comment: "Title of the publication remove confirmation alert"),
            message: alertMsg,
            preferredStyle: .alert
        )
        let removeAction = UIAlertAction(title: NSLocalizedString("remove_button", comment: "Button to confirm the deletion of a publication"), style: .destructive, handler: { _ in
            Task {
                do {
                    let result = try await self.library.remove(book)
                    if let isSample = book.isSample, isSample {
                        self.removeBookFromCloudLibrary(book: book)
                    } else if result {
                        DispatchQueue.main.async {
                            toast("Removed book from device", on: self.view, duration: 2)
                        }
                    }
                } catch {
                    self.libraryDelegate?.presentError(UserError(error), from: self)
                }
            }
        })
        let cancelAction = UIAlertAction(title: NSLocalizedString("cancel_button", comment: "Button to cancel the deletion of a publication"), style: .cancel)

        removePublicationAlert.addAction(removeAction)
        removePublicationAlert.addAction(cancelAction)
        present(removePublicationAlert, animated: true, completion: nil)
    }

    func displayInformation(forCellAt indexPath: IndexPath) {
        let book = books[indexPath.row]

        Task {
            do {
                guard let pub = try await library.openBook(book, sender: self) else {
                    return
                }
                let detailsViewController = self.factory.make(publication: pub)
                detailsViewController.modalPresentationStyle = .popover
                self.navigationController?.pushViewController(detailsViewController, animated: true)
            } catch {
                libraryDelegate?.presentError(UserError(error), from: self)
            }
        }
    }

    // Used to reset ui of the last flipped cell, we must not have two cells
    // flipped at the same time
    func cellFlipped(_ cell: PublicationCollectionViewCell) {
        lastFlippedCell?.flipMenu()
        lastFlippedCell = cell
    }
}

class PublicationIndicator: UIView {
    lazy var indicator: UIActivityIndicatorView = {
        let result = UIActivityIndicatorView(style: .large)
        result.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = UIColor(white: 0.3, alpha: 0.7)
        self.addSubview(result)

        let horizontalConstraint = NSLayoutConstraint(item: result, attribute: .centerX, relatedBy: .equal, toItem: self, attribute: .centerX, multiplier: 1.0, constant: 0.0)
        let verticalConstraint = NSLayoutConstraint(item: result, attribute: .centerY, relatedBy: .equal, toItem: self, attribute: .centerY, multiplier: 1.0, constant: 0.0)
        self.addConstraints([horizontalConstraint, verticalConstraint])

        return result
    }()

    override func didMoveToSuperview() {
        super.didMoveToSuperview()

        guard let superView = superview else { return }
        translatesAutoresizingMaskIntoConstraints = false

        let horizontalConstraint = NSLayoutConstraint(item: self, attribute: .centerX, relatedBy: .equal, toItem: superView, attribute: .centerX, multiplier: 1.0, constant: 0.0)
        let verticalConstraint = NSLayoutConstraint(item: self, attribute: .centerY, relatedBy: .equal, toItem: superView, attribute: .centerY, multiplier: 1.0, constant: 0.0)
        let widthConstraint = NSLayoutConstraint(item: self, attribute: .width, relatedBy: .equal, toItem: superView, attribute: .width, multiplier: 1.0, constant: 0.0)
        let heightConstraint = NSLayoutConstraint(item: self, attribute: .height, relatedBy: .equal, toItem: superView, attribute: .height, multiplier: 1.0, constant: 0.0)

        superView.addConstraints([horizontalConstraint, verticalConstraint, widthConstraint, heightConstraint])

        indicator.startAnimating()
    }

    override func removeFromSuperview() {
        indicator.stopAnimating()
        super.removeFromSuperview()
    }
}
