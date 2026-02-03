import Foundation

/// AppleScript helper for Notes.app operations
/// Uses osascript for reliable CloudKit-compatible writes
class NotesAppleScript {

    /// Result of an AppleScript operation
    struct NoteResult {
        let id: String      // x-coredata://...ICNote/p123 format
        let uuid: String    // Extracted UUID for DB correlation
    }

    // MARK: - Create

    /// Create a new note via AppleScript
    /// - Parameters:
    ///   - title: The note title
    ///   - body: The note body (plain text or HTML depending on isHTML flag)
    ///   - folder: Optional folder name (defaults to "Notes")
    ///   - account: Optional account name (defaults to default account)
    ///   - isHTML: If true, body is already HTML and won't be processed
    /// - Returns: NoteResult with the created note's ID
    func createNote(title: String, body: String, folder: String? = nil, account: String? = nil, isHTML: Bool = false) throws -> NoteResult {
        let folderName = folder ?? "Notes"
        let escapedFolder = escapeForAppleScript(folderName)

        // Build HTML body with styled title - Notes derives title from first line
        let styledTitle = "<b><span style=\"font-size: 24px\">\(escapeHTMLOnly(title))</span></b>"
        let processedBody = isHTML ? body : processBody(body)
        let htmlBody = "<div>\(styledTitle)</div><div><br></div><div>\(processedBody)</div>"
        let escapedHtmlBody = escapeForAppleScript(htmlBody)

        let script: String
        if let account = account {
            let escapedAccount = escapeForAppleScript(account)
            script = """
            tell application "Notes"
                tell account "\(escapedAccount)"
                    set newNote to make new note at folder "\(escapedFolder)" with properties {body:"\(escapedHtmlBody)"}
                    return id of newNote
                end tell
            end tell
            """
        } else {
            script = """
            tell application "Notes"
                set newNote to make new note at folder "\(escapedFolder)" with properties {body:"\(escapedHtmlBody)"}
                return id of newNote
            end tell
            """
        }

        let output = try runAppleScript(script)
        return try parseNoteId(output)
    }

    /// Create multiple notes in a single AppleScript call (batched for performance)
    func createNotes(_ notes: [(title: String, body: String, folder: String?)]) throws -> [NoteResult] {
        guard !notes.isEmpty else { return [] }

        var scriptParts: [String] = ["tell application \"Notes\""]
        var resultVars: [String] = []

        for (index, note) in notes.enumerated() {
            let varName = "note\(index)"
            let folder = note.folder ?? "Notes"
            let styledTitle = "<b><span style=\"font-size: 24px\">\(escapeHTMLOnly(note.title))</span></b>"
            let htmlBody = "<div>\(styledTitle)</div><div><br></div><div>\(processBody(note.body))</div>"

            scriptParts.append("""
                set \(varName) to make new note at folder "\(escapeForAppleScript(folder))" with properties {body:"\(escapeForAppleScript(htmlBody))"}
            """)
            resultVars.append("id of \(varName)")
        }

        scriptParts.append("return {\(resultVars.joined(separator: ", "))}")
        scriptParts.append("end tell")

        let script = scriptParts.joined(separator: "\n")
        let output = try runAppleScript(script)

        // Parse comma-separated IDs
        let ids = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        return try ids.map { try parseNoteId($0) }
    }

    // MARK: - Update

    /// Update an existing note's content
    /// - Parameters:
    ///   - id: The note ID (either x-coredata URL or UUID)
    ///   - title: Optional new title
    ///   - body: Optional new body
    func updateNote(id: String, title: String? = nil, body: String? = nil) throws {
        let noteId = try resolveNoteId(id)

        guard title != nil || body != nil else {
            throw NotesError.missingParameter("title or body")
        }

        // Notes.app quirk: setting body replaces everything including title
        // So we include styled title in body for consistency
        let script: String

        if let title = title, let body = body {
            // Both title and body provided - include styled title in body
            let styledTitle = "<b><span style=\"font-size: 24px\">\(escapeHTMLOnly(title))</span></b>"
            let htmlBody = "<div>\(styledTitle)</div><div><br></div><div>\(processBody(body))</div>"
            script = """
            tell application "Notes"
                set theNote to note id "\(noteId)"
                set body of theNote to "\(escapeForAppleScript(htmlBody))"
            end tell
            """
        } else if let title = title {
            // Only title - get current body and rebuild with new styled title
            script = """
            tell application "Notes"
                set theNote to note id "\(noteId)"
                set currentBody to body of theNote
                set name of theNote to "\(escapeForAppleScript(title))"
            end tell
            """
        } else if let body = body {
            // Only body - get current title and include it styled
            let htmlBody = processBody(body)
            script = """
            tell application "Notes"
                set theNote to note id "\(noteId)"
                set currentTitle to name of theNote
                set styledTitle to "<b><span style=\\"font-size: 24px\\">" & currentTitle & "</span></b>"
                set newBody to "<div>" & styledTitle & "</div><div><br></div><div>\(escapeForAppleScript(htmlBody))</div>"
                set body of theNote to newBody
            end tell
            """
        } else {
            throw NotesError.missingParameter("title or body")
        }

        _ = try runAppleScript(script)
    }

