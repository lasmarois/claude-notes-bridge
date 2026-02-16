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
            Setup.self,
            Search.self,
            List.self,
            Read.self,
            Folders.self,
            Export.self,
            Import.self
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

// MARK: - Setup Command

struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Configure Claude Code integration",
        discussion: """
            Sets up the Apple Notes MCP server for Claude Code.

            This command will:
            1. Check Full Disk Access permissions
            2. Register the MCP server with Claude Code
            3. Verify the configuration

            Run this after installing via .pkg, or anytime you need to reconfigure.
            """
    )

    func run() throws {
        print(TerminalStyle.title("Claude Notes Bridge — Setup\n"))

        // Step 1: Check Full Disk Access
        print("Checking Full Disk Access...")
        let hasFDA = Permissions.hasFullDiskAccess()
        if hasFDA {
            print(TerminalStyle.success("Full Disk Access granted"))
        } else {
            print(TerminalStyle.warning("Full Disk Access not granted"))
            print("  The MCP server needs Full Disk Access to read your Notes database.")
            print("  Open: System Settings > Privacy & Security > Full Disk Access")
            print("  Or run: open 'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles'")
        }

        // Step 2: Find claude CLI
        print("\nLooking for Claude Code CLI...")
        guard let claudePath = findClaudeCLI() else {
            print(TerminalStyle.error("Claude Code CLI not found"))
            print("  Install Claude Code first: https://claude.ai/download")
            print("  Then re-run: claude-notes-bridge setup")
            throw ExitCode.notFound
        }
        print(TerminalStyle.success("Found: \(claudePath)"))

        // Step 3: Determine binary path for MCP config
        let installedPath = "/usr/local/bin/claude-notes-bridge"
        let servePath: String
        if FileManager.default.fileExists(atPath: installedPath) {
            servePath = installedPath
        } else {
            // Fall back to current executable location
            let currentExe = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
                .resolvingSymlinksInPath().path
            servePath = currentExe
        }

        // Step 4: Register MCP server
        print("\nRegistering MCP server...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["mcp", "add", "apple-notes", "--scope", "user", "--", servePath, "serve"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print(TerminalStyle.success("MCP server registered with Claude Code"))
        } else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print(TerminalStyle.error("Failed to register MCP server"))
            if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("  \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            print("\n  Manual setup:")
            print("  \(claudePath) mcp add apple-notes --scope user -- \(servePath) serve")
            throw ExitCode.generalError
        }

        // Step 5: Summary
        print("\n\(TerminalStyle.title("Setup complete!"))")
        print("  The \(TerminalStyle.cyan)apple-notes\(TerminalStyle.reset) MCP server is now available in Claude Code.")
        if !hasFDA {
            print("\n\(TerminalStyle.warning("Remember to grant Full Disk Access before using."))")
        }
    }

    private func findClaudeCLI() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/usr/local/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.claude/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/bin/claude",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fall back to `which`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let path = output, !path.isEmpty {
                return path
            }
        }

        return nil
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

// MARK: - Export Command

enum ExportFormat: String, ExpressibleByArgument, CaseIterable {
    case markdown = "md"
    case json = "json"
}

