//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import GRDB
import ReadiumShared

struct Book: Codable {
    struct Id: EntityId { let rawValue: Int64 }

    let id: Id?
    /// Canonical identifier for the publication, extracted from its metadata.
    var identifier: String?
    /// Title of the publication, extracted from its metadata.
    var title: String
    /// Authors of the publication, separated by commas.
    var authors: String?
    /// Media type associated to the publication.
    var type: String
    /// Location of the packaged publication or a manifest. It can be a relative
    /// path to the Documents/ folder, or an absolute URL.
    var url: String?
    /// Location of the cover.
    var coverPath: String?
    /// Last read location in the publication.
    var locator: Locator? {
        didSet { progression = locator?.locations.totalProgression ?? 0 }
    }

    /// Current progression in the publication, extracted from the locator.
    var progression: Double
    /// Date of creation.
    var created: Date
    /// JSON of user preferences specific to this publication (e.g. language,
    /// reading progression, spreads).
    var preferencesJSON: String?
    
    /// If publication is a smaple type
    let isSample: Bool?
    
    /// If publication is a smaple type
    let isReading: Bool?
    
    /// Last updated (downloaded / read) time of the book
    let updatedAt: Date?
    
    /// Publication ID retrieved from server
    let bookId: Int?

    var mediaType: MediaType { MediaType(type) ?? .binary }

    init(
        id: Id? = nil,
        identifier: String? = nil,
        title: String,
        authors: String? = nil,
        type: String,
        url: String,
        coverPath: String? = nil,
        locator: Locator? = nil,
        created: Date = Date(),
        preferencesJSON: String? = nil,
        isSample: Bool? = false,
        isReading: Bool? = false,
        updatedAt: Date = Date(),
        bookId: Int? = 0
    ) {
        self.id = id
        self.identifier = identifier
        self.title = title
        self.authors = authors
        self.type = type
        self.url = url
        self.coverPath = coverPath
        self.locator = locator
        progression = locator?.locations.totalProgression ?? 0
        self.created = created
        self.preferencesJSON = preferencesJSON
        self.isSample = isSample
        self.isReading = isReading
        self.updatedAt = updatedAt
        self.bookId = bookId
    }

    var cover: FileURL? {
        coverPath.map { Paths.covers.appendingPath($0, isDirectory: false) }
    }

    func preferences<P: Decodable>() throws -> P? {
        guard let data = preferencesJSON.flatMap({ $0.data(using: .utf8) }) else {
            return nil
        }
        return try JSONDecoder().decode(P.self, from: data)
    }

    mutating func setPreferences<P: Encodable>(_ preferences: P) throws {
        let data = try JSONEncoder().encode(preferences)
        preferencesJSON = String(data: data, encoding: .utf8)
    }
}

struct BookCloud {
    var isSample: Bool?
    var bookId: Int?
    var bookTitle: String?
    var bookCover: String?
    // TODO: to replace sample, id, title, cover arrays
}

extension Book: TableRecord, FetchableRecord, PersistableRecord {
    enum Columns: String, ColumnExpression {
        case id, identifier, title, authors, type, url, coverPath, updatedAt, locator, progression, created, preferencesJSON
    }
}

final class BookRepository {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func get(_ id: Book.Id) async throws -> Book? {
        try await db.read { db in
            try Book.fetchOne(db, key: id)
        }
    }

    func observe(_ id: Book.Id) -> AnyPublisher<Book?, Error> {
        db.observe { db in
            try Book.fetchOne(db, key: id)
        }
    }

    func all() -> AnyPublisher<[Book], Error> {
        db.observe { db in
            try Book.order(Book.Columns.updatedAt).fetchAll(db).reversed()
        }
    }
    
    func all(searchText: String? = nil) -> AnyPublisher<[Book], Error> {
        db.observe { db in
            var query = Book.order(Book.Columns.updatedAt)

            if let text = searchText, !text.isEmpty {
                let pattern = "%\(text)%"
                query = query.filter(
                    Book.Columns.title.like(pattern) || Book.Columns.authors.like(pattern)
                )
            }

            return try query.fetchAll(db).reversed()
        }
    }


    @discardableResult
    func add(_ book: Book) async throws -> Book.Id {
        try await db.write { db in
            try book.insert(db)
            return Book.Id(rawValue: db.lastInsertedRowID)
        }
    }
    
    func update(for bookId: Int, _ book: Book) async throws {
        try await db.write { db in
            try db.execute(literal: """
                UPDATE book
                   SET url = \(book.url), type = \(book.type), authors = \(book.authors), updatedAt = CURRENT_TIMESTAMP
                 WHERE bookId = \(bookId)
            """)
            // return Book.Id(rawValue: db.lastInsertedRowID)
            // return Book.Id(rawValue: db.lastInsertedRowID).rawValue == bookId
        }
    }
    
    func setCurrentlyReading(for bookId: Int) async throws {
        try await db.write { db in
            try db.execute(literal: """
                UPDATE book
                   SET isReading = (bookId = \(bookId)), updatedAt = CASE WHEN bookId = \(bookId) THEN CURRENT_TIMESTAMP ELSE updatedAt END
            """)
        }
    }
    
    func removeBookEntryFromDataBase(_ book: Book) async throws -> Bool {
        guard let bookId = book.bookId else {
            return false
        }
        if let isSample = book.isSample,
           isSample == true {
            try await db.write { db in try Book.deleteOne(db, key: book.id) }
            return true
        } else {
            try await db.write { db in
                try db.execute(literal: """
                    UPDATE book
                       SET url = \(""), type = \("")
                     WHERE bookId = \(bookId)
                """)
            }
            return true
        }
    }

    func removeAll() async throws {
        try await db.write { db in try Book.deleteAll(db) }
    }
    
    func remove(_ id: Book.Id) async throws {
        try await db.write { db in try Book.deleteOne(db, key: id) }
    }

    func saveProgress(for id: Book.Id, locator: Locator) async throws {
        guard let json = locator.jsonString else {
            return
        }

        try await db.write { db in
            try db.execute(literal: """
                UPDATE book
                   SET locator = \(json), progression = \(locator.locations.totalProgression ?? 0)
                 WHERE id = \(id)
            """)
        }
    }

    func savePreferences<Preferences: Encodable>(_ preferences: Preferences, of id: Book.Id) async throws {
        try await db.write { db in
            guard var book = try Book.fetchOne(db, key: id) else {
                return
            }

            try book.setPreferences(preferences)
            try book.save(db)
        }
    }
}
