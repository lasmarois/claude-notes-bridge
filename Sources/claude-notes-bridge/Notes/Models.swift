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
}

// MARK: - Errors

enum NotesError: LocalizedError {
    case databaseNotFound
    case cannotOpenDatabase(String)
    case queryFailed(String)
    case noteNotFound(String)
    case decodingFailed(String)
    case missingParameter(String)
    case encodingError

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
        case .decodingFailed(let reason):
            return "Failed to decode note content: \(reason)"
        case .missingParameter(let name):
            return "Missing required parameter: \(name)"
        case .encodingError:
            return "Failed to encode response"
        }
    }
}
