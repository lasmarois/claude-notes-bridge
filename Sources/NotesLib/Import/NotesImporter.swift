import Foundation

/// Strategy for handling import conflicts
public enum ConflictStrategy: String, CaseIterable {
    case skip       // Skip the note, keep existing
    case replace    // Delete existing and import new
    case duplicate  // Import as new note (may create duplicate title)
    case ask        // Ask user for each conflict (handled by caller)
}

/// Information about a detected conflict
public struct ImportConflict {
    public let importTitle: String
    public let importFolder: String?
    public let existingNote: Note
}

/// Result of an import operation
public struct ImportResult {
    public var imported: [ImportedNote] = []
    public var skipped: [SkippedNote] = []
    public var conflicts: [ImportConflict] = []
    public var failures: [ImportFailure] = []

    public var importedCount: Int { imported.count }
    public var skippedCount: Int { skipped.count }
    public var conflictCount: Int { conflicts.count }
    public var failureCount: Int { failures.count }
}

/// Information about a successfully imported note
public struct ImportedNote {
    public let sourceFile: URL
    public let noteId: String
    public let title: String
    public let folder: String?
}

/// Information about a skipped note
public struct SkippedNote {
    public let sourceFile: URL
    public let title: String
    public let reason: String
}

/// Information about a failed import
public struct ImportFailure {
    public let sourceFile: URL
    public let title: String?
    public let error: String
}

/// Options for import operations
public struct ImportOptions {
    /// Target folder for imported notes (overrides frontmatter)
    public var targetFolder: String?

    /// Conflict handling strategy
    public var conflictStrategy: ConflictStrategy

    /// Dry run - detect conflicts without importing
    public var dryRun: Bool

    public init(
        targetFolder: String? = nil,
        conflictStrategy: ConflictStrategy = .ask,
        dryRun: Bool = false
    ) {
        self.targetFolder = targetFolder
        self.conflictStrategy = conflictStrategy
        self.dryRun = dryRun
    }
}

/// Handles importing notes from markdown files
public class NotesImporter {
    private let database: NotesDatabase
    private let appleScript: NotesAppleScript
    private let frontmatterParser: FrontmatterParser
    private let markdownConverter: MarkdownConverter

    public init(database: NotesDatabase) {
        self.database = database
        self.appleScript = NotesAppleScript()
        self.frontmatterParser = FrontmatterParser()
        self.markdownConverter = MarkdownConverter()
    }

    // MARK: - Single File Import

    /// Import a single markdown file
    /// - Parameters:
    ///   - fileURL: Path to the markdown file
    ///   - options: Import options
    ///   - conflictHandler: Called when conflict detected and strategy is .ask
    /// - Returns: Import result
    public func importFile(
        _ fileURL: URL,
        options: ImportOptions = ImportOptions(),
        conflictHandler: ((ImportConflict) -> ConflictStrategy)? = nil
    ) throws -> ImportResult {
        var result = ImportResult()

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let filename = fileURL.lastPathComponent
            let parsed = frontmatterParser.parse(content, filename: filename)

            let title = parsed.resolvedTitle
            let folder = options.targetFolder ?? parsed.frontmatter.folder

            // Check for conflicts
            if let conflict = detectConflict(title: title, folder: folder) {
                let strategy: ConflictStrategy
                if options.conflictStrategy == .ask {
                    if let handler = conflictHandler {
                        strategy = handler(conflict)
                    } else {
                        // No handler, return conflict for caller to handle
                        result.conflicts.append(conflict)
                        return result
                    }
                } else {
                    strategy = options.conflictStrategy
                }

                switch strategy {
                case .skip:
                    result.skipped.append(SkippedNote(
                        sourceFile: fileURL,
                        title: title,
                        reason: "Conflict with existing note"
                    ))
                    return result

                case .replace:
                    // Delete existing note first
                    try appleScript.deleteNote(id: conflict.existingNote.id)

                case .duplicate, .ask:
                    // Continue with import (creates duplicate)
                    break
                }
            }

            // Dry run - don't actually import
            if options.dryRun {
                result.imported.append(ImportedNote(
                    sourceFile: fileURL,
                    noteId: "dry-run",
                    title: title,
                    folder: folder
                ))
                return result
            }

            // Convert markdown to HTML
            let htmlBody = convertToNoteBody(parsed)

            // Create the note (body is already HTML from convertToNoteBody)
            let noteResult = try appleScript.createNote(
                title: title,
                body: htmlBody,
                folder: folder,
                isHTML: true
            )

            result.imported.append(ImportedNote(
                sourceFile: fileURL,
                noteId: noteResult.uuid,
                title: title,
                folder: folder
            ))

        } catch {
            result.failures.append(ImportFailure(
                sourceFile: fileURL,
                title: nil,
                error: error.localizedDescription
            ))
        }

