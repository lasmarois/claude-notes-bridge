import Foundation

// MARK: - Note Models

/// Basic note metadata for list operations
public struct Note {
    public let id: String
    public let title: String
    public let folder: String?
    public let createdAt: Date?
    public let modifiedAt: Date?
    public var matchSnippet: String?  // Search context snippet with highlighted matches

    public init(id: String, title: String, folder: String?, createdAt: Date?, modifiedAt: Date?, matchSnippet: String? = nil) {
        self.id = id
        self.title = title
        self.folder = folder
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.matchSnippet = matchSnippet
    }
}

/// Full note content for read operations
public struct NoteContent: Codable {
    public let id: String
    public let title: String
    public let content: String
    public let folder: String?
    public let createdAt: Date?
    public let modifiedAt: Date?
    public var attachments: [Attachment] = []
    public var hashtags: [String] = []
    public var noteLinks: [NoteLink] = []

    enum CodingKeys: String, CodingKey {
        case id, title, content, folder, createdAt, modifiedAt
        case attachments, hashtags, noteLinks
    }

    public init(id: String, title: String, content: String, folder: String?, createdAt: Date?, modifiedAt: Date?) {
        self.id = id
        self.title = title
        self.content = content
        self.folder = folder
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        hashtags = try container.decodeIfPresent([String].self, forKey: .hashtags) ?? []
        noteLinks = try container.decodeIfPresent([NoteLink].self, forKey: .noteLinks) ?? []
    }
}

/// A link to another note
public struct NoteLink: Codable {
    public let text: String      // Display text of the link
    public let targetId: String  // UUID of the target note

    public init(text: String, targetId: String) {
        self.text = text
        self.targetId = targetId
    }
}

/// Attachment metadata
public struct Attachment: Codable {
    public let id: String           // x-coredata://...ICAttachment/p123
    public let identifier: String   // UUID
    public let name: String?        // filename (e.g., "IMG_0473.jpg")
    public let typeUTI: String      // e.g., "public.jpeg", "com.adobe.pdf"
    public let fileSize: Int64      // bytes
    public let createdAt: Date?
    public let modifiedAt: Date?

    public init(id: String, identifier: String, name: String?, typeUTI: String, fileSize: Int64, createdAt: Date?, modifiedAt: Date?) {
        self.id = id
        self.identifier = identifier
        self.name = name
        self.typeUTI = typeUTI
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

// MARK: - Errors

public enum NotesError: LocalizedError {
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

    public var errorDescription: String? {
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
