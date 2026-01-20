import ArgumentParser
import Foundation
import NotesLib

// MARK: - Terminal Colors

enum TerminalStyle {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let cyan = "\u{001B}[36m"

    static func error(_ message: String) -> String {
        "\(red)\(bold)Error:\(reset) \(message)"
    }

    static func success(_ message: String) -> String {
        "\(green)✓\(reset) \(message)"
    }

    static func warning(_ message: String) -> String {
        "\(yellow)⚠\(reset) \(message)"
    }

    static func title(_ text: String) -> String {
        "\(bold)\(text)\(reset)"
    }

    static func noteTitle(_ text: String) -> String {
        "\(cyan)📝 \(text)\(reset)"
    }

    static func folder(_ text: String) -> String {
        "\(yellow)📁 \(text)\(reset)"
    }
}

// MARK: - Exit Codes

enum ExitCode: Int32 {
    case success = 0
    case generalError = 1
    case permissionDenied = 2
    case notFound = 3
}

// MARK: - Root Command

@main
struct NotesBridge: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude-notes-bridge",
        abstract: "Apple Notes bridge for Claude/MCP integration",
        discussion: """
            A tool for reading, searching, and managing Apple Notes.

            When run without a subcommand, starts the MCP server for Claude integration.
            Use subcommands for direct CLI access to your notes.

            Requires Full Disk Access permission in System Settings > Privacy & Security.
            """,
        version: "0.2.0",
        subcommands: [
            Serve.self,
            Search.self,
            List.self,
            Read.self,
            Folders.self
        ],
        defaultSubcommand: Serve.self
    )
}

// MARK: - Serve Command (MCP Server)

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the MCP server for Claude integration",
        discussion: "Runs the JSON-RPC MCP server over stdio. This is the default command."
    )

    func run() async throws {
        // Check Full Disk Access first
        guard Permissions.hasFullDiskAccess() else {
            printPermissionError()
            throw ExitCode.permissionDenied
        }

        // Start MCP server
        let server = MCPServer()
        await server.run()
    }
}

// MARK: - Search Command

struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search notes by keyword or semantic similarity",
        discussion: """
            Search your Apple Notes using various methods:
            - Default: Searches titles and snippets
            - With --content: Also searches note body text
            - With --semantic: Uses AI to find conceptually similar notes
            - With --fts: Uses full-text search index (fastest for content)
            """
    )

    @Argument(help: "Search query")
    var query: String

    @Option(name: .shortAndLong, help: "Maximum number of results")
    var limit: Int = 10

    @Flag(name: .long, help: "Search within note content (slower)")
    var content: Bool = false

    @Flag(name: .long, help: "Use semantic search (AI-powered)")
    var semantic: Bool = false

    @Flag(name: .long, help: "Use full-text search index")
    var fts: Bool = false

    @Flag(name: .long, help: "Enable fuzzy matching for typos")
    var fuzzy: Bool = false

    @Option(name: .long, help: "Filter by folder name")
    var folder: String?

    func run() async throws {
        guard Permissions.hasFullDiskAccess() else {
            printPermissionError()
            throw ExitCode.permissionDenied
        }

        let db = NotesDatabase()

        if semantic {
            // Semantic search
            print(TerminalStyle.title("Semantic search for: \"\(query)\"\n"))

            let semanticSearch = SemanticSearch(notesDB: db)
            let results = try await semanticSearch.search(query: query, limit: limit)

            if results.isEmpty {
                print("No results found.")
            } else {
                for result in results {
                    let score = String(format: "%.2f", result.score)
                    print(TerminalStyle.noteTitle(result.title))
                    print("   Score: \(score)")
                    print("   Folder: \(result.folder ?? "Notes")")
                    print("   ID: \(TerminalStyle.dim)\(result.noteId)\(TerminalStyle.reset)")
                    print("")
                }
                print("\(TerminalStyle.dim)Found \(results.count) result(s)\(TerminalStyle.reset)")
            }
        } else if fts {
            // FTS search
            print(TerminalStyle.title("Full-text search for: \"\(query)\"\n"))

            let index = SearchIndex(notesDB: db)
            let (results, _, _) = try index.searchWithAutoRebuild(query: query, limit: limit)

            if results.isEmpty {
                print("No results found.")
            } else {
                for (noteId, snippet) in results {
                    // Try to get note metadata
                    if let note = try? db.listNotes(limit: 10000).first(where: { $0.id == noteId }) {
                        print(TerminalStyle.noteTitle(note.title))
                        if !snippet.isEmpty {
                            print("   \(snippet)")
                        }
                        print("   Folder: \(note.folder ?? "Notes")")
                        print("   ID: \(TerminalStyle.dim)\(noteId)\(TerminalStyle.reset)")
                        print("")
                    }
                }
                print("\(TerminalStyle.dim)Found \(results.count) result(s)\(TerminalStyle.reset)")
            }
        } else {
            // Basic search
            print(TerminalStyle.title("Searching for: \"\(query)\"\n"))

            let results = try db.searchNotes(
                query: query,
                limit: limit,
                searchContent: content,
                fuzzy: fuzzy,
                folder: folder
            )

            if results.isEmpty {
                print("No results found.")
                if !content && !fuzzy {
                    print(TerminalStyle.warning("Try --content to search bodies, or --fuzzy for typo tolerance"))
                }
            } else {
                for note in results {
                    print(TerminalStyle.noteTitle(note.title))
                    print("   Folder: \(note.folder ?? "Notes")")
                    if let modified = note.modifiedAt {
                        print("   Modified: \(formatDate(modified))")
                    }
                    print("   ID: \(TerminalStyle.dim)\(note.id)\(TerminalStyle.reset)")
                    print("")
                }
                print("\(TerminalStyle.dim)Found \(results.count) result(s)\(TerminalStyle.reset)")
            }
        }
    }
}