struct Export: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Export notes to Markdown or JSON",
        discussion: """
            Export notes to Markdown or JSON format.

            Single note:
              notes-bridge export <id>                    # Markdown to stdout
              notes-bridge export <id> --format json      # JSON to stdout
              notes-bridge export <id> -o note.md         # Markdown to file

            Batch export:
              notes-bridge export --folder "Work" -o ./backup/
              notes-bridge export --all -o ./backup/
              notes-bridge export --all -o ./backup/ --no-attachments
            """
    )

    // Single note export
    @Argument(help: "Note ID (UUID) for single note export")
    var id: String?

    // Batch export options
    @Option(name: .long, help: "Export all notes in a folder")
    var folder: String?

    @Flag(name: .long, help: "Export all notes")
    var all: Bool = false

    // Output options
    @Option(name: .shortAndLong, help: "Output format: md (default) or json")
    var format: ExportFormat = .markdown

    @Option(name: .shortAndLong, help: "Output path (file for single, directory for batch)")
    var output: String?

    // Markdown options
    @Flag(name: .long, help: "Exclude YAML frontmatter from Markdown output")
    var noFrontmatter: Bool = false

    // JSON options
    @Flag(name: .long, help: "Include HTML content in JSON output")
    var includeHtml: Bool = false

    @Flag(name: .long, help: "Include all metadata (attachments, hashtags, links) in JSON")
    var full: Bool = false

    // Batch options
    @Flag(name: .long, help: "Skip attachment copying in batch export")
    var noAttachments: Bool = false

    func validate() throws {
        // Must specify exactly one of: id, --folder, or --all
        let modes = [id != nil, folder != nil, all].filter { $0 }.count
        if modes == 0 {
            throw ValidationError("Must specify a note ID, --folder, or --all")
        }
        if modes > 1 {
            throw ValidationError("Cannot combine note ID with --folder or --all")
        }

        // Batch export requires output directory
        if (folder != nil || all) && output == nil {
            throw ValidationError("Batch export requires -o/--output directory")
        }
    }

    func run() throws {
        guard Permissions.hasFullDiskAccess() else {
            printPermissionError()
            throw ExitCode.permissionDenied
        }

        let db = NotesDatabase()
        let exporter = NotesExporter(database: db)

        // Build export options
        let options = ExportOptions(
            includeFrontmatter: !noFrontmatter,
            includeHTML: includeHtml,
            fullMetadata: full,
            includeAttachments: !noAttachments
        )

        // Get formatter
        let formatter: NoteFormatter = format == .json ? JSONFormatter() : MarkdownFormatter()

        do {
            if let noteId = id {
                // Single note export
                try exportSingleNote(noteId, exporter: exporter, formatter: formatter, options: options)
            } else if let folderName = folder {
                // Folder export
                try exportFolder(folderName, exporter: exporter, formatter: formatter, options: options)
            } else if all {
                // Export all
                try exportAllNotes(exporter: exporter, formatter: formatter, options: options)
            }
        } catch {
            print(TerminalStyle.error("Export failed: \(error.localizedDescription)"))
            throw ExitCode.generalError
        }
    }

    private func exportSingleNote(
        _ noteId: String,
        exporter: NotesExporter,
        formatter: NoteFormatter,
        options: ExportOptions
    ) throws {
        let content: String

        if format == .markdown {
            content = try exporter.exportNoteStyled(id: noteId, options: options)
        } else {
            content = try exporter.exportNote(id: noteId, formatter: formatter, options: options)
        }

        // Output to file or stdout
        if let outputPath = output {
            let url = URL(fileURLWithPath: outputPath)
            try content.write(to: url, atomically: true, encoding: .utf8)
            print(TerminalStyle.success("Exported to \(outputPath)"))
        } else {
            print(content)
        }
    }

    private func exportFolder(
        _ folderName: String,
        exporter: NotesExporter,
        formatter: NoteFormatter,
        options: ExportOptions
    ) throws {
        let outputDir = URL(fileURLWithPath: output!)

        print(TerminalStyle.title("Exporting folder: \(folderName)\n"))

        let result = try exporter.exportFolder(
            folderName: folderName,
            outputDirectory: outputDir,
            formatter: formatter,
            options: options
        ) { current, total in
            print("\r\(TerminalStyle.dim)Progress: \(current)/\(total)\(TerminalStyle.reset)", terminator: "")
            fflush(stdout)
        }

        print("\n")
        printExportResult(result, outputDir: outputDir)
    }

    private func exportAllNotes(
        exporter: NotesExporter,
        formatter: NoteFormatter,
        options: ExportOptions
    ) throws {
        let outputDir = URL(fileURLWithPath: output!)

        print(TerminalStyle.title("Exporting all notes\n"))

        let result = try exporter.exportAll(
            outputDirectory: outputDir,
            formatter: formatter,
            options: options
        ) { current, total in
            print("\r\(TerminalStyle.dim)Progress: \(current)/\(total)\(TerminalStyle.reset)", terminator: "")
            fflush(stdout)
        }

        print("\n")
        printExportResult(result, outputDir: outputDir)
    }

    private func printExportResult(_ result: ExportResult, outputDir: URL) {
        print(TerminalStyle.success("Exported \(result.successCount) note(s) to \(outputDir.path)"))

        if !result.exportedAttachments.isEmpty {
            print(TerminalStyle.success("Copied \(result.exportedAttachments.count) attachment(s)"))
        }

        if !result.failures.isEmpty {
            print(TerminalStyle.warning("\(result.failures.count) note(s) failed:"))
            for failure in result.failures.prefix(5) {
                print("  - \(failure.title): \(failure.error)")
            }
            if result.failures.count > 5 {
                print("  ... and \(result.failures.count - 5) more")
            }
        }
    }
}

// MARK: - Import Command

