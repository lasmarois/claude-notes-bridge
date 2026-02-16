import Foundation

/// MCP Server implementation using JSON-RPC over stdio
public actor MCPServer {
    private let notesDB: NotesDatabase
    private let notesAS: NotesAppleScript
    private let searchIndex: SearchIndex
    private let semanticSearch: SemanticSearch
    private var initialized = false

    public init() {
        self.notesDB = NotesDatabase()
        self.notesAS = NotesAppleScript()
        self.searchIndex = SearchIndex(notesDB: notesDB)
        self.semanticSearch = SemanticSearch(notesDB: notesDB)
    }

    /// Main run loop - reads JSON-RPC requests from stdin, writes responses to stdout
    public func run() async {
        while let line = readLine() {
            guard let data = line.data(using: .utf8) else { continue }

            do {
                let request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
                let response = await handleRequest(request)
                try writeResponse(response)
            } catch {
                let errorResponse = JSONRPCResponse(
                    jsonrpc: "2.0",
                    id: nil,
                    result: nil,
                    error: JSONRPCError(code: -32700, message: "Parse error: \(error.localizedDescription)")
                )
                try? writeResponse(errorResponse)
            }
        }
    }

    private func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return handleInitialize(request)
        case "notifications/initialized":
            // Client acknowledges initialization - no response needed
            return JSONRPCResponse(jsonrpc: "2.0", id: request.id, result: .null, error: nil)
        case "tools/list":
            return handleToolsList(request)
        case "tools/call":
            return await handleToolsCall(request)
        default:
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: nil,
                error: JSONRPCError(code: -32601, message: "Method not found: \(request.method)")
            )
        }
    }

    private func handleInitialize(_ request: JSONRPCRequest) -> JSONRPCResponse {
        initialized = true
        let result: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": [:]
            ],
            "serverInfo": [
                "name": "claude-notes-bridge",
                "version": "0.1.0"
            ]
        ]
        return JSONRPCResponse(
            jsonrpc: "2.0",
            id: request.id,
            result: .dictionary(result),
            error: nil
        )
    }

    private func handleToolsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let tools: [[String: Any]] = [
            [
                "name": "list_notes",
                "description": "List all notes with their titles and metadata",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "folder": [
                            "type": "string",
                            "description": "Optional folder name to filter by"
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of notes to return"
                        ]
                    ]
                ]
            ],
            [
                "name": "read_note",
                "description": "Read the full content of a specific note",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "The note ID (UUID)"
                        ],
                        "format": [
                            "type": "string",
                            "description": "Output format: 'plain' (default) for plain text, 'html' for HTML with formatting preserved",
                            "enum": ["plain", "html"]
                        ]
                    ],
                    "required": ["id"]
                ]
            ],
            [
                "name": "search_notes",
                "description": "Search notes by text content. Searches title, snippet (first line), and folder name. Case-insensitive. Supports multi-term: 'term1 AND term2' or 'term1 OR term2'. Options: search_content (bodies), fuzzy (typo tolerance), folder/date filters.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "Search query"
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of results"
                        ],
                        "search_content": [
                            "type": "boolean",
                            "description": "If true, also search within note body content (slower but more thorough)"
                        ],
                        "fuzzy": [
                            "type": "boolean",
                            "description": "If true, enable typo-tolerant fuzzy matching (e.g., 'kubctl' finds 'kubectl')"
                        ],
                        "folder": [
                            "type": "string",
                            "description": "Filter by folder name (exact match, case-insensitive)"
                        ],
                        "modified_after": [
                            "type": "string",
                            "description": "Filter: modified after this date (ISO 8601, e.g., '2024-01-01')"
                        ],
                        "modified_before": [
                            "type": "string",
                            "description": "Filter: modified before this date (ISO 8601)"
                        ],
                        "created_after": [
                            "type": "string",
                            "description": "Filter: created after this date (ISO 8601)"
                        ],
                        "created_before": [
                            "type": "string",
                            "description": "Filter: created before this date (ISO 8601)"
                        ]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "create_note",
                "description": "Create a new note in Apple Notes. Supports markdown: # headers, **bold**, *italic*, ~~strike~~, `code` (colored), ```blocks```, - lists, > quotes.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "The note title"
                        ],
                        "body": [
                            "type": "string",
                            "description": "The note body content (supports markdown)"
                        ],
                        "folder": [
                            "type": "string",
                            "description": "Optional folder name (defaults to 'Notes')"
                        ]
                    ],
                    "required": ["title", "body"]
                ]
            ],
            [
                "name": "list_folders",
                "description": "List all available folders in Apple Notes",
                "inputSchema": [
                    "type": "object",
                    "properties": [:]
                ]
            ],
            [
                "name": "update_note",
                "description": "Update an existing note's title and/or body",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "The note ID (UUID or x-coredata URL)"
                        ],
                        "title": [
                            "type": "string",
                            "description": "New title (optional)"
                        ],
                        "body": [
                            "type": "string",
                            "description": "New body content (optional)"
                        ]
                    ],
                    "required": ["id"]
                ]
            ],
            [
                "name": "delete_note",
                "description": "Delete a note (moves to Recently Deleted)",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "The note ID (UUID or x-coredata URL)"
                        ]
                    ],
                    "required": ["id"]
                ]
            ],
            [
                "name": "create_folder",
                "description": "Create a new folder in Apple Notes",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "description": "The folder name"
                        ],
                        "parent": [
                            "type": "string",
                            "description": "Optional parent folder name for nested folders"
                        ]
                    ],
                    "required": ["name"]
                ]
            ],
            [
                "name": "move_note",
                "description": "Move a note to a different folder",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "The note ID (UUID or x-coredata URL)"
                        ],
                        "folder": [
                            "type": "string",
                            "description": "Target folder name"
                        ]
                    ],
                    "required": ["id", "folder"]
                ]
            ],
            [
                "name": "rename_folder",
                "description": "Rename an existing folder",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "old_name": [
                            "type": "string",
                            "description": "Current folder name"
                        ],
                        "new_name": [
                            "type": "string",
                            "description": "New folder name"
                        ]
                    ],
                    "required": ["old_name", "new_name"]
                ]
            ],
            [
                "name": "delete_folder",
                "description": "Delete a folder (notes inside will be moved to Recently Deleted)",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "description": "The folder name to delete"
                        ]
                    ],
                    "required": ["name"]
                ]
            ],
            [
                "name": "get_attachment",
                "description": "Get attachment metadata and file path. Use this to retrieve the file path for an attachment.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "The attachment ID (x-coredata URL from read_note response)"
                        ]
                    ],
                    "required": ["id"]
                ]
            ],
            [
                "name": "add_attachment",
                "description": "Add an attachment to an existing note",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "note_id": [
                            "type": "string",
                            "description": "The note ID (UUID or x-coredata URL)"
                        ],
                        "file_path": [
                            "type": "string",
                            "description": "Path to the file to attach (POSIX path)"
                        ]
                    ],
                    "required": ["note_id", "file_path"]
                ]
            ],
            [
                "name": "list_hashtags",
                "description": "List all unique hashtags used across all notes",
                "inputSchema": [
                    "type": "object",
                    "properties": [:]
                ]
            ],
            [
                "name": "search_by_hashtag",
                "description": "Find all notes containing a specific hashtag",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "tag": [
                            "type": "string",
                            "description": "The hashtag to search for (with or without # prefix)"
                        ]
                    ],
                    "required": ["tag"]
                ]
            ],
            [
                "name": "list_note_links",
                "description": "List all note-to-note links in the database. Shows which notes link to other notes.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:]
                ]
            ],
            [
                "name": "build_search_index",
                "description": "Build or rebuild the full-text search (FTS5) index for fast content search. This indexes all note content and enables much faster searching. Run once, then use fts_search.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:]
                ]
            ],
            [
                "name": "fts_search",
                "description": "Fast full-text search using FTS5 index. Much faster than search_notes with search_content=true. Requires build_search_index to be run first. Returns ranked results with snippets.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "Search query (supports phrases in quotes, OR between terms)"
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of results (default 20)"
                        ]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "semantic_search",
                "description": "Search notes by meaning using AI embeddings (MiniLM). Finds semantically similar notes even without exact keyword matches. Example: 'cooking recipes' finds notes about food preparation. First call builds the index (~10s for 2000 notes).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "Natural language query describing what you're looking for"
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of results (default 10)"
                        ]
                    ],
                    "required": ["query"]
                ]
            ]
        ]

        return JSONRPCResponse(
            jsonrpc: "2.0",
            id: request.id,
            result: .dictionary(["tools": tools]),
            error: nil
        )
    }

    private func handleToolsCall(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        guard let params = request.params,
              let name = params["name"] as? String else {
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: nil,
                error: JSONRPCError(code: -32602, message: "Invalid params: missing tool name")
            )
        }

        let arguments = params["arguments"] as? [String: Any] ?? [:]

        do {
            let result: Any
            switch name {
            case "list_notes":
                let folder = arguments["folder"] as? String
                let limit = arguments["limit"] as? Int ?? 100
                result = try notesDB.listNotes(folder: folder, limit: limit)
            case "read_note":
                guard let id = arguments["id"] as? String else {
                    throw NotesError.missingParameter("id")
                }
                let format = arguments["format"] as? String ?? "plain"
                var note = try notesDB.readNote(id: id)
                if format == "html" {
                    // Get Z_PK and construct x-coredata URL for AppleScript
                    let pk = try notesDB.getNotePK(id: id)
                    let coreDataId = "x-coredata://E80D5A9D-1939-4C46-B3D4-E0EF27C98CE8/ICNote/p\(pk)"
                    let htmlBody = try notesAS.getNoteBody(id: coreDataId)
                    var htmlNote = NoteContent(
                        id: note.id,
                        title: note.title,
                        content: htmlBody,
                        folder: note.folder,
                        createdAt: note.createdAt,
                        modifiedAt: note.modifiedAt
                    )
                    htmlNote.attachments = note.attachments
                    htmlNote.hashtags = note.hashtags
                    note = htmlNote
                }
                result = note
            case "search_notes":
                guard let query = arguments["query"] as? String else {
                    throw NotesError.missingParameter("query")
                }
                let limit = arguments["limit"] as? Int ?? 20
                let searchContent = arguments["search_content"] as? Bool ?? false
                let fuzzy = arguments["fuzzy"] as? Bool ?? false
                let folder = arguments["folder"] as? String

                // Parse ISO 8601 date filters
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withFullDate]
                let modifiedAfter = (arguments["modified_after"] as? String).flatMap { dateFormatter.date(from: $0) }
                let modifiedBefore = (arguments["modified_before"] as? String).flatMap { dateFormatter.date(from: $0) }
                let createdAfter = (arguments["created_after"] as? String).flatMap { dateFormatter.date(from: $0) }
                let createdBefore = (arguments["created_before"] as? String).flatMap { dateFormatter.date(from: $0) }

                let notes = try notesDB.searchNotes(
                    query: query,
                    limit: limit,
                    searchContent: searchContent,
                    fuzzy: fuzzy,
                    folder: folder,
                    modifiedAfter: modifiedAfter,
                    modifiedBefore: modifiedBefore,
                    createdAfter: createdAfter,
                    createdBefore: createdBefore
                )

                // Threshold fallback hint: if few results and advanced options weren't used, suggest them
                let threshold = 5
                if !searchContent && !fuzzy && notes.count < threshold && notes.count < limit {
                    result = ["notes": notes, "hint": "💡 Only \(notes.count) result(s) found. Try search_content=true (search bodies) or fuzzy=true (typo tolerance)."]
                } else {
                    result = notes
                }
            case "create_note":
                guard let title = arguments["title"] as? String else {
                    throw NotesError.missingParameter("title")
                }
                guard let body = arguments["body"] as? String else {
                    throw NotesError.missingParameter("body")
                }
                let folder = arguments["folder"] as? String
                // Use AppleScript for reliable CloudKit-compatible creation with markdown→HTML conversion
                let noteResult = try notesAS.createNote(title: title, body: body, folder: folder)

                // Resolve the x-coredata ID to a UUID so callers can use it with read_note
                var noteId: String = noteResult.id
                // x-coredata://DB-UUID/ICNote/p{Z_PK} — extract Z_PK from the last component
                if let lastSlash = noteResult.id.lastIndex(of: "/"),
                   let pk = Int64(String(noteResult.id[noteResult.id.index(after: lastSlash)...].dropFirst())) {
                    // dropFirst() removes the "p" prefix from "p1234"
                    if let uuid = try? notesDB.getNoteIdentifier(pk: pk) {
                        noteId = uuid
                    }
                }

                result = ["id": noteId, "title": title, "folder": folder ?? "Notes"]
            case "update_note":
                guard let id = arguments["id"] as? String else {
                    throw NotesError.missingParameter("id")
                }
                let title = arguments["title"] as? String
                let body = arguments["body"] as? String
                if title == nil && body == nil {
                    throw NotesError.missingParameter("title or body")
                }
                try notesAS.updateNote(id: id, title: title, body: body)
                result = ["id": id, "updated": true]
            case "delete_note":
                guard let id = arguments["id"] as? String else {
                    throw NotesError.missingParameter("id")
                }
                try notesAS.deleteNote(id: id)
                result = ["id": id, "deleted": true]
            case "list_folders":
                let folders = try notesDB.listFolders()
                result = folders.map { ["name": $0.name] }
            case "create_folder":
                guard let name = arguments["name"] as? String else {
                    throw NotesError.missingParameter("name")
                }
                let parent = arguments["parent"] as? String
                let folderName = try notesAS.createFolder(name: name, parentFolder: parent)
                result = ["name": folderName, "created": true, "parent": parent as Any]
            case "move_note":
                guard let id = arguments["id"] as? String else {
                    throw NotesError.missingParameter("id")
                }
                guard let folder = arguments["folder"] as? String else {
                    throw NotesError.missingParameter("folder")
                }
                try notesAS.moveNote(noteId: id, toFolder: folder)
                result = ["id": id, "moved": true, "folder": folder]
            case "rename_folder":
                guard let oldName = arguments["old_name"] as? String else {
                    throw NotesError.missingParameter("old_name")
                }
                guard let newName = arguments["new_name"] as? String else {
                    throw NotesError.missingParameter("new_name")
                }
                try notesAS.renameFolder(from: oldName, to: newName)
                result = ["old_name": oldName, "new_name": newName, "renamed": true]
            case "delete_folder":
                guard let name = arguments["name"] as? String else {
                    throw NotesError.missingParameter("name")
                }
                try notesAS.deleteFolder(name: name)
                result = ["name": name, "deleted": true]
            case "get_attachment":
                guard let id = arguments["id"] as? String else {
                    throw NotesError.missingParameter("id")
                }
                let attachment = try notesDB.getAttachment(id: id)
                // Get the file path via AppleScript
                let filePath = try notesAS.getAttachmentPath(id: id)
                result = [
                    "id": attachment.id,
                    "identifier": attachment.identifier,
                    "name": attachment.name ?? "Unknown",
                    "type": attachment.typeUTI,
                    "size": attachment.fileSize,
                    "path": filePath
                ] as [String: Any]
            case "add_attachment":
                guard let noteId = arguments["note_id"] as? String else {
                    throw NotesError.missingParameter("note_id")
                }
                guard let filePath = arguments["file_path"] as? String else {
                    throw NotesError.missingParameter("file_path")
                }
                let attachmentId = try notesAS.addAttachment(noteId: noteId, filePath: filePath)
                result = ["note_id": noteId, "attachment_id": attachmentId, "added": true]
            case "list_hashtags":
                let hashtags = try notesDB.listHashtags()
                result = ["hashtags": hashtags, "count": hashtags.count] as [String: Any]
            case "search_by_hashtag":
                guard let tag = arguments["tag"] as? String else {
                    throw NotesError.missingParameter("tag")
                }
                result = try notesDB.searchNotesByHashtag(tag: tag)
            case "list_note_links":
                let links = try notesDB.listNoteLinks()
                result = ["links": links.map { ["source_id": $0.sourceId, "text": $0.text, "target_id": $0.targetId] }, "count": links.count] as [String: Any]
            case "build_search_index":
                let count = try searchIndex.buildIndex()
                result = ["indexed": count, "message": "Successfully indexed \(count) notes"] as [String: Any]
            case "fts_search":
                guard let query = arguments["query"] as? String else {
                    throw NotesError.missingParameter("query")
                }
                let limit = arguments["limit"] as? Int ?? 20

                // Use auto-rebuild search (builds index if missing, rebuilds in background if stale)
                let (ftsResults, wasStale, isRebuilding) = try searchIndex.searchWithAutoRebuild(query: query, limit: limit)

                // Fetch full note metadata for each result
                var notes: [Note] = []
                for (noteId, snippet) in ftsResults {
                    if let note = try? notesDB.listNotes(limit: 10000).first(where: { $0.id == noteId }) {
                        notes.append(Note(
                            id: note.id,
                            title: note.title,
                            folder: note.folder,
                            createdAt: note.createdAt,
                            modifiedAt: note.modifiedAt,
                            matchSnippet: snippet.isEmpty ? nil : snippet
                        ))
                    }
                }

                var resultDict: [String: Any] = [
                    "notes": notes,
                    "count": notes.count,
                    "indexed_notes": searchIndex.indexedCount
                ]

                // Add staleness warning if applicable
                if wasStale {
                    if isRebuilding {
                        resultDict["warning"] = "⚠️ Index was stale, rebuilding in background. Results may be incomplete."
                    } else {
                        resultDict["warning"] = "⚠️ Index was stale and has been rebuilt."
                    }
                }

                result = resultDict
            case "semantic_search":
                guard let query = arguments["query"] as? String else {
                    throw NotesError.missingParameter("query")
                }
                let limit = arguments["limit"] as? Int ?? 10
                let searchResults = try await semanticSearch.search(query: query, limit: limit)
                result = ["results": searchResults, "count": searchResults.count, "indexed_notes": await semanticSearch.indexedCount] as [String: Any]
            default:
                return JSONRPCResponse(
                    jsonrpc: "2.0",
                    id: request.id,
                    result: nil,
                    error: JSONRPCError(code: -32602, message: "Unknown tool: \(name)")
                )
            }

            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: .dictionary([
                    "content": [
                        ["type": "text", "text": formatResult(result)]
                    ]
                ]),
                error: nil
            )
        } catch {
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: .dictionary([
                    "content": [
                        ["type": "text", "text": "Error: \(error.localizedDescription)"]
                    ],
                    "isError": true
                ]),
                error: nil
            )
        }
    }

    private func formatResult(_ result: Any) -> String {
        if let notes = result as? [Note] {
            if notes.isEmpty {
                return "No notes found."
            }
            return notes.map { note in
                var result = """
                📝 \(note.title)
                   ID: \(note.id)
                   Folder: \(note.folder ?? "Unknown")
                   Modified: \(note.modifiedAt?.description ?? "Unknown")
                """
                if let snippet = note.matchSnippet {
                    result += "\n   Match: \(snippet)"
                }
                return result
            }.joined(separator: "\n\n")
        } else if let searchResult = result as? [String: Any],
                  let notes = searchResult["notes"] as? [Note] {
            // Search result with optional hint or FTS metadata
            var output = notes.isEmpty ? "No notes found." : notes.map { note in
                var result = """
                📝 \(note.title)
                   ID: \(note.id)
                   Folder: \(note.folder ?? "Unknown")
                   Modified: \(note.modifiedAt?.description ?? "Unknown")
                """
                if let snippet = note.matchSnippet {
                    result += "\n   Match: \(snippet)"
                }
                return result
            }.joined(separator: "\n\n")

            if let hint = searchResult["hint"] as? String {
                output += "\n\n\(hint)"
            }

            // FTS search metadata
            if let indexedNotes = searchResult["indexed_notes"] as? Int {
                output += "\n\n📊 FTS Index: \(indexedNotes) notes indexed"
            }

            // Staleness warning
            if let warning = searchResult["warning"] as? String {
                output += "\n\(warning)"
            }

            return output
        } else if let searchResult = result as? [String: Any],
                  let errorMsg = searchResult["error"] as? String {
            // Error result (e.g., FTS index not built)
            return "⚠️ \(errorMsg)"
        } else if let searchResult = result as? [String: Any],
                  let indexed = searchResult["indexed"] as? Int {
            // Index build result
            let message = searchResult["message"] as? String ?? "Indexed \(indexed) notes"
            return "✅ \(message)"
        } else if let note = result as? NoteContent {
            var output = """
            # \(note.title)

            \(note.content)

            ---
            ID: \(note.id)
            Folder: \(note.folder ?? "Unknown")
            Created: \(note.createdAt?.description ?? "Unknown")
            Modified: \(note.modifiedAt?.description ?? "Unknown")
            """

            if !note.attachments.isEmpty {
                output += "\n\nAttachments (\(note.attachments.count)):"
                for att in note.attachments {
                    let name = att.name ?? "Unnamed"
                    let size = ByteCountFormatter.string(fromByteCount: att.fileSize, countStyle: .file)
                    output += "\n  📎 \(name) (\(att.typeUTI), \(size))"
                    output += "\n     ID: \(att.id)"
                }
            }

            if !note.hashtags.isEmpty {
                output += "\n\nHashtags: \(note.hashtags.joined(separator: " "))"
            }

            if !note.noteLinks.isEmpty {
                output += "\n\nNote Links (\(note.noteLinks.count)):"
                for link in note.noteLinks {
                    output += "\n  🔗 \(link.text)"
                    output += "\n     Target: \(link.targetId)"
                }
            }

            return output
        } else if let actionResult = result as? [String: Any] {
            // Handle various action results
            // Check for semantic search results
            if let semanticResults = actionResult["results"] as? [SemanticSearchResult] {
                let count = actionResult["count"] as? Int ?? semanticResults.count
                let indexed = actionResult["indexed_notes"] as? Int ?? 0
                var output = "Found \(count) semantically similar note(s) (index: \(indexed) notes):\n"
                for result in semanticResults {
                    let score = String(format: "%.2f", result.score)
                    output += "\n📝 \(result.title) (score: \(score))"
                    output += "\n   Folder: \(result.folder ?? "Notes")"
                    output += "\n   ID: \(result.noteId)\n"
                }
                return output
            }
            // Check for hashtag list result
            else if let hashtags = actionResult["hashtags"] as? [String] {
                let count = actionResult["count"] as? Int ?? hashtags.count
                let tagList = hashtags.joined(separator: "  ")
                return "Found \(count) hashtags:\n\n\(tagList)"
            }
            // Check for note links result
            else if let links = actionResult["links"] as? [[String: String]] {
                let count = actionResult["count"] as? Int ?? links.count
                if links.isEmpty {
                    return "No note-to-note links found in the database."
                }
                var output = "Found \(count) note-to-note link(s):\n"
                for link in links {
                    let sourceId = link["source_id"] ?? "?"
                    let text = link["text"] ?? "?"
                    let targetId = link["target_id"] ?? "?"
                    output += "\n🔗 \"\(text)\""
                    output += "\n   Source: \(sourceId)"
                    output += "\n   Target: \(targetId)\n"
                }
                return output
            }
            // Check for attachment results (they have id but also path or added)
            else if let path = actionResult["path"] as? String {
                // Get attachment result
                let name = actionResult["name"] as? String ?? "Unknown"
                let type = actionResult["type"] as? String ?? "Unknown"
                let size = actionResult["size"] as? Int64 ?? 0
                let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                let id = actionResult["id"] as? String ?? "Unknown"
                return """
                📎 Attachment: \(name)

                Type: \(type)
                Size: \(sizeStr)
                Path: \(path)
                ID: \(id)
                """
            } else if actionResult["added"] as? Bool == true,
                      let attachmentId = actionResult["attachment_id"] as? String {
                // Add attachment result
                let noteId = actionResult["note_id"] as? String ?? "Unknown"
                return """
                ✅ Attachment added successfully!

                Note ID: \(noteId)
                Attachment ID: \(attachmentId)
                """
            } else if let id = actionResult["id"] as? String {
                // Note operations
                if let title = actionResult["title"] as? String {
                    // Create note result
                    let folder = actionResult["folder"] as? String ?? "Notes"
                    return """
                    ✅ Note created successfully!

                    Title: \(title)
                    ID: \(id)
                    Folder: \(folder)
                    """
                } else if actionResult["updated"] as? Bool == true {
                    // Update note result
                    return """
                    ✅ Note updated successfully!

                    ID: \(id)
                    """
                } else if actionResult["deleted"] as? Bool == true {
                    // Delete note result
                    return """
                    ✅ Note deleted successfully!

                    ID: \(id)
                    Note moved to Recently Deleted.
                    """
                } else if actionResult["moved"] as? Bool == true {
                    // Move note result
                    let folder = actionResult["folder"] as? String ?? "Unknown"
                    return """
                    ✅ Note moved successfully!

                    ID: \(id)
                    New folder: \(folder)
                    """
                }
            } else if let name = actionResult["name"] as? String {
                // Folder operations
                if actionResult["created"] as? Bool == true {
                    // Create folder result
                    if let parent = actionResult["parent"] as? String {
                        return """
                        ✅ Folder created successfully!

                        Name: \(name)
                        Parent: \(parent)
                        """
                    } else {
                        return """
                        ✅ Folder created successfully!

                        Name: \(name)
                        """
                    }
                } else if actionResult["deleted"] as? Bool == true {
                    // Delete folder result
                    return """
                    ✅ Folder deleted successfully!

                    Name: \(name)
                    Notes moved to Recently Deleted.
                    """
                }
            } else if actionResult["renamed"] as? Bool == true {
                // Rename folder result
                let oldName = actionResult["old_name"] as? String ?? "Unknown"
                let newName = actionResult["new_name"] as? String ?? "Unknown"
                return """
                ✅ Folder renamed successfully!

                From: \(oldName)
                To: \(newName)
                """
            }
            return String(describing: result)
        } else if let folders = result as? [[String: String]] {
            let folderList = folders.map { "📁 \($0["name"] ?? "Unknown")" }.joined(separator: "\n")
            return "Available folders:\n\n\(folderList)"
        } else {
            return String(describing: result)
        }
    }

    private func writeResponse(_ response: JSONRPCResponse) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NotesError.encodingError
        }
        print(json)
        fflush(stdout)
    }
}
