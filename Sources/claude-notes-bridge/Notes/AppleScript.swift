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
    ///   - body: The note body (plain text, will be wrapped in HTML)
    ///   - folder: Optional folder name (defaults to "Notes")
    ///   - account: Optional account name (defaults to default account)
    /// - Returns: NoteResult with the created note's ID
    func createNote(title: String, body: String, folder: String? = nil, account: String? = nil) throws -> NoteResult {
        let escapedTitle = escapeForAppleScript(title)
        let escapedBody = escapeForAppleScript(body)
        let folderName = folder ?? "Notes"
        let escapedFolder = escapeForAppleScript(folderName)

        // Build HTML body with title as h1
        let htmlBody = "<div><h1>\(escapeHTML(title))</h1></div><div>\(escapeHTML(body))</div>"
        let escapedHtmlBody = escapeForAppleScript(htmlBody)

        let script: String
        if let account = account {
            let escapedAccount = escapeForAppleScript(account)
            script = """
            tell application "Notes"
                tell account "\(escapedAccount)"
                    set newNote to make new note at folder "\(escapedFolder)" with properties {name:"\(escapedTitle)", body:"\(escapedHtmlBody)"}
                    return id of newNote
                end tell
            end tell
            """
        } else {
            script = """
            tell application "Notes"
                set newNote to make new note at folder "\(escapedFolder)" with properties {name:"\(escapedTitle)", body:"\(escapedHtmlBody)"}
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
            let htmlBody = "<div><h1>\(escapeHTML(note.title))</h1></div><div>\(escapeHTML(note.body))</div>"

            scriptParts.append("""
                set \(varName) to make new note at folder "\(escapeForAppleScript(folder))" with properties {name:"\(escapeForAppleScript(note.title))", body:"\(escapeForAppleScript(htmlBody))"}
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
        // So we need to always set both name and body together for consistency
        let script: String

        if let title = title, let body = body {
            // Both title and body provided
            let htmlBody = "<div><h1>\(escapeHTML(title))</h1></div><div>\(escapeHTML(body))</div>"
            script = """
            tell application "Notes"
                set theNote to note id "\(noteId)"
                set body of theNote to "\(escapeForAppleScript(htmlBody))"
            end tell
            """
        } else if let title = title {
            // Only title - get current body and rebuild
            script = """
            tell application "Notes"
                set theNote to note id "\(noteId)"
                set currentBody to plaintext of theNote
                -- Remove first line (old title) from body
                set AppleScript's text item delimiters to {return, linefeed, return & linefeed}
                set bodyLines to text items of currentBody
                if (count of bodyLines) > 1 then
                    set bodyContent to items 2 thru -1 of bodyLines as text
                else
                    set bodyContent to ""
                end if
                set AppleScript's text item delimiters to ""
                set newBody to "<div><h1>\(escapeForAppleScript(escapeHTML(title)))</h1></div><div>" & bodyContent & "</div>"
                set body of theNote to newBody
            end tell
            """
        } else if let body = body {
            // Only body - preserve current title
            script = """
            tell application "Notes"
                set theNote to note id "\(noteId)"
                set currentTitle to name of theNote
                set newBody to "<div><h1>" & currentTitle & "</h1></div><div>\(escapeForAppleScript(escapeHTML(body)))</div>"
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
