import Foundation
import SQLite3

/// Access to the Apple Notes SQLite database
public class NotesDatabase {
    private var db: OpaquePointer?
    private let decoder = NoteDecoder()
    private let encoder = NoteEncoder()
    private var isReadWrite = false

    public init() {
        // Database is opened lazily on first query
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Public API

    /// List notes with optional folder filter
    public func listNotes(folder: String? = nil, limit: Int = 100) throws -> [Note] {
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
    public func readNote(id: String) throws -> NoteContent {
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

        // Fetch attachments for this note
        let attachments = try fetchAttachments(forNotePK: pk)

        // Fetch hashtags from embedded objects
        let hashtags = try getHashtags(forNoteId: id)

        // Fetch note-to-note links from embedded objects
        let linkTuples = try getNoteLinks(forNoteId: id)
        let noteLinks = linkTuples.map { NoteLink(text: $0.text, targetId: $0.targetId) }

        var noteContent = NoteContent(
            id: id,
            title: title,
            content: content,
            folder: folder,
            createdAt: created,
            modifiedAt: modified
        )
        noteContent.attachments = attachments
        noteContent.hashtags = hashtags
        noteContent.noteLinks = noteLinks

        return noteContent
    }

    /// Search notes by content
    /// Enhanced search: case-insensitive, searches title + snippet + folder name
    /// Set searchContent=true to also search decoded note body (slower)
    public func searchNotes(query: String, limit: Int = 20, searchContent: Bool = false) throws -> [Note] {
        try ensureOpen()

        // Phase 1: Fast search using indexed columns (title, snippet, folder)
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
              AND (
                  LOWER(n.ZTITLE1) LIKE '%' || LOWER(?) || '%'
                  OR LOWER(COALESCE(n.ZSNIPPET, '')) LIKE '%' || LOWER(?) || '%'
                  OR LOWER(COALESCE(f.ZTITLE2, '')) LIKE '%' || LOWER(?) || '%'
              )
            ORDER BY n.ZMODIFICATIONDATE1 DESC
            LIMIT ?
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, searchQuery, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        let SQLITE_TRANSIENT_SEARCH = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        // Bind query for each OR condition
        sqlite3_bind_text(statement, 1, (query as NSString).utf8String, -1, SQLITE_TRANSIENT_SEARCH)
        sqlite3_bind_text(statement, 2, (query as NSString).utf8String, -1, SQLITE_TRANSIENT_SEARCH)
        sqlite3_bind_text(statement, 3, (query as NSString).utf8String, -1, SQLITE_TRANSIENT_SEARCH)
        sqlite3_bind_int(statement, 4, Int32(limit))

        var notes: [Note] = []
        var foundIds = Set<String>()

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = columnString(statement, 0) ?? ""
            let title = columnString(statement, 1) ?? "Untitled"
            let folder = columnString(statement, 2)
            let created = columnDate(statement, 3)
            let modified = columnDate(statement, 4)

            foundIds.insert(id)
            notes.append(Note(
                id: id,
                title: title,
                folder: folder,
                createdAt: created,
                modifiedAt: modified
            ))
        }

        // Phase 2: If searchContent=true and we haven't hit limit, search note bodies
        if searchContent && notes.count < limit {
            let contentMatches = try searchNoteContent(query: query, limit: limit - notes.count, excludeIds: foundIds)
            notes.append(contentsOf: contentMatches)
        }

        return notes
    }

    /// Search within decoded note content (protobuf bodies)
    /// This is slower as it requires decoding each note
    private func searchNoteContent(query: String, limit: Int, excludeIds: Set<String>) throws -> [Note] {
        // Get all notes not already found, ordered by modification date
        let allNotesQuery = """
            SELECT
                n.ZIDENTIFIER as id,
                n.ZTITLE1 as title,
                f.ZTITLE2 as folder,
                n.ZCREATIONDATE1 as created,
                n.ZMODIFICATIONDATE1 as modified,
                n.Z_PK as pk
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
            WHERE n.ZTITLE1 IS NOT NULL
            ORDER BY n.ZMODIFICATIONDATE1 DESC
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, allNotesQuery, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var matches: [Note] = []
        let lowerQuery = query.lowercased()

        while sqlite3_step(statement) == SQLITE_ROW && matches.count < limit {
            let id = columnString(statement, 0) ?? ""

            // Skip already found notes
            if excludeIds.contains(id) { continue }

            let title = columnString(statement, 1) ?? "Untitled"
            let folder = columnString(statement, 2)
            let created = columnDate(statement, 3)
            let modified = columnDate(statement, 4)
            let pk = sqlite3_column_int64(statement, 5)

            // Decode note content and search
            if let content = try? getDecodedContent(forNotePK: pk),
               content.lowercased().contains(lowerQuery) {
                matches.append(Note(
                    id: id,
                    title: title,
                    folder: folder,
                    createdAt: created,
                    modifiedAt: modified
                ))
            }
        }

        return matches
    }

    /// Get decoded content for a note by its Z_PK
    private func getDecodedContent(forNotePK pk: Int64) throws -> String? {
        let contentQuery = "SELECT ZDATA FROM ZICNOTEDATA WHERE ZNOTE = ?"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, contentQuery, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, pk)

        if sqlite3_step(statement) == SQLITE_ROW {
            if let blob = sqlite3_column_blob(statement, 0) {
                let length = sqlite3_column_bytes(statement, 0)
                let data = Data(bytes: blob, count: Int(length))
                return try? decoder.decode(data)
            }
        }

        return nil
    }

    // MARK: - Attachment Operations

    /// Fetch attachments for a note by its Z_PK
    private func fetchAttachments(forNotePK notePK: Int64) throws -> [Attachment] {
        let query = """
            SELECT
                a.Z_PK as pk,
                a.ZIDENTIFIER as identifier,
                a.ZTITLE as name,
                a.ZTYPEUTI as typeUTI,
                a.ZFILESIZE as fileSize,
                a.ZCREATIONDATE as created,
                a.ZMODIFICATIONDATE as modified
            FROM ZICCLOUDSYNCINGOBJECT a
            WHERE a.Z_ENT = 5 AND a.ZNOTE = ?
            ORDER BY a.ZCREATIONDATE
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, notePK)

        var attachments: [Attachment] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let pk = sqlite3_column_int64(statement, 0)
            let identifier = columnString(statement, 1) ?? ""
            let name = columnString(statement, 2)
            let typeUTI = columnString(statement, 3) ?? "public.data"
            let fileSize = sqlite3_column_int64(statement, 4)
            let created = columnDate(statement, 5)
            let modified = columnDate(statement, 6)

            // Construct the x-coredata ID format
            let id = "x-coredata://E80D5A9D-1939-4C46-B3D4-E0EF27C98CE8/ICAttachment/p\(pk)"

            attachments.append(Attachment(
                id: id,
                identifier: identifier,
                name: name,
                typeUTI: typeUTI,
                fileSize: fileSize,
                createdAt: created,
                modifiedAt: modified
            ))
        }

