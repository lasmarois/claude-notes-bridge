import Foundation
import SQLite3

/// Access to the Apple Notes SQLite database
class NotesDatabase {
    private var db: OpaquePointer?
    private let decoder = NoteDecoder()

    init() {
        // Database is opened lazily on first query
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Public API

    /// List notes with optional folder filter
    func listNotes(folder: String? = nil, limit: Int = 100) throws -> [Note] {
        try ensureOpen()

        var query = """
            SELECT
                n.ZIDENTIFIER as id,
                n.ZTITLE1 as title,
                f.ZTITLE2 as folder,
                n.ZCREATIONDATE1 as created,
                n.ZMODIFICATIONDATE1 as modified
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
            WHERE n.ZTITLE1 IS NOT NULL
            """

        if let folder = folder {
            query += " AND f.ZTITLE2 = '\(folder.replacingOccurrences(of: "'", with: "''"))'"
        }

        query += " ORDER BY n.ZMODIFICATIONDATE1 DESC LIMIT \(limit)"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var notes: [Note] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = columnString(statement, 0) ?? ""
            let title = columnString(statement, 1) ?? "Untitled"
            let folder = columnString(statement, 2)
            let created = columnDate(statement, 3)
            let modified = columnDate(statement, 4)

            notes.append(Note(
                id: id,
                title: title,
                folder: folder,
                createdAt: created,
                modifiedAt: modified
            ))
        }

        return notes
    }

    /// Read a single note's full content
    func readNote(id: String) throws -> NoteContent {
        try ensureOpen()

        // First get metadata
        let metaQuery = """
            SELECT
                n.ZIDENTIFIER as id,
                n.ZTITLE1 as title,
                f.ZTITLE2 as folder,
                n.ZCREATIONDATE1 as created,
                n.ZMODIFICATIONDATE1 as modified,
                n.Z_PK as pk
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
            WHERE n.ZIDENTIFIER = ?
            """

        var metaStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, metaQuery, -1, &metaStatement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(metaStatement) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(metaStatement, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(metaStatement) == SQLITE_ROW else {
            throw NotesError.noteNotFound(id)
        }

        let title = columnString(metaStatement, 1) ?? "Untitled"
        let folder = columnString(metaStatement, 2)
        let created = columnDate(metaStatement, 3)
        let modified = columnDate(metaStatement, 4)
        let pk = sqlite3_column_int64(metaStatement, 5)

        // Now get content from ZICNOTEDATA
        let contentQuery = """
            SELECT ZDATA FROM ZICNOTEDATA WHERE ZNOTE = ?
            """

        var contentStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, contentQuery, -1, &contentStatement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(contentStatement) }

        sqlite3_bind_int64(contentStatement, 1, pk)

        var content = ""
        if sqlite3_step(contentStatement) == SQLITE_ROW {
            if let blob = sqlite3_column_blob(contentStatement, 0) {
                let length = sqlite3_column_bytes(contentStatement, 0)
                let data = Data(bytes: blob, count: Int(length))
                content = try decoder.decode(data)
            }
        }

        return NoteContent(
            id: id,
            title: title,
            content: content,
            folder: folder,
            createdAt: created,
            modifiedAt: modified
        )
    }

    /// Search notes by content
    func searchNotes(query: String, limit: Int = 20) throws -> [Note] {
        // For now, search by title
        // TODO: Search within decoded content
        try ensureOpen()

        let searchQuery = """
            SELECT
                n.ZIDENTIFIER as id,
                n.ZTITLE1 as title,
                f.ZTITLE2 as folder,
                n.ZCREATIONDATE1 as created,
                n.ZMODIFICATIONDATE1 as modified
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
            WHERE n.ZTITLE1 IS NOT NULL
              AND n.ZTITLE1 LIKE '%' || ? || '%'
            ORDER BY n.ZMODIFICATIONDATE1 DESC
            LIMIT ?
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, searchQuery, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        let SQLITE_TRANSIENT_SEARCH = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, (query as NSString).utf8String, -1, SQLITE_TRANSIENT_SEARCH)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var notes: [Note] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = columnString(statement, 0) ?? ""
            let title = columnString(statement, 1) ?? "Untitled"
            let folder = columnString(statement, 2)
            let created = columnDate(statement, 3)
            let modified = columnDate(statement, 4)

            notes.append(Note(
                id: id,
                title: title,
                folder: folder,
                createdAt: created,
                modifiedAt: modified
            ))
        }

        return notes
    }

    // MARK: - Private Helpers

    private func ensureOpen() throws {
        if db != nil { return }

        let path = Permissions.notesDatabasePath
        guard FileManager.default.fileExists(atPath: path) else {
            throw NotesError.databaseNotFound
        }

        // Open read-only
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let error = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw NotesError.cannotOpenDatabase(error)
        }
    }

    private func columnString(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    private func columnDate(_ statement: OpaquePointer?, _ index: Int32) -> Date? {
        let timestamp = sqlite3_column_double(statement, index)
        guard timestamp > 0 else { return nil }
        // Apple's Core Data timestamps are seconds since 2001-01-01
        return Date(timeIntervalSinceReferenceDate: timestamp)
    }
}
