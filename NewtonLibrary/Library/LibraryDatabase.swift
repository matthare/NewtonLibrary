import Foundation
import SQLite3

/// The library's SQLite database: one row per package.
///
/// What was read from the package is kept as JSON in the `info` column, so it can
/// be read again (Library > Re-read All Packages) without losing anything you
/// typed: your changes are kept as JSON in the `edits` column (a field that isn't
/// there means "use what was read from the package"), and your notes in `notes`.
/// (The title, publisher and newton_os columns held edits in version 1 and are
/// moved into `edits` when the library is opened.)
final class LibraryDatabase {
    enum DatabaseError: LocalizedError {
        case sqlite(String)
        var errorDescription: String? {
            switch self {
            case .sqlite(let message): return "Database error: \(message)"
            }
        }
    }

    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// The default database, in ~/Library/Application Support/Newton Library.
    /// (Launching with -LibraryDatabasePath <file> uses another one, for testing.)
    static func openDefault() throws -> LibraryDatabase {
        if let path = UserDefaults.standard.string(forKey: "LibraryDatabasePath"), !path.isEmpty {
            return try LibraryDatabase(url: URL(fileURLWithPath: path))
        }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent("Newton Library", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try LibraryDatabase(url: folder.appendingPathComponent("Library.sqlite"))
    }

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        try execute("""
            CREATE TABLE IF NOT EXISTS packages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sha256 TEXT NOT NULL UNIQUE,
                file_path TEXT NOT NULL,
                original_name TEXT NOT NULL,
                date_added REAL NOT NULL,
                info TEXT NOT NULL,
                title TEXT,
                publisher TEXT,
                newton_os TEXT,
                notes TEXT NOT NULL DEFAULT ''
            );
            """)
        // Version 2: all edits in one JSON column
        if try intValue("PRAGMA user_version") < 2 {
            let columns = try strings("SELECT name FROM pragma_table_info('packages')")
            if !columns.contains("edits") {
                try execute("ALTER TABLE packages ADD COLUMN edits TEXT NOT NULL DEFAULT '{}'")
            }
            try execute("PRAGMA user_version = 2")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: Reading and writing

    func allItems() throws -> [LibraryItem] {
        let sql = "SELECT id, sha256, file_path, original_name, date_added, info, title, publisher, newton_os, notes, edits FROM packages"
        var items: [LibraryItem] = []
        try query(sql, bind: []) { s in
            guard let infoText = text(s, 5),
                  let info = try? decoder.decode(PackageInfo.self, from: Data(infoText.utf8)) else { return }
            var edits = (try? decoder.decode([String: String].self, from: Data((text(s, 10) ?? "{}").utf8))) ?? [:]
            // Edits made with version 1
            if let title = text(s, 6) { edits[InfoField.title.rawValue] = title }
            if let publisher = text(s, 7) { edits[InfoField.publisher.rawValue] = publisher }
            if let os = text(s, 8) { edits[InfoField.newtonOS.rawValue] = os }
            var item = LibraryItem(
                id: sqlite3_column_int64(s, 0),
                sha256: text(s, 1) ?? "",
                filePath: text(s, 2) ?? "",
                originalName: text(s, 3) ?? "",
                dateAdded: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(s, 4)),
                info: info,
                edits: edits,
                notes: text(s, 9) ?? "")
            // A Newton OS group chosen in version 1 becomes a minimum and maximum
            if let group = edits[InfoField.newtonOS.rawValue].flatMap(NewtonOS.init(rawValue:)) {
                item.setGroup(group)
            }
            items.append(item)
        }
        return items
    }

    /// Adds a package and returns it with its new id.
    func insert(sha256: String, filePath: String, originalName: String, info: PackageInfo) throws -> LibraryItem {
        let now = Date()
        try run("INSERT INTO packages (sha256, file_path, original_name, date_added, info) VALUES (?, ?, ?, ?, ?)",
                [sha256, filePath, originalName, now.timeIntervalSinceReferenceDate, try json(info)])
        return LibraryItem(id: sqlite3_last_insert_rowid(db), sha256: sha256, filePath: filePath,
                           originalName: originalName, dateAdded: now, info: info, edits: [:], notes: "")
    }

    func update(_ item: LibraryItem) throws {
        try run("""
            UPDATE packages SET file_path = ?, info = ?, edits = ?, notes = ?,
                title = NULL, publisher = NULL, newton_os = NULL
            WHERE id = ?
            """,
            [item.filePath, try json(item.info),
             String(decoding: try encoder.encode(item.edits), as: UTF8.self), item.notes, item.id])
    }

    func delete(id: Int64) throws {
        try run("DELETE FROM packages WHERE id = ?", [id])
    }

    // MARK: SQLite helpers

    private func json(_ info: PackageInfo) throws -> String {
        String(decoding: try encoder.encode(info), as: UTF8.self)
    }

    private func intValue(_ sql: String) throws -> Int {
        var value = 0
        try query(sql, bind: []) { s in value = Int(sqlite3_column_int64(s, 0)) }
        return value
    }

    private func strings(_ sql: String) throws -> [String] {
        var values: [String] = []
        try query(sql, bind: []) { s in if let t = text(s, 0) { values.append(t) } }
        return values
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func run(_ sql: String, _ values: [Any?]) throws {
        try query(sql, bind: values) { _ in }
    }

    private func query(_ sql: String, bind values: [Any?], row: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let s = statement else {
            throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(s) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, value) in values.enumerated() {
            let index = Int32(i + 1)
            switch value {
            case let v as String: sqlite3_bind_text(s, index, v, -1, transient)
            case let v as Int64: sqlite3_bind_int64(s, index, v)
            case let v as Int: sqlite3_bind_int64(s, index, Int64(v))
            case let v as Double: sqlite3_bind_double(s, index, v)
            default: sqlite3_bind_null(s, index)
            }
        }
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_ROW {
                try row(s)
            } else if result == SQLITE_DONE {
                break
            } else {
                throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private func text(_ s: OpaquePointer, _ column: Int32) -> String? {
        guard let c = sqlite3_column_text(s, column) else { return nil }
        return String(cString: c)
    }
}