struct Import: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Import notes from Markdown files",
        discussion: """
            Import Markdown files into Apple Notes.

            Single file:
              notes-bridge import note.md
              notes-bridge import note.md --folder "Work"

            Batch import:
              notes-bridge import --dir ./notes/
              notes-bridge import --dir ./notes/ --folder "Imported"
              notes-bridge import --dir ./notes/ --on-conflict skip

            Frontmatter:
              Files can include YAML frontmatter with title, folder, and tags.
            """
    )

    // Single file import
    @Argument(help: "Markdown file to import")
    var file: String?

    // Batch import
    @Option(name: .long, help: "Import all markdown files from directory")
    var dir: String?

    // Options
    @Option(name: .long, help: "Target folder (overrides frontmatter)")
    var folder: String?

    @Option(name: .long, help: "Conflict handling: skip, replace, duplicate, ask (default)")
    var onConflict: String = "ask"

    @Flag(name: .long, help: "Preview import without creating notes")
    var dryRun: Bool = false

    func validate() throws {
        // Must specify either file or --dir
        if file == nil && dir == nil {
            throw ValidationError("Must specify a file or --dir")
        }
        if file != nil && dir != nil {
            throw ValidationError("Cannot specify both file and --dir")
        }

        // Validate conflict strategy
        let validStrategies = ["skip", "replace", "duplicate", "ask"]
        if !validStrategies.contains(onConflict) {
            throw ValidationError("Invalid --on-conflict value. Use: \(validStrategies.joined(separator: ", "))")
        }
    }

    func run() throws {
        guard Permissions.hasFullDiskAccess() else {
            printPermissionError()
            throw ExitCode.permissionDenied
        }

        let db = NotesDatabase()
        let importer = NotesImporter(database: db)

        // Parse conflict strategy
        let strategy: ConflictStrategy
        switch onConflict {
        case "skip": strategy = .skip
        case "replace": strategy = .replace
        case "duplicate": strategy = .duplicate
        default: strategy = .ask
        }

        let options = ImportOptions(
            targetFolder: folder,
            conflictStrategy: strategy,
            dryRun: dryRun
        )

        do {
            if let filePath = file {
                try importSingleFile(filePath, importer: importer, options: options)
            } else if let dirPath = dir {
                try importDirectory(dirPath, importer: importer, options: options)
            }
        } catch {
            print(TerminalStyle.error("Import failed: \(error.localizedDescription)"))
            throw ExitCode.generalError
        }
    }

    private func importSingleFile(
        _ path: String,
        importer: NotesImporter,
        options: ImportOptions
    ) throws {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            print(TerminalStyle.error("File not found: \(path)"))
            throw ExitCode.notFound
        }

        if dryRun {
            print(TerminalStyle.title("Dry run - previewing import\n"))
        }

        let result = try importer.importFile(url, options: options) { conflict in
            return handleConflictInteractively(conflict)
        }

        printImportResult(result, dryRun: dryRun)
    }

    private func importDirectory(
        _ path: String,
        importer: NotesImporter,
        options: ImportOptions
    ) throws {
        let url = URL(fileURLWithPath: path)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            print(TerminalStyle.error("Directory not found: \(path)"))
            throw ExitCode.notFound
        }

        if dryRun {
            print(TerminalStyle.title("Dry run - previewing import from: \(path)\n"))
        } else {
            print(TerminalStyle.title("Importing from: \(path)\n"))
        }

        let result = try importer.importDirectory(
            url,
            options: options,
            recursive: true,
            conflictHandler: { conflict in
                return handleConflictInteractively(conflict)
            }
        ) { current, total in
            print("\r\(TerminalStyle.dim)Progress: \(current)/\(total)\(TerminalStyle.reset)", terminator: "")
            fflush(stdout)
        }

        print("\n")
        printImportResult(result, dryRun: dryRun)
    }

    private func handleConflictInteractively(_ conflict: ImportConflict) -> ConflictStrategy {
        print("\n\(TerminalStyle.warning("Conflict detected:"))")
        print("  Title: \(conflict.importTitle)")
        print("  Folder: \(conflict.importFolder ?? "Notes")")
        print("  Existing note ID: \(conflict.existingNote.id)")
        print("")
        print("Options: [s]kip, [r]eplace, [d]uplicate, [S]kip all, [R]eplace all")
        print("Choice: ", terminator: "")
        fflush(stdout)

        guard let input = readLine()?.trimmingCharacters(in: .whitespaces) else {
            return .skip
        }

        switch input.lowercased() {
        case "s", "skip": return .skip
        case "r", "replace": return .replace
        case "d", "duplicate": return .duplicate
        default: return .skip
        }
    }

    private func printImportResult(_ result: ImportResult, dryRun: Bool) {
        let verb = dryRun ? "Would import" : "Imported"

        if result.importedCount > 0 {
            print(TerminalStyle.success("\(verb) \(result.importedCount) note(s)"))
            if result.importedCount <= 5 {
                for note in result.imported {
                    print("  - \(note.title) → \(note.folder ?? "Notes")")
                }
            }
        }

        if result.skippedCount > 0 {
            print(TerminalStyle.warning("Skipped \(result.skippedCount) note(s)"))
            for skipped in result.skipped.prefix(3) {
                print("  - \(skipped.title): \(skipped.reason)")
            }
            if result.skippedCount > 3 {
                print("  ... and \(result.skippedCount - 3) more")
            }
        }

        if result.conflictCount > 0 {
            print(TerminalStyle.warning("\(result.conflictCount) conflict(s) need resolution"))
        }

        if result.failureCount > 0 {
            print(TerminalStyle.error("\(result.failureCount) failure(s)"))
            for failure in result.failures.prefix(5) {
                let title = failure.title ?? failure.sourceFile.lastPathComponent
                print("  - \(title): \(failure.error)")
            }
            if result.failureCount > 5 {
                print("  ... and \(result.failureCount - 5) more")
            }
        }

        if result.importedCount == 0 && result.skippedCount == 0 &&
           result.conflictCount == 0 && result.failureCount == 0 {
            print("No markdown files found to import.")
        }
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