        return result
    }

    // MARK: - Batch Import

    /// Import all markdown files from a directory
    /// - Parameters:
    ///   - directoryURL: Directory containing markdown files
    ///   - options: Import options
    ///   - recursive: Include subdirectories
    ///   - conflictHandler: Called for each conflict when strategy is .ask
    ///   - progress: Progress callback (current, total)
    /// - Returns: Combined import result
    public func importDirectory(
        _ directoryURL: URL,
        options: ImportOptions = ImportOptions(),
        recursive: Bool = true,
        conflictHandler: ((ImportConflict) -> ConflictStrategy)? = nil,
        progress: ((Int, Int) -> Void)? = nil
    ) throws -> ImportResult {
        var result = ImportResult()

        // Find all markdown files
        let files = try findMarkdownFiles(in: directoryURL, recursive: recursive)
        let total = files.count

        for (index, fileURL) in files.enumerated() {
            let fileResult = try importFile(
                fileURL,
                options: adjustOptionsForFile(options, file: fileURL, baseDir: directoryURL),
                conflictHandler: conflictHandler
            )

            // Merge results
            result.imported.append(contentsOf: fileResult.imported)
            result.skipped.append(contentsOf: fileResult.skipped)
            result.conflicts.append(contentsOf: fileResult.conflicts)
            result.failures.append(contentsOf: fileResult.failures)

            progress?(index + 1, total)
        }

        return result
    }

    // MARK: - Conflict Detection

    /// Check if a note with the same title exists in the target folder
    public func detectConflict(title: String, folder: String?) -> ImportConflict? {
        do {
            // Search for notes with matching title
            let notes = try database.searchNotes(
                query: title,
                limit: 100,
                searchContent: false,
                fuzzy: false,
                folder: folder
            )

            // Find exact title match
            for note in notes {
                if note.title.lowercased() == title.lowercased() {
                    // Also check folder matches
                    let noteFolder = note.folder
                    let targetFolder = folder

                    if noteFolder == targetFolder ||
                       (noteFolder == nil && targetFolder == "Notes") ||
                       (noteFolder == "Notes" && targetFolder == nil) {
                        return ImportConflict(
                            importTitle: title,
                            importFolder: folder,
                            existingNote: note
                        )
                    }
                }
            }
        } catch {
            // If search fails, assume no conflict
        }

        return nil
    }

    // MARK: - Private Methods

    private func convertToNoteBody(_ parsed: ParsedMarkdown) -> String {
        var markdown = parsed.content

        // Remove title heading if it matches the resolved title
        // (AppleScript.createNote adds the title)
        let lines = markdown.components(separatedBy: "\n")
        var startIndex = 0

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }
            if trimmed.hasPrefix("# ") {
                let headingTitle = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if headingTitle.lowercased() == parsed.resolvedTitle.lowercased() {
                    startIndex = index + 1
                    // Skip following blank lines
                    while startIndex < lines.count &&
                          lines[startIndex].trimmingCharacters(in: .whitespaces).isEmpty {
                        startIndex += 1
                    }
                }
            }
            break
        }

        if startIndex > 0 {
            markdown = lines[startIndex...].joined(separator: "\n")
        }

        // Convert markdown to HTML
        return markdownConverter.convert(markdown)
    }

    private func findMarkdownFiles(in directory: URL, recursive: Bool) throws -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []

        let contents: [URL]
        if recursive {
            guard let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            contents = enumerator.compactMap { $0 as? URL }
        } else {
            contents = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        }

        for url in contents {
            let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues?.isRegularFile == true {
                let ext = url.pathExtension.lowercased()
                if ext == "md" || ext == "markdown" {
                    files.append(url)
                }
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    private func adjustOptionsForFile(
        _ options: ImportOptions,
        file: URL,
        baseDir: URL
    ) -> ImportOptions {
        var adjusted = options

        // If no target folder specified, derive from directory structure
        if adjusted.targetFolder == nil {
            let relativePath = file.deletingLastPathComponent().path
                .replacingOccurrences(of: baseDir.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            if !relativePath.isEmpty {
                // Use directory structure as folder path
                adjusted.targetFolder = relativePath
            }
        }

        return adjusted
    }
}

/// Errors that can occur during import
public enum ImportError: Error, LocalizedError {
    case fileNotFound(String)
    case invalidContent(String)
    case conflictDetected(String)
    case createFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .invalidContent(let message):
            return "Invalid content: \(message)"
        case .conflictDetected(let title):
            return "Conflict detected: \(title)"
        case .createFailed(let message):
            return "Failed to create note: \(message)"
        }
    }
}
