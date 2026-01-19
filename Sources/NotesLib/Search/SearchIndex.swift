import Foundation
import SQLite3

/// FTS5-based full-text search index for Apple Notes
/// Stores index in a separate file, doesn't modify the Notes database
public class SearchIndex {
    private var db: OpaquePointer?
    private let indexPath: String
    private let notesDB: NotesDatabase

    /// Initialize with a NotesDatabase instance
    public init(notesDB: NotesDatabase) {
        self.notesDB = notesDB

        // Store index in ~/Library/Caches/claude-notes-bridge/
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("claude-notes-bridge")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        self.indexPath = cacheDir.appendingPathComponent("search_index.db").path
    }

    /// Open the index database, creating it if needed
    public func open() throws {
        guard db == nil else { return }

        if sqlite3_open(indexPath, &db) != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            throw NotesError.cannotOpenDatabase(error)
        }

        // Create FTS5 virtual table if it doesn't exist
        let createSQL = """
            CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
                note_id,
                title,
                snippet,
                folder,
                content,
                tokenize='porter unicode61'
            );
            """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createSQL, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg != nil ? String(cString: errMsg!) : "Unknown error"
            sqlite3_free(errMsg)
            throw NotesError.queryFailed(error)
        }

        // Create metadata table to track index freshness
        let metaSQL = """
            CREATE TABLE IF NOT EXISTS index_meta (
                key TEXT PRIMARY KEY,
                value TEXT
            );
            """
        sqlite3_exec(db, metaSQL, nil, nil, nil)
    }

    /// Close the index database
    public func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    /// Check if index exists and has content
    public var isIndexed: Bool {
        do {
            try open()
            var stmt: OpaquePointer?
            let sql = "SELECT COUNT(*) FROM notes_fts"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int(stmt, 0) > 0
            }
            return false
        } catch {
            return false
        }
    }

    /// Get the number of indexed notes
    public var indexedCount: Int {
        do {
            try open()
            var stmt: OpaquePointer?
            let sql = "SELECT COUNT(*) FROM notes_fts"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
            return 0
        } catch {
            return 0
        }
    }

    /// Build or rebuild the full-text search index
    /// - Parameter progress: Optional callback for progress updates
    /// - Returns: Number of notes indexed
    @discardableResult
    public func buildIndex(progress: ((Int, Int) -> Void)? = nil) throws -> Int {
        try open()

        // Clear existing index
        sqlite3_exec(db, "DELETE FROM notes_fts", nil, nil, nil)

        // Get all notes from the database
        let notes = try notesDB.listNotes(limit: 100000)
        let total = notes.count
        var indexed = 0

        // Begin transaction for faster inserts
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)

        let insertSQL = "INSERT INTO notes_fts (note_id, title, snippet, folder, content) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            throw NotesError.queryFailed(error)
        }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT_IDX = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        for note in notes {
            // Get full note content
            var content = ""
            if let noteContent = try? notesDB.readNote(id: note.id) {
                content = noteContent.content
            }

            // Bind values
            sqlite3_bind_text(stmt, 1, (note.id as NSString).utf8String, -1, SQLITE_TRANSIENT_IDX)
            sqlite3_bind_text(stmt, 2, (note.title as NSString).utf8String, -1, SQLITE_TRANSIENT_IDX)
            sqlite3_bind_text(stmt, 3, ("" as NSString).utf8String, -1, SQLITE_TRANSIENT_IDX)  // snippet not easily available here
            sqlite3_bind_text(stmt, 4, ((note.folder ?? "") as NSString).utf8String, -1, SQLITE_TRANSIENT_IDX)
            sqlite3_bind_text(stmt, 5, (content as NSString).utf8String, -1, SQLITE_TRANSIENT_IDX)

            if sqlite3_step(stmt) != SQLITE_DONE {
                // Log error but continue
                print("Warning: Failed to index note \(note.id)")
            }

            sqlite3_reset(stmt)
            indexed += 1

            // Report progress every 50 notes
            if indexed % 50 == 0 {
                progress?(indexed, total)
            }
        }

        // Commit transaction
        sqlite3_exec(db, "COMMIT", nil, nil, nil)

        // Update metadata
        let now = ISO8601DateFormatter().string(from: Date())
        let metaSQL = "INSERT OR REPLACE INTO index_meta (key, value) VALUES ('last_build', ?)"
        var metaStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, metaSQL, -1, &metaStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(metaStmt, 1, (now as NSString).utf8String, -1, SQLITE_TRANSIENT_IDX)
            sqlite3_step(metaStmt)
            sqlite3_finalize(metaStmt)
        }

        progress?(indexed, total)
        return indexed
    }

    /// Search the FTS5 index
    /// - Parameters:
    ///   - query: Search query (supports FTS5 syntax)
    ///   - limit: Maximum results
    /// - Returns: Array of (noteId, snippet) tuples
    public func search(query: String, limit: Int = 20) throws -> [(noteId: String, snippet: String)] {
        try open()

        // Escape query for FTS5 (wrap terms in quotes for phrase matching)
        let escapedQuery = query.components(separatedBy: " ")
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"" }
            .joined(separator: " OR ")

        let sql = """
            SELECT note_id, snippet(notes_fts, 4, '**', '**', '...', 20) as match_snippet
            FROM notes_fts
            WHERE notes_fts MATCH ?
            ORDER BY rank
            LIMIT ?
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            throw NotesError.queryFailed(error)
        }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT_IDX = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, (escapedQuery as NSString).utf8String, -1, SQLITE_TRANSIENT_IDX)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [(String, String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let noteId = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let snippet = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            results.append((noteId, snippet))
        }

        return results
    }

    /// Delete the index file
    public func deleteIndex() {
        close()
        try? FileManager.default.removeItem(atPath: indexPath)
    }

    /// Get last build timestamp
    public var lastBuildDate: Date? {
        do {
            try open()
            var stmt: OpaquePointer?
            let sql = "SELECT value FROM index_meta WHERE key = 'last_build'"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_ROW {
                if let value = sqlite3_column_text(stmt, 0) {
                    let dateStr = String(cString: value)
                    return ISO8601DateFormatter().date(from: dateStr)
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    deinit {
        close()
    }
}