    // MARK: - Delete

    /// Delete a note
    /// - Parameter id: The note ID (either x-coredata URL or UUID)
    func deleteNote(id: String) throws {
        let noteId = try resolveNoteId(id)

        let script = """
        tell application "Notes"
            delete note id "\(noteId)"
        end tell
        """

        _ = try runAppleScript(script)
    }

    // MARK: - Folder Operations

    /// Create a new folder
    /// - Parameters:
    ///   - name: The folder name
    ///   - parentFolder: Optional parent folder name for nested folders
    /// - Returns: The created folder's name
    func createFolder(name: String, parentFolder: String? = nil) throws -> String {
        let script: String

        if let parent = parentFolder {
            script = """
            tell application "Notes"
                tell folder "\(escapeForAppleScript(parent))"
                    make new folder with properties {name:"\(escapeForAppleScript(name))"}
                end tell
                return "\(escapeForAppleScript(name))"
            end tell
            """
        } else {
            script = """
            tell application "Notes"
                make new folder with properties {name:"\(escapeForAppleScript(name))"}
                return "\(escapeForAppleScript(name))"
            end tell
            """
        }

        let output = try runAppleScript(script)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Move a note to a different folder
    /// - Parameters:
    ///   - noteId: The note ID (x-coredata URL or UUID)
    ///   - folderName: The target folder name
    func moveNote(noteId: String, toFolder folderName: String) throws {
        let resolvedId = try resolveNoteId(noteId)

        let script = """
        tell application "Notes"
            set theNote to note id "\(resolvedId)"
            set targetFolder to folder "\(escapeForAppleScript(folderName))"
            move theNote to targetFolder
        end tell
        """

        _ = try runAppleScript(script)
    }

    /// Rename a folder
    /// - Parameters:
    ///   - oldName: Current folder name
    ///   - newName: New folder name
    func renameFolder(from oldName: String, to newName: String) throws {
        let script = """
        tell application "Notes"
            set theFolder to folder "\(escapeForAppleScript(oldName))"
            set name of theFolder to "\(escapeForAppleScript(newName))"
        end tell
        """

        _ = try runAppleScript(script)
    }

    /// Delete a folder (notes will be moved to Recently Deleted)
    /// - Parameter name: The folder name to delete
    func deleteFolder(name: String) throws {
        let script = """
        tell application "Notes"
            delete folder "\(escapeForAppleScript(name))"
        end tell
        """

        _ = try runAppleScript(script)
    }

    // MARK: - Read Operations

    /// Get a note's HTML body via AppleScript
    /// - Parameter id: The note ID (x-coredata URL or UUID)
    /// - Returns: HTML content of the note
    func getNoteBody(id: String) throws -> String {
        let resolvedId = try resolveNoteId(id)

        let script = """
        tell application "Notes"
            set theNote to note id "\(resolvedId)"
            return body of theNote
        end tell
        """

        let output = try runAppleScript(script)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Attachment Operations

    /// Get the file path for an attachment
    /// - Parameter id: The attachment ID (x-coredata URL)
    /// - Returns: POSIX file path to the attachment
    func getAttachmentPath(id: String) throws -> String {
        // Note: We need to get 'contents' from the properties record because
        // 'contents of attachment' returns the attachment reference, not the file path
        let script = """
        tell application "Notes"
            set att to attachment id "\(escapeForAppleScript(id))"
            set props to properties of att
            set filePath to contents of props
            return POSIX path of filePath
        end tell
        """

        let output = try runAppleScript(script)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Add an attachment to an existing note
    /// - Parameters:
    ///   - noteId: The note ID (x-coredata URL or UUID)
    ///   - filePath: POSIX path to the file to attach
    /// - Returns: The created attachment's ID
    func addAttachment(noteId: String, filePath: String) throws -> String {
        let resolvedNoteId = try resolveNoteId(noteId)

        let script = """
        tell application "Notes"
            set theNote to note id "\(resolvedNoteId)"
            set newAtt to make new attachment at end of attachments of theNote with data (POSIX file "\(escapeForAppleScript(filePath))")
            return id of newAtt
        end tell
        """

        let output = try runAppleScript(script)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Query Helpers

    /// Find a note's x-coredata ID by UUID (searches via AppleScript)
    func findNoteByUUID(_ uuid: String) throws -> String? {
        let script = """
        tell application "Notes"
            repeat with n in notes
                if id of n contains "\(escapeForAppleScript(uuid))" then
                    return id of n
                end if
            end repeat
            return ""
        end tell
        """

        let output = try runAppleScript(script)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Get list of folder names
    func listFolders(account: String? = nil) throws -> [String] {
        let script: String
        if let account = account {
            script = """
            tell application "Notes"
                tell account "\(escapeForAppleScript(account))"
                    return name of folders
                end tell
            end tell
            """
        } else {
            script = """
            tell application "Notes"
                return name of folders
            end tell
            """
        }

        let output = try runAppleScript(script)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Private Helpers

    private func runAppleScript(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown AppleScript error"
            throw NotesError.appleScriptError(errorMessage.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }

    private func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// Convert markdown to HTML
    /// Handles: code blocks, inline code, bold, italic, strikethrough, headers, lists
    private func processMarkdown(_ string: String) -> String {
        var result = string

        // 1. First, handle fenced code blocks: ```lang\ncode\n```
        let codeBlockPattern = "```(?:\\w*)?\\n([\\s\\S]*?)```"
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)

            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let codeRange = Range(match.range(at: 1), in: result) else {
                    continue
                }

                let code = String(result[codeRange])
                let escapedCode = code
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                    .replacingOccurrences(of: "\n", with: "<br>")

                // Use placeholder to protect from further processing
                let replacement = "⟦CODEBLOCK⟧\(escapedCode)⟦/CODEBLOCK⟧"
                result.replaceSubrange(fullRange, with: replacement)
            }
        }

        // 2. Handle inline code: `code`
        let inlinePattern = "`([^`]+)`"
        if let regex = try? NSRegularExpression(pattern: inlinePattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)

            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let codeRange = Range(match.range(at: 1), in: result) else {
                    continue
                }

                let code = String(result[codeRange])
                let escapedCode = code
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")

                let replacement = "⟦CODE⟧\(escapedCode)⟦/CODE⟧"
                result.replaceSubrange(fullRange, with: replacement)
            }
        }

        // 3. Now escape HTML in the rest of the text
        // Split by our placeholders, escape non-code parts
        var escaped = ""
        var remaining = result

        while !remaining.isEmpty {
            // Find the earliest placeholder
            let codeBlockRange = remaining.range(of: "⟦CODEBLOCK⟧")
            let codeRange = remaining.range(of: "⟦CODE⟧")

            // Determine which comes first
            let nextPlaceholder: (range: Range<String.Index>, isBlock: Bool)?
            if let cbr = codeBlockRange, let cr = codeRange {
                nextPlaceholder = cbr.lowerBound < cr.lowerBound ? (cbr, true) : (cr, false)
            } else if let cbr = codeBlockRange {
                nextPlaceholder = (cbr, true)
            } else if let cr = codeRange {
                nextPlaceholder = (cr, false)
            } else {
                nextPlaceholder = nil
            }

            guard let (startRange, isBlock) = nextPlaceholder else {
                // No more placeholders, escape the rest
                escaped += escapeHTMLOnly(remaining)
                break
            }

            // Escape text before the placeholder
            let before = String(remaining[..<startRange.lowerBound])
            escaped += escapeHTMLOnly(before)

            let afterStart = String(remaining[startRange.upperBound...])
            let endTag = isBlock ? "⟦/CODEBLOCK⟧" : "⟦/CODE⟧"

            if let endRange = afterStart.range(of: endTag) {
                let codeContent = String(afterStart[..<endRange.lowerBound])
                // Use Menlo font with a code-like color (dark red/maroon for inline, just Menlo for blocks)
                let fontTag = isBlock ? "<font face=\"Menlo\">" : "<font face=\"Menlo\" color=\"#c7254e\">"
                escaped += "\(fontTag)\(codeContent)</font>"
                remaining = String(afterStart[endRange.upperBound...])
            } else {
                // No closing tag found, escape the rest
                escaped += escapeHTMLOnly(remaining)
                break
            }
        }

        result = escaped

        // 4. Process markdown formatting (on escaped text, avoiding code blocks)
        // Bold: **text** or __text__
        result = applyPattern(result, pattern: "\\*\\*(.+?)\\*\\*", replacement: "<b>$1</b>")
        result = applyPattern(result, pattern: "__(.+?)__", replacement: "<b>$1</b>")

        // Italic: *text* or _text_ (but not inside words for underscore)
        result = applyPattern(result, pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", replacement: "<i>$1</i>")
        result = applyPattern(result, pattern: "(?<![\\w])_(?!_)(.+?)(?<!_)_(?![\\w])", replacement: "<i>$1</i>")

        // Strikethrough: ~~text~~
        result = applyPattern(result, pattern: "~~(.+?)~~", replacement: "<strike>$1</strike>")

        // 5. Handle line-based markdown (headers, lists)
        // Process line by line
        var lines = result.components(separatedBy: "\n")
        for i in 0..<lines.count {
            var line = lines[i]

            // Headers: # ## ###
            if line.hasPrefix("### ") {
                line = "<b>\(String(line.dropFirst(4)))</b>"
            } else if line.hasPrefix("## ") {
                line = "<h2>\(String(line.dropFirst(3)))</h2>"
            } else if line.hasPrefix("# ") {
                line = "<h1>\(String(line.dropFirst(2)))</h1>"
            }
            // Blockquotes: > text
            else if line.hasPrefix("&gt; ") {
                // > was escaped to &gt;, style as quote with left border effect using color
                line = "<font color=\"#666666\">▎ \(String(line.dropFirst(5)))</font>"
            } else if line.hasPrefix("&gt;") && line.count > 4 {
                line = "<font color=\"#666666\">▎ \(String(line.dropFirst(4)))</font>"
            }
            // Unordered lists: - or *
            else if line.hasPrefix("- ") {
                line = "• \(String(line.dropFirst(2)))"
            } else if line.hasPrefix("* ") {
                line = "• \(String(line.dropFirst(2)))"
            }
            // Ordered lists: 1. 2. etc (keep as-is, just ensure formatting)

            lines[i] = line
        }

        result = lines.joined(separator: "<br>")

        return result
    }

    /// Apply regex pattern and replacement
    private func applyPattern(_ string: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return string
        }

        let range = NSRange(string.startIndex..., in: string)
        return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: replacement)
    }

    /// Escape HTML special characters only (no newline conversion)
    private func escapeHTMLOnly(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Process body text with full markdown conversion
    private func processBody(_ string: String) -> String {
        let converter = MarkdownConverter()
        return converter.convert(string)
    }

    private func parseNoteId(_ output: String) throws -> NoteResult {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Format: x-coredata://E80D5A9D-1939-4C46-B3D4-E0EF27C98CE8/ICNote/p6448
        guard trimmed.hasPrefix("x-coredata://") else {
            throw NotesError.appleScriptError("Invalid note ID format: \(trimmed)")
        }

        // Extract UUID from the path (the one between :// and /ICNote)
        // x-coredata://UUID/ICNote/pN
        let components = trimmed.components(separatedBy: "/")
        guard components.count >= 4 else {
            throw NotesError.appleScriptError("Cannot parse note ID: \(trimmed)")
        }

        // The UUID is in components[2] (after x-coredata:)
        let dbUUID = components[2]

        return NoteResult(id: trimmed, uuid: dbUUID)
    }

    /// Resolve a note ID - if it's already x-coredata format, use it; otherwise search by UUID
    private func resolveNoteId(_ id: String) throws -> String {
        if id.hasPrefix("x-coredata://") {
            return id
        }

        // Assume it's a UUID, try to find the note
        guard let fullId = try findNoteByUUID(id) else {
            throw NotesError.noteNotFound(id)
        }

        return fullId
    }
}
