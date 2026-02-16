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
    /// - Parameters:
    ///   - folder: Optional folder name to filter by
    ///   - limit: Maximum number of notes to return
    ///   - includeDeleted: If true, includes notes marked for deletion (Recently Deleted)
    public func listNotes(folder: String? = nil, limit: Int = 100, includeDeleted: Bool = false) throws -> [Note] {
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

        // Filter out deleted notes unless explicitly requested
        if !includeDeleted {
            query += " AND (n.ZMARKEDFORDELETION IS NULL OR n.ZMARKEDFORDELETION = 0)"
            query += " AND f.ZTITLE2 != 'Recently Deleted'"
        }

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

    /// Get the latest modification date across all notes (for staleness detection)
    public func getLatestModificationDate() throws -> Date? {
        try ensureOpen()

        let query = """
            SELECT MAX(ZMODIFICATIONDATE1) as latest
            FROM ZICCLOUDSYNCINGOBJECT
            WHERE ZTITLE1 IS NOT NULL
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_ROW {
            return columnDate(statement, 0)
        }

        return nil
    }

    /// Read a single note's full content
    public func readNote(id: String, includeTables: Bool = true) throws -> NoteContent {
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
        var htmlContent: String? = nil
        if sqlite3_step(contentStatement) == SQLITE_ROW {
            if let blob = sqlite3_column_blob(contentStatement, 0) {
                let length = sqlite3_column_bytes(contentStatement, 0)
                let data = Data(bytes: blob, count: Int(length))
                // Decode with styling for HTML
                var styledContent = try decoder.decodeStyled(data)
                content = stripLeadingTitle(styledContent.text, title: title)

                // Fetch tables if requested (skip during indexing for performance)
                if includeTables {
                    let tableRefs = decoder.extractTableReferences(from: data)
                    for ref in tableRefs {
                        if let tableData = try? fetchTableData(uuid: ref.uuid),
                           let table = decoder.parseCRDTTable(tableData, position: ref.position) {
                            styledContent.tables.append(table)
                        }
                    }
                }

                htmlContent = styledContent.toHTML(darkMode: false)
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
            modifiedAt: modified,
            htmlContent: htmlContent
        )
        noteContent.attachments = attachments
        noteContent.hashtags = hashtags
        noteContent.noteLinks = noteLinks

        return noteContent
    }

    /// Fetch table data by UUID from ZMERGEABLEDATA1
    public func fetchTableData(uuid: String) throws -> Data? {
        try ensureOpen()

        let query = """
            SELECT ZMERGEABLEDATA1
            FROM ZICCLOUDSYNCINGOBJECT
            WHERE ZIDENTIFIER = ?
            AND ZTYPEUTI = 'com.apple.notes.table'
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, (uuid as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let blob = sqlite3_column_blob(statement, 0) else {
            return nil
        }

        let length = sqlite3_column_bytes(statement, 0)
        return Data(bytes: blob, count: Int(length))
    }

    // MARK: - Snippet Extraction

    /// Extract a snippet around the first match with highlighted terms
    /// - Parameters:
    ///   - text: The full text to extract from
    ///   - terms: Search terms to find and highlight
    ///   - windowSize: Characters before/after match to include (default 40)
    /// - Returns: Snippet with **highlighted** terms, or nil if no match
    private func extractSnippet(from text: String, terms: [String], windowSize: Int = 40) -> String? {
        let lowerText = text.lowercased()

        // Find the first matching term and its position
        var firstMatchPos: String.Index? = nil
        var matchedTerm: String? = nil

        for term in terms {
            if let range = lowerText.range(of: term.lowercased()) {
                if firstMatchPos == nil || range.lowerBound < firstMatchPos! {
                    firstMatchPos = range.lowerBound
                    matchedTerm = term
                }
            }
        }

        guard let matchPos = firstMatchPos, let _ = matchedTerm else {
            return nil
        }

        // Calculate snippet window
        let matchDistance = lowerText.distance(from: lowerText.startIndex, to: matchPos)
        let startOffset = max(0, matchDistance - windowSize)
        let endOffset = min(text.count, matchDistance + windowSize + 20)

        let startIndex = text.index(text.startIndex, offsetBy: startOffset)
        let endIndex = text.index(text.startIndex, offsetBy: endOffset)

        var snippet = String(text[startIndex..<endIndex])

        // Add ellipsis if truncated
        if startOffset > 0 { snippet = "..." + snippet }
        if endOffset < text.count { snippet = snippet + "..." }

        // Highlight all matching terms with **bold**
        for term in terms {
            // Case-insensitive replacement with highlight markers
            let pattern = "(?i)" + NSRegularExpression.escapedPattern(for: term)
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(snippet.startIndex..., in: snippet)
                snippet = regex.stringByReplacingMatches(in: snippet, range: range, withTemplate: "**$0**")
            }
        }

        // Clean up: collapse whitespace and newlines
        snippet = snippet.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return snippet
    }

    // MARK: - Fuzzy Matching

    /// Calculate Levenshtein distance between two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1.lowercased())
        let s2 = Array(s2.lowercased())

        let m = s1.count
        let n = s2.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i - 1][j - 1] + cost, // substitution
                    matrix[i][j - 1] + 1       // insertion
                )
            }
        }

        return matrix[m][n]
    }

    /// Check if a word fuzzy-matches a query term
    /// Threshold: max 2 edits for words <= 5 chars, max 3 for longer
    private func fuzzyMatch(_ word: String, query: String) -> Bool {
        let threshold = query.count <= 5 ? 2 : 3
        return levenshteinDistance(word, query) <= threshold
    }

    /// Check if text contains a fuzzy match for the query
    private func textContainsFuzzyMatch(_ text: String, query: String) -> Bool {
        // First check exact substring match
        if text.lowercased().contains(query.lowercased()) {
            return true
        }

        // Then check word-level fuzzy matching
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0) }

        return words.contains { fuzzyMatch($0, query: query) }
    }

    // MARK: - Query Parsing

    /// Parse query for AND/OR operators
    /// Returns (terms, isAndQuery) - if no operators, treats as single term
    private func parseMultiTermQuery(_ query: String) -> (terms: [String], isAndQuery: Bool) {
        // Check for explicit AND/OR (case-insensitive)
        let upperQuery = query.uppercased()

        if upperQuery.contains(" AND ") {
            let terms = query
                .replacingOccurrences(of: " AND ", with: "\u{0000}", options: .caseInsensitive)
                .split(separator: "\u{0000}")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return (terms, true)
        } else if upperQuery.contains(" OR ") {
            let terms = query
                .replacingOccurrences(of: " OR ", with: "\u{0000}", options: .caseInsensitive)
                .split(separator: "\u{0000}")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return (terms, false)
        }

        // No operators - single term
        return ([query], true)
    }

    /// Build SQL condition for a single search term
    private func buildTermCondition(termIndex: Int) -> String {
        let base = termIndex * 3
        return """
            (
                LOWER(n.ZTITLE1) LIKE '%' || LOWER(?\(base + 1)) || '%'
                OR LOWER(COALESCE(n.ZSNIPPET, '')) LIKE '%' || LOWER(?\(base + 2)) || '%'
                OR LOWER(COALESCE(f.ZTITLE2, '')) LIKE '%' || LOWER(?\(base + 3)) || '%'
            )
            """
    }

    /// Search notes by content
    /// Enhanced search: case-insensitive, searches title + snippet + folder name
    /// Supports multi-term queries: "term1 AND term2" or "term1 OR term2"
    /// Set searchContent=true to also search decoded note body (slower)
    /// Set fuzzy=true to enable typo-tolerant matching using Levenshtein distance
    /// Filters: folder (exact match), modifiedAfter/Before, createdAfter/Before (ISO dates)
    public func searchNotes(
        query: String,
        limit: Int = 20,
        searchContent: Bool = false,
        fuzzy: Bool = false,
        folder: String? = nil,
        modifiedAfter: Date? = nil,
        modifiedBefore: Date? = nil,
        createdAfter: Date? = nil,
        createdBefore: Date? = nil
    ) throws -> [Note] {
        try ensureOpen()

        let (terms, isAndQuery) = parseMultiTermQuery(query)
        let connector = isAndQuery ? " AND " : " OR "

        // Build dynamic WHERE clause for multi-term search
        let termConditions = terms.enumerated().map { idx, _ in buildTermCondition(termIndex: idx) }
        let whereClause = termConditions.joined(separator: connector)

        // Build filter conditions
        var filterConditions: [String] = []
        var nextParamIndex = terms.count * 3 + 1

        if folder != nil {
            filterConditions.append("LOWER(f.ZTITLE2) = LOWER(?\(nextParamIndex))")
            nextParamIndex += 1
        }

        // Apple Notes stores dates as seconds since 2001-01-01 (Core Data reference date)
        let coreDataEpoch: TimeInterval = 978307200 // Seconds between 1970 and 2001
        if modifiedAfter != nil {
            filterConditions.append("n.ZMODIFICATIONDATE1 >= ?\(nextParamIndex)")
            nextParamIndex += 1
        }
        if modifiedBefore != nil {
            filterConditions.append("n.ZMODIFICATIONDATE1 <= ?\(nextParamIndex)")
            nextParamIndex += 1
        }
        if createdAfter != nil {
            filterConditions.append("n.ZCREATIONDATE1 >= ?\(nextParamIndex)")
            nextParamIndex += 1
        }
        if createdBefore != nil {
            filterConditions.append("n.ZCREATIONDATE1 <= ?\(nextParamIndex)")
            nextParamIndex += 1
        }

        let filterClause = filterConditions.isEmpty ? "" : " AND " + filterConditions.joined(separator: " AND ")

        // Phase 1: Fast search using indexed columns (title, snippet, folder)
        let searchQuery = """
            SELECT
                n.ZIDENTIFIER as id,
                n.ZTITLE1 as title,
                f.ZTITLE2 as folder,
                n.ZCREATIONDATE1 as created,
                n.ZMODIFICATIONDATE1 as modified,
                n.ZSNIPPET as noteSnippet
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
            WHERE n.ZTITLE1 IS NOT NULL
              AND (\(whereClause))\(filterClause)
            ORDER BY n.ZMODIFICATIONDATE1 DESC
            LIMIT ?\(nextParamIndex)
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, searchQuery, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        let SQLITE_TRANSIENT_SEARCH = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        // Bind each term 3 times (for title, snippet, folder)
        for (idx, term) in terms.enumerated() {
            let base = idx * 3
            sqlite3_bind_text(statement, Int32(base + 1), (term as NSString).utf8String, -1, SQLITE_TRANSIENT_SEARCH)
            sqlite3_bind_text(statement, Int32(base + 2), (term as NSString).utf8String, -1, SQLITE_TRANSIENT_SEARCH)
            sqlite3_bind_text(statement, Int32(base + 3), (term as NSString).utf8String, -1, SQLITE_TRANSIENT_SEARCH)
        }

        // Bind filter parameters
        var bindIndex = Int32(terms.count * 3 + 1)
        if let folder = folder {
            sqlite3_bind_text(statement, bindIndex, (folder as NSString).utf8String, -1, SQLITE_TRANSIENT_SEARCH)
            bindIndex += 1
        }
        if let modifiedAfter = modifiedAfter {
            sqlite3_bind_double(statement, bindIndex, modifiedAfter.timeIntervalSinceReferenceDate)
            bindIndex += 1
        }
        if let modifiedBefore = modifiedBefore {
            sqlite3_bind_double(statement, bindIndex, modifiedBefore.timeIntervalSinceReferenceDate)
            bindIndex += 1
        }
        if let createdAfter = createdAfter {
            sqlite3_bind_double(statement, bindIndex, createdAfter.timeIntervalSinceReferenceDate)
            bindIndex += 1
        }
        if let createdBefore = createdBefore {
            sqlite3_bind_double(statement, bindIndex, createdBefore.timeIntervalSinceReferenceDate)
            bindIndex += 1
        }
        sqlite3_bind_int(statement, bindIndex, Int32(limit))

        var notes: [Note] = []
        var foundIds = Set<String>()

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = columnString(statement, 0) ?? ""
            let title = columnString(statement, 1) ?? "Untitled"
            let folder = columnString(statement, 2)
            let created = columnDate(statement, 3)
            let modified = columnDate(statement, 4)
            let noteSnippet = columnString(statement, 5)

            // Generate match snippet from title, snippet, or folder
            let searchableText = title + " | " + (noteSnippet ?? "") + " | " + (folder ?? "")
            let matchSnippet = extractSnippet(from: searchableText, terms: terms)

            foundIds.insert(id)
            notes.append(Note(
                id: id,
                title: title,
                folder: folder,
                createdAt: created,
                modifiedAt: modified,
                matchSnippet: matchSnippet
            ))
        }

        // Phase 2: If searchContent=true and we haven't hit limit, search note bodies
        if searchContent && notes.count < limit {
            let contentMatches = try searchNoteContent(terms: terms, isAndQuery: isAndQuery, limit: limit - notes.count, excludeIds: foundIds)
            notes.append(contentsOf: contentMatches)
            for note in contentMatches {
                foundIds.insert(note.id)
            }
        }

        // Phase 3: If fuzzy=true and we haven't hit limit, do fuzzy matching on titles/folders
        if fuzzy && notes.count < limit {
            let fuzzyMatches = try searchNotesFuzzy(terms: terms, isAndQuery: isAndQuery, limit: limit - notes.count, excludeIds: foundIds)
            notes.append(contentsOf: fuzzyMatches)
        }

        return notes
    }

    /// Fuzzy search on note titles and folders using Levenshtein distance
    private func searchNotesFuzzy(terms: [String], isAndQuery: Bool, limit: Int, excludeIds: Set<String>) throws -> [Note] {
        // Fetch all notes and filter with fuzzy matching
        let allNotesQuery = """
            SELECT
                n.ZIDENTIFIER as id,
                n.ZTITLE1 as title,
                f.ZTITLE2 as folder,
                n.ZCREATIONDATE1 as created,
                n.ZMODIFICATIONDATE1 as modified
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

        while sqlite3_step(statement) == SQLITE_ROW && matches.count < limit {
            let id = columnString(statement, 0) ?? ""

            // Skip already found notes
            if excludeIds.contains(id) { continue }

            let title = columnString(statement, 1) ?? "Untitled"
            let folder = columnString(statement, 2)
            let created = columnDate(statement, 3)
            let modified = columnDate(statement, 4)

            // Combine title and folder for fuzzy matching
            let searchableText = title + " | " + (folder ?? "")

            // Check if all/any terms fuzzy-match
            let termMatches = terms.map { textContainsFuzzyMatch(searchableText, query: $0) }
            let matchesQuery = isAndQuery ? termMatches.allSatisfy { $0 } : termMatches.contains(true)

            if matchesQuery {
                // Generate snippet with fuzzy-matched terms highlighted
                let matchSnippet = extractSnippet(from: searchableText, terms: terms)

                matches.append(Note(
                    id: id,
                    title: title,
                    folder: folder,
                    createdAt: created,
                    modifiedAt: modified,
                    matchSnippet: matchSnippet
                ))
            }
        }

        return matches
    }

    /// Search within decoded note content (protobuf bodies)
    /// This is slower as it requires decoding each note
    private func searchNoteContent(terms: [String], isAndQuery: Bool, limit: Int, excludeIds: Set<String>) throws -> [Note] {
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
        let lowerTerms = terms.map { $0.lowercased() }

        while sqlite3_step(statement) == SQLITE_ROW && matches.count < limit {
            let id = columnString(statement, 0) ?? ""

            // Skip already found notes
            if excludeIds.contains(id) { continue }

            let title = columnString(statement, 1) ?? "Untitled"
            let folder = columnString(statement, 2)
            let created = columnDate(statement, 3)
            let modified = columnDate(statement, 4)
            let pk = sqlite3_column_int64(statement, 5)

            // Decode note content and search with multi-term logic
            if let content = try? getDecodedContent(forNotePK: pk) {
                let lowerContent = content.lowercased()
                let termMatches = lowerTerms.map { lowerContent.contains($0) }
                let matches_query = isAndQuery ? termMatches.allSatisfy { $0 } : termMatches.contains(true)

                if matches_query {
                    // Extract snippet from content with highlighted terms
                    let matchSnippet = extractSnippet(from: content, terms: terms, windowSize: 60)

                    matches.append(Note(
                        id: id,
                        title: title,
                        folder: folder,
                        createdAt: created,
                        modifiedAt: modified,
                        matchSnippet: matchSnippet
                    ))
                }
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

    /// Get styled content (with attribute runs) for a note by its ID
    /// This decodes the protobuf and returns the full styled content including paragraph styles
    public func getStyledContent(forNoteId id: String) throws -> StyledNoteContent? {
        // First get the Z_PK for this note
        let pkQuery = "SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = '\(id)'"

        var pkStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, pkQuery, -1, &pkStatement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(pkStatement) }

        guard sqlite3_step(pkStatement) == SQLITE_ROW else {
            return nil
        }
        let pk = sqlite3_column_int64(pkStatement, 0)

        // Now get the ZDATA
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
                var styledContent = try decoder.decodeStyled(data)

                // Fetch tables
                let tableRefs = decoder.extractTableReferences(from: data)
                for ref in tableRefs {
                    if let tableData = try? fetchTableData(uuid: ref.uuid),
                       let table = decoder.parseCRDTTable(tableData, position: ref.position) {
                        styledContent.tables.append(table)
                    }
                }

                return styledContent
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

    /// List available accounts
    public func listAccounts() throws -> [(pk: Int64, name: String)] {
        try ensureOpen()

        let query = """
            SELECT Z_PK, ZNAME
            FROM ZICCLOUDSYNCINGOBJECT
            WHERE Z_ENT = 14 AND ZNAME IS NOT NULL
            ORDER BY Z_PK
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var accounts: [(pk: Int64, name: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let pk = sqlite3_column_int64(statement, 0)
            let name = columnString(statement, 1) ?? ""
            accounts.append((pk: pk, name: name))
        }

        return accounts
    }

    /// List available folders with account info, ordered to match Notes app
    public func listFoldersWithAccounts() throws -> [(pk: Int64, name: String, accountPK: Int64?, accountName: String?)] {
        try ensureOpen()

        // Query folders with their parent account, excluding deleted/system folders
        // ZMARKEDFORDELETION = 1 means folder is in trash
        // Only show folders that have at least one non-deleted note
        let query = """
            SELECT DISTINCT f.Z_PK, f.ZTITLE2, a.Z_PK, a.ZNAME
            FROM ZICCLOUDSYNCINGOBJECT f
            LEFT JOIN ZICCLOUDSYNCINGOBJECT a ON f.ZACCOUNT4 = a.Z_PK
            INNER JOIN ZICCLOUDSYNCINGOBJECT n ON n.ZFOLDER = f.Z_PK
            WHERE f.Z_ENT = 15
            AND f.ZTITLE2 IS NOT NULL
            AND f.ZTITLE2 != 'Recently Deleted'
            AND (f.ZMARKEDFORDELETION IS NULL OR f.ZMARKEDFORDELETION = 0)
            AND n.ZTITLE1 IS NOT NULL
            AND (n.ZMARKEDFORDELETION IS NULL OR n.ZMARKEDFORDELETION = 0)
            ORDER BY a.Z_PK, f.Z_PK
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var folders: [(pk: Int64, name: String, accountPK: Int64?, accountName: String?)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let pk = sqlite3_column_int64(statement, 0)
            let name = columnString(statement, 1) ?? ""
            let accountPK: Int64? = sqlite3_column_type(statement, 2) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 2)
            let accountName = columnString(statement, 3)
            folders.append((pk: pk, name: name, accountPK: accountPK, accountName: accountName))
        }

        // Sort to match Notes app: group by account, then "Notes" first within each
        folders.sort { a, b in
            // First by account (maintain database order)
            if a.accountPK != b.accountPK {
                return (a.accountPK ?? 0) < (b.accountPK ?? 0)
            }
            // Within same account: "Notes" first
            if a.name == "Notes" { return true }
            if b.name == "Notes" { return false }
            // Otherwise by Z_PK (creation order)
            return a.pk < b.pk
        }

        return folders
    }

    /// List available folders (simple version for backward compatibility)
    public func listFolders() throws -> [(pk: Int64, name: String)] {
        let foldersWithAccounts = try listFoldersWithAccounts()
        return foldersWithAccounts.map { (pk: $0.pk, name: $0.name) }
    }

    /// Debug: dump attribute runs for a note
    public func debugNoteStyles(id: String) throws -> String {
        try ensureOpen()

        let query = """
            SELECT d.ZDATA
            FROM ZICCLOUDSYNCINGOBJECT n
            JOIN ZICNOTEDATA d ON n.ZNOTEDATA = d.Z_PK
            WHERE n.ZIDENTIFIER = ?
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let blob = sqlite3_column_blob(statement, 0) else {
            throw NotesError.noteNotFound(id)
        }

        let length = sqlite3_column_bytes(statement, 0)
        let data = Data(bytes: blob, count: Int(length))

        return decoder.debugDumpStyles(data)
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

    /// Look up a note's UUID (ZIDENTIFIER) by its Z_PK (primary key).
    /// Used to resolve x-coredata IDs (which contain the Z_PK) to UUIDs after note creation.
    public func getNoteIdentifier(pk: Int64) throws -> String? {
        try ensureOpen()

        let query = "SELECT ZIDENTIFIER FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK = ? AND Z_ENT = 12 LIMIT 1"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NotesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, pk)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return columnString(statement, 0)
    }

    /// Strip the leading title line from protobuf-decoded content if it matches the note title.
    /// Apple Notes stores the title as the first paragraph of the body, but we already return it
    /// as a separate `title` field — so strip it from `content` to avoid duplication.
    private func stripLeadingTitle(_ text: String, title: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard let firstLine = lines.first else { return text }

        let trimmedFirst = firstLine.trimmingCharacters(in: .whitespaces)
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)

        guard !trimmedFirst.isEmpty,
              trimmedFirst.lowercased() == trimmedTitle.lowercased() else {
            return text
        }

        // Skip the title line and any immediately following blank lines
        var startIndex = 1
        while startIndex < lines.count &&
              lines[startIndex].trimmingCharacters(in: .whitespaces).isEmpty {
            startIndex += 1
        }

        return lines[startIndex...].joined(separator: "\n")
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
