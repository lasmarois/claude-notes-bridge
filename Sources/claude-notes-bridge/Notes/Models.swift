import Foundation

// MARK: - Note Models

/// Basic note metadata for list operations
struct Note {
    let id: String
    let title: String
    let folder: String?
    let createdAt: Date?
    let modifiedAt: Date?
}

/// Full note content for read operations
struct NoteContent {
    let id: String
    let title: String
    let content: String
    let folder: String?
    let createdAt: Date?
    let modifiedAt: Date?
    var attachments: [Attachment] = []
    var hashtags: [String] = []
    var noteLinks: [NoteLink] = []
}

/// A link to another note
struct NoteLink {
    let text: String      // Display text of the link
    let targetId: String  // UUID of the target note
}

/// Attachment metadata
struct Attachment {
    let id: String           // x-coredata://...ICAttachment/p123
    let identifier: String   // UUID
    let name: String?        // filename (e.g., "IMG_0473.jpg")
    let typeUTI: String      // e.g., "public.jpeg", "com.adobe.pdf"
    let fileSize: Int64      // bytes
    let createdAt: Date?
    let modifiedAt: Date?
}

// MARK: - Errors

enum NotesError: LocalizedError {
    case databaseNotFound
    case cannotOpenDatabase(String)
    case queryFailed(String)
    case noteNotFound(String)
    case folderNotFound(String)
    case decodingFailed(String)
    case missingParameter(String)
    case encodingError
    case appleScriptError(String)
    case attachmentNotFound(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "Notes database not found. Is Full Disk Access enabled?"
        case .cannotOpenDatabase(let reason):
            return "Cannot open Notes database: \(reason)"
        case .queryFailed(let reason):
            return "Database query failed: \(reason)"
        case .noteNotFound(let id):
            return "Note not found: \(id)"
        case .folderNotFound(let name):
            return "Folder not found: \(name)"
        case .decodingFailed(let reason):
            return "Failed to decode note content: \(reason)"
        case .missingParameter(let name):
            return "Missing required parameter: \(name)"
        case .encodingError:
            return "Failed to encode response"
        case .appleScriptError(let message):
            return "AppleScript error: \(message)"
        case .attachmentNotFound(let id):
            return "Attachment not found: \(id)"
        }
    }
}