// MARK: - List Command

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List notes",
        discussion: "List notes from your Apple Notes. Optionally filter by folder."
    )

    @Option(name: .shortAndLong, help: "Filter by folder name")
    var folder: String?

    @Option(name: .shortAndLong, help: "Maximum number of notes to list")
    var limit: Int = 20

    func run() throws {
        guard Permissions.hasFullDiskAccess() else {
            printPermissionError()
            throw ExitCode.permissionDenied
        }

        let db = NotesDatabase()
        let notes = try db.listNotes(folder: folder, limit: limit)

        if let folder = folder {
            print(TerminalStyle.title("Notes in \"\(folder)\":\n"))
        } else {
            print(TerminalStyle.title("Recent notes:\n"))
        }

        if notes.isEmpty {
            print("No notes found.")
        } else {
            for note in notes {
                print(TerminalStyle.noteTitle(note.title))
                print("   Folder: \(note.folder ?? "Notes")")
                if let modified = note.modifiedAt {
                    print("   Modified: \(formatDate(modified))")
                }
                print("   ID: \(TerminalStyle.dim)\(note.id)\(TerminalStyle.reset)")
                print("")
            }
            print("\(TerminalStyle.dim)Showing \(notes.count) note(s)\(TerminalStyle.reset)")
        }
    }
}

// MARK: - Read Command

struct Read: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read a note's content",
        discussion: "Display the full content of a specific note by ID."
    )

    @Argument(help: "Note ID (UUID)")
    var id: String

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        guard Permissions.hasFullDiskAccess() else {
            printPermissionError()
            throw ExitCode.permissionDenied
        }

        let db = NotesDatabase()

        do {
            let note = try db.readNote(id: id)

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(note)
                if let jsonString = String(data: data, encoding: .utf8) {
                    print(jsonString)
                }
            } else {
                print(TerminalStyle.title(note.title))
                print("\(TerminalStyle.dim)────────────────────────────────────────\(TerminalStyle.reset)")
                print(note.content)
                print("\(TerminalStyle.dim)────────────────────────────────────────\(TerminalStyle.reset)")
                print("Folder: \(note.folder ?? "Notes")")
                if let created = note.createdAt {
                    print("Created: \(formatDate(created))")
                }
                if let modified = note.modifiedAt {
                    print("Modified: \(formatDate(modified))")
                }
                if !note.hashtags.isEmpty {
                    print("Hashtags: \(note.hashtags.joined(separator: " "))")
                }
                if !note.attachments.isEmpty {
                    print("Attachments: \(note.attachments.count)")
                }
                print("ID: \(note.id)")
            }
        } catch {
            print(TerminalStyle.error("Note not found: \(id)"))
            throw ExitCode.notFound
        }
    }
}

// MARK: - Folders Command

struct Folders: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all folders",
        discussion: "Display all available folders in Apple Notes."
    )

    func run() throws {
        guard Permissions.hasFullDiskAccess() else {
            printPermissionError()
            throw ExitCode.permissionDenied
        }

        let db = NotesDatabase()
        let folders = try db.listFolders()

        print(TerminalStyle.title("Folders:\n"))

        for folder in folders {
            print(TerminalStyle.folder(folder.name))
        }

        print("\n\(TerminalStyle.dim)Total: \(folders.count) folder(s)\(TerminalStyle.reset)")
    }
}

// MARK: - Helper Functions

func printPermissionError() {
    fputs(TerminalStyle.error("Full Disk Access required\n\n"), stderr)
    fputs("This tool needs Full Disk Access to read your Notes database.\n\n", stderr)
    fputs("To grant access:\n", stderr)
    fputs("1. Open System Settings > Privacy & Security > Full Disk Access\n", stderr)
    fputs("2. Click '+' and add this application\n", stderr)
    fputs("3. Restart the application\n\n", stderr)
    fputs("Or run: open 'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles'\n", stderr)
}

func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

// MARK: - ExitCode Conformance

extension ExitCode: Error {}

extension ExitCode: CustomStringConvertible {
    var description: String {
        switch self {
        case .success: return "Success"
        case .generalError: return "Error"
        case .permissionDenied: return "Permission denied"
        case .notFound: return "Not found"
        }
    }
}