        return attachments
    }

    /// Get attachment metadata by ID
    public func getAttachment(id: String) throws -> Attachment {
        try ensureOpen()

        // Extract PK from x-coredata URL (e.g., "x-coredata://...ICAttachment/p123" -> 123)
        guard let pkString = id.components(separatedBy: "/p").last,
              let pk = Int64(pkString) else {
            throw NotesError.attachmentNotFound(id)
        }

        let query = """
            SELECT
                a.Z_PK as pk,
                a.ZIDENTIFIER as identifier,
                a.ZTITLE as name,
                a.ZTYPEUTI as typeUTI,
                a.ZFILESIZE as fileSize,
                a.ZCREATIONDATE as created,
                a.ZMODIFICATIONDATE as modified
            FROM ZICCLOUDSYNCINGOBJECT a
            WHERE a.Z_ENT = 5 AND a.Z_PK = ?
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, pk)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NotesError.attachmentNotFound(id)
        }

        let identifier = columnString(statement, 1) ?? ""
        let name = columnString(statement, 2)
        let typeUTI = columnString(statement, 3) ?? "public.data"
        let fileSize = sqlite3_column_int64(statement, 4)
        let created = columnDate(statement, 5)
        let modified = columnDate(statement, 6)

        return Attachment(
            id: id,
            identifier: identifier,
            name: name,
            typeUTI: typeUTI,
            fileSize: fileSize,
            createdAt: created,
            modifiedAt: modified
        )
    }

    // MARK: - Write Operations

    /// Create a new note in the database
    /// - Parameters:
    ///   - title: The note title
    ///   - body: The note body content
    ///   - folderName: Optional folder name (uses "Notes" if nil)
    /// - Returns: The UUID of the created note
    public func createNote(title: String, body: String, folderName: String? = nil) throws -> String {
        try ensureOpenReadWrite()

        // Build the full note text (title + newlines + body)
        let fullText = body.isEmpty ? title : "\(title)\n\n\(body)"

        // Generate snippet (first line of body or empty)
        let snippet = body.components(separatedBy: "\n").first ?? ""

        // Find the folder
        let folderPK = try findFolder(named: folderName ?? "Notes")

        // Find the account (use iCloud account)
        let accountPK = try findAccount()

        // Generate new UUID
        let identifier = UUID().uuidString

        // Get current timestamp (Core Data format: seconds since 2001-01-01)
        let timestamp = Date().timeIntervalSinceReferenceDate

        // Encode the note content
        let encodedData = try encoder.encode(fullText)

        // Begin transaction
        try executeSQL("BEGIN TRANSACTION")

        do {
            // Allocate Z_PK for note (entity 3 = ICCloudSyncingObject)
            let notePK = try allocateNextPK(forEntity: 3)

            // Allocate Z_PK for note data (entity 19 = ICNoteData)
            let noteDataPK = try allocateNextPK(forEntity: 19)

            // Insert into ZICNOTEDATA first
            try insertNoteData(pk: noteDataPK, notePK: notePK, data: encodedData)

            // Insert into ZICCLOUDSYNCINGOBJECT
            try insertNote(
                pk: notePK,
                identifier: identifier,
                title: title,
                snippet: snippet,
                folderPK: folderPK,
                accountPK: accountPK,
                noteDataPK: noteDataPK,
                timestamp: timestamp
            )

            // Commit transaction
            try executeSQL("COMMIT")

            return identifier
        } catch {
            // Rollback on error
            try? executeSQL("ROLLBACK")
            throw error
        }
    }

    /// Extract hashtags from embedded objects for a note
    /// Uses ZTYPEUTI1 and ZALTTEXT columns for accurate extraction
    public func getHashtags(forNoteId id: String) throws -> [String] {
        try ensureOpen()

        // First get the note's Z_PK
        let pk = try getNotePK(id: id)

        // Query embedded objects with hashtag UTI
        // Check ZNOTE, ZNOTE1, and ZATTACHMENT relationships
        let query = """
            SELECT DISTINCT ZALTTEXT
            FROM ZICCLOUDSYNCINGOBJECT
            WHERE ZTYPEUTI1 = 'com.apple.notes.inlinetextattachment.hashtag'
              AND ZALTTEXT IS NOT NULL
              AND (ZNOTE = ? OR ZNOTE1 = ? OR ZATTACHMENT = ?)
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, pk)
        sqlite3_bind_int64(statement, 2, pk)
        sqlite3_bind_int64(statement, 3, pk)

        var hashtags: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let altText = columnString(statement, 0) {
                // ZALTTEXT may or may not have # prefix
                let tag = altText.hasPrefix("#") ? altText : "#\(altText)"
                hashtags.append(tag)
            }
        }

        return hashtags
    }

    /// Extract note-to-note links from embedded objects for a note
    /// Returns array of (linkText, targetNoteId) tuples
    public func getNoteLinks(forNoteId id: String) throws -> [(text: String, targetId: String)] {
        try ensureOpen()

        let pk = try getNotePK(id: id)

        let query = """
            SELECT ZALTTEXT, ZTOKENCONTENTIDENTIFIER
            FROM ZICCLOUDSYNCINGOBJECT
            WHERE ZTYPEUTI1 = 'com.apple.notes.inlinetextattachment.link'
              AND ZTOKENCONTENTIDENTIFIER LIKE 'applenotes:note/%'
              AND (ZNOTE = ? OR ZNOTE1 = ? OR ZATTACHMENT = ?)
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, pk)
        sqlite3_bind_int64(statement, 2, pk)
        sqlite3_bind_int64(statement, 3, pk)

        var links: [(text: String, targetId: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let linkText = columnString(statement, 0) ?? ""
            if let tokenId = columnString(statement, 1) {
                // Extract UUID from applenotes:note/UUID?ownerIdentifier=...
                // Format: applenotes:note/b1e9c1aa-b884-461c-9235-0a243f309729?ownerIdentifier=...
                if let range = tokenId.range(of: "applenotes:note/") {
                    var targetId = String(tokenId[range.upperBound...])
                    // Remove query parameters if present
                    if let queryRange = targetId.range(of: "?") {
                        targetId = String(targetId[..<queryRange.lowerBound])
                    }
                    links.append((text: linkText, targetId: targetId.uppercased()))
                }
            }
        }

        return links
    }

    /// Get the Z_PK (primary key) for a note by its UUID identifier
    func getNotePK(id: String) throws -> Int64 {
        try ensureOpen()

        let query = """
            SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT
            WHERE ZIDENTIFIER = ? AND Z_ENT = 12
            LIMIT 1
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NotesError.noteNotFound(id)
        }

        return sqlite3_column_int64(statement, 0)
    }

    /// List all unique hashtags in the database
    /// Uses embedded objects table with ZTYPEUTI1
    public func listHashtags() throws -> [String] {
        try ensureOpen()

        let query = """
            SELECT DISTINCT ZALTTEXT
            FROM ZICCLOUDSYNCINGOBJECT
            WHERE ZTYPEUTI1 = 'com.apple.notes.inlinetextattachment.hashtag'
              AND ZALTTEXT IS NOT NULL
            ORDER BY ZALTTEXT
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var hashtags: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let altText = columnString(statement, 0) {
                // ZALTTEXT may or may not have # prefix
                let tag = altText.hasPrefix("#") ? altText : "#\(altText)"
                hashtags.append(tag)
            }
        }

        return hashtags
    }

    /// List all note-to-note links in the database
    /// Returns array of (sourceNoteId, linkText, targetNoteId) tuples
    public func listNoteLinks() throws -> [(sourceId: String, text: String, targetId: String)] {
        try ensureOpen()

        let query = """
            SELECT
                n.ZIDENTIFIER as source_id,
                e.ZALTTEXT as link_text,
                e.ZTOKENCONTENTIDENTIFIER as target_url
            FROM ZICCLOUDSYNCINGOBJECT e
            JOIN ZICCLOUDSYNCINGOBJECT n ON (e.ZNOTE = n.Z_PK OR e.ZNOTE1 = n.Z_PK)
            WHERE e.ZTYPEUTI1 = 'com.apple.notes.inlinetextattachment.link'
              AND e.ZTOKENCONTENTIDENTIFIER LIKE 'applenotes:note/%'
              AND n.ZIDENTIFIER IS NOT NULL
            ORDER BY n.ZMODIFICATIONDATE1 DESC
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var links: [(sourceId: String, text: String, targetId: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let sourceId = columnString(statement, 0) ?? ""
            let linkText = columnString(statement, 1) ?? ""
            if let tokenId = columnString(statement, 2) {
                if let range = tokenId.range(of: "applenotes:note/") {
                    var targetId = String(tokenId[range.upperBound...])
                    if let queryRange = targetId.range(of: "?") {
                        targetId = String(targetId[..<queryRange.lowerBound])
                    }
                    links.append((sourceId: sourceId, text: linkText, targetId: targetId.uppercased()))
                }
            }
        }

        return links
    }

    /// Search notes by hashtag using embedded objects table
    public func searchNotesByHashtag(tag: String) throws -> [Note] {
        try ensureOpen()

        // Remove # prefix if present
        let cleanTag = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag

        // Search using embedded objects with hashtag UTI
        // ZALTTEXT can have # prefix or not
        let query = """
            SELECT DISTINCT
                n.ZIDENTIFIER as id,
                n.ZTITLE1 as title,
                f.ZTITLE2 as folder,
                n.ZCREATIONDATE1 as created,
                n.ZMODIFICATIONDATE1 as modified
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
            JOIN ZICCLOUDSYNCINGOBJECT e ON (e.ZNOTE = n.Z_PK OR e.ZNOTE1 = n.Z_PK)
            WHERE e.ZTYPEUTI1 = 'com.apple.notes.inlinetextattachment.hashtag'
              AND (e.ZALTTEXT = ? OR e.ZALTTEXT = ?)
              AND n.ZTITLE1 IS NOT NULL
            ORDER BY n.ZMODIFICATIONDATE1 DESC
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        // Bind both with and without # prefix
        sqlite3_bind_text(statement, 1, (cleanTag as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, ("#\(cleanTag)" as NSString).utf8String, -1, SQLITE_TRANSIENT)

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

    /// List available folders
    public func listFolders() throws -> [(pk: Int64, name: String)] {
        try ensureOpen()

        let query = """
            SELECT Z_PK, ZTITLE2
            FROM ZICCLOUDSYNCINGOBJECT
            WHERE Z_ENT = 15 AND ZTITLE2 IS NOT NULL
            ORDER BY ZTITLE2
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var folders: [(pk: Int64, name: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let pk = sqlite3_column_int64(statement, 0)
            let name = columnString(statement, 1) ?? ""
            folders.append((pk: pk, name: name))
        }

        return folders
    }

    // MARK: - Private Write Helpers

    private func ensureOpenReadWrite() throws {
        // If already open read-write, we're good
        if db != nil && isReadWrite { return }

        // Close existing read-only connection
        if let existingDb = db {
            sqlite3_close(existingDb)
            db = nil
        }

        let path = Permissions.notesDatabasePath
        guard FileManager.default.fileExists(atPath: path) else {
            throw NotesError.databaseNotFound
        }

        // Open read-write
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            let error = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw NotesError.cannotOpenDatabase(error)
        }

        isReadWrite = true
    }

    private func findFolder(named name: String) throws -> Int64 {
        let query = """
            SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT
            WHERE Z_ENT = 15 AND ZTITLE2 = ?
            LIMIT 1
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NotesError.folderNotFound(name)
        }

        return sqlite3_column_int64(statement, 0)
    }

    private func findAccount() throws -> Int64 {
        // Find the first (typically iCloud) account
        let query = """
            SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT
            WHERE Z_ENT = 14
            LIMIT 1
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NotesError.queryFailed("No account found")
        }

        return sqlite3_column_int64(statement, 0)
    }

    private func allocateNextPK(forEntity entity: Int) throws -> Int64 {
        // Read current max
        let selectQuery = "SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_ENT = ?"

        var selectStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, selectQuery, -1, &selectStatement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(selectStatement) }

        sqlite3_bind_int(selectStatement, 1, Int32(entity))

        guard sqlite3_step(selectStatement) == SQLITE_ROW else {
            throw NotesError.queryFailed("Entity \(entity) not found in Z_PRIMARYKEY")
        }

        let currentMax = sqlite3_column_int64(selectStatement, 0)
        let newPK = currentMax + 1

        // Update Z_MAX
        let updateQuery = "UPDATE Z_PRIMARYKEY SET Z_MAX = ? WHERE Z_ENT = ?"

        var updateStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, updateQuery, -1, &updateStatement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(updateStatement) }

        sqlite3_bind_int64(updateStatement, 1, newPK)
        sqlite3_bind_int(updateStatement, 2, Int32(entity))

        guard sqlite3_step(updateStatement) == SQLITE_DONE else {
            throw NotesError.queryFailed("Failed to update Z_MAX: \(String(cString: sqlite3_errmsg(db)))")
        }

        return newPK
    }

    private func insertNoteData(pk: Int64, notePK: Int64, data: Data) throws {
        let query = """
            INSERT INTO ZICNOTEDATA (Z_PK, Z_ENT, Z_OPT, ZNOTE, ZDATA)
            VALUES (?, 19, 1, ?, ?)
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, pk)
        sqlite3_bind_int64(statement, 2, notePK)

        data.withUnsafeBytes { ptr in
            sqlite3_bind_blob(statement, 3, ptr.baseAddress, Int32(data.count), nil)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NotesError.queryFailed("Failed to insert note data: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func insertNote(
        pk: Int64,
        identifier: String,
        title: String,
        snippet: String,
        folderPK: Int64,
        accountPK: Int64,
        noteDataPK: Int64,
        timestamp: Double
    ) throws {
        let query = """
            INSERT INTO ZICCLOUDSYNCINGOBJECT (
                Z_PK, Z_ENT, Z_OPT,
                ZACCOUNT7, ZFOLDER, ZNOTEDATA,
                ZIDENTIFIER, ZTITLE1, ZSNIPPET,
                ZCREATIONDATE3, ZMODIFICATIONDATE1,
                ZHASCHECKLIST, ZHASCHECKLISTINPROGRESS, ZHASEMPHASIS,
                ZHASSYSTEMTEXTATTACHMENTS, ZISPINNED, ZISSYSTEMPAPER,
                ZPAPERSTYLETYPE, ZPREFERREDBACKGROUNDTYPE
            ) VALUES (
                ?, 12, 1,
                ?, ?, ?,
                ?, ?, ?,
                ?, ?,
                0, 0, 0,
                0, 0, 0,
                0, 0
            )
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        sqlite3_bind_int64(statement, 1, pk)
        sqlite3_bind_int64(statement, 2, accountPK)
        sqlite3_bind_int64(statement, 3, folderPK)
        sqlite3_bind_int64(statement, 4, noteDataPK)
        sqlite3_bind_text(statement, 5, (identifier as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 6, (title as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 7, (snippet as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 8, timestamp)
        sqlite3_bind_double(statement, 9, timestamp)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NotesError.queryFailed("Failed to insert note: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func executeSQL(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
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
