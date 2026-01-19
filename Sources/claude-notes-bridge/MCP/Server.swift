import Foundation

/// MCP Server implementation using JSON-RPC over stdio
actor MCPServer {
    private let notesDB: NotesDatabase
    private var initialized = false

    init() {
        self.notesDB = NotesDatabase()
    }

    /// Main run loop - reads JSON-RPC requests from stdin, writes responses to stdout
    func run() async {
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
                        ]
                    ],
                    "required": ["id"]
                ]
            ],
            [
                "name": "search_notes",
                "description": "Search notes by text content",
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
                result = try notesDB.readNote(id: id)
            case "search_notes":
                guard let query = arguments["query"] as? String else {
                    throw NotesError.missingParameter("query")
                }
                let limit = arguments["limit"] as? Int ?? 20
                result = try notesDB.searchNotes(query: query, limit: limit)
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
            return notes.map { note in
                """
                📝 \(note.title)
                   ID: \(note.id)
                   Folder: \(note.folder ?? "Unknown")
                   Modified: \(note.modifiedAt?.description ?? "Unknown")
                """
            }.joined(separator: "\n\n")
        } else if let note = result as? NoteContent {
            return """
            # \(note.title)

            \(note.content)

            ---
            ID: \(note.id)
            Folder: \(note.folder ?? "Unknown")
            Created: \(note.createdAt?.description ?? "Unknown")
            Modified: \(note.modifiedAt?.description ?? "Unknown")
            """
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
