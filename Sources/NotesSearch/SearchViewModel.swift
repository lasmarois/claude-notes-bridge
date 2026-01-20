import Foundation
import SwiftUI
import NotesLib

enum SearchMode: String, CaseIterable {
    case basic = "Basic"
    case fts = "Full-Text"
    case semantic = "Semantic"

    var icon: String {
        switch self {
        case .basic: return "magnifyingglass"
        case .fts: return "doc.text.magnifyingglass"
        case .semantic: return "brain"
        }
    }

    var description: String {
        switch self {
        case .basic: return "Search titles and snippets"
        case .fts: return "Search all content (fast)"
        case .semantic: return "AI-powered similarity search"
        }
    }
}

struct SearchResult: Identifiable, Hashable {
    let id: String
    let title: String
    let folder: String?
    let snippet: String?
    let score: Float?
    let modifiedAt: Date?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var searchMode: SearchMode = .basic
    @Published var results: [SearchResult] = []
    @Published var selectedResult: SearchResult?
    @Published var selectedNoteContent: NoteContent?
    @Published var isSearching: Bool = false
    @Published var errorMessage: String?
    @Published var hasFullDiskAccess: Bool = true

    private let database = NotesDatabase()
    private var searchIndex: SearchIndex?
    private var semanticSearch: SemanticSearch?
    private var searchTask: Task<Void, Never>?

    init() {
        checkPermissions()
        searchIndex = SearchIndex(notesDB: database)
        semanticSearch = SemanticSearch(notesDB: database)
    }

    func checkPermissions() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess()
    }

    func search() {
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            return
        }

        searchTask = Task {
            isSearching = true
            errorMessage = nil

            do {
                switch searchMode {
                case .basic:
                    try await performBasicSearch(query)
                case .fts:
                    try await performFTSSearch(query)
                case .semantic:
                    try await performSemanticSearch(query)
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }

            if !Task.isCancelled {
                isSearching = false
            }
        }
    }

    private func performBasicSearch(_ query: String) async throws {
        let notes = try database.searchNotes(query: query, limit: 50)
        results = notes.map { note in
            SearchResult(
                id: note.id,
                title: note.title,
                folder: note.folder,
                snippet: note.matchSnippet,
                score: nil,
                modifiedAt: note.modifiedAt
            )
        }
    }

    private func performFTSSearch(_ query: String) async throws {
        guard let index = searchIndex else { return }

        let (ftsResults, _, _) = try index.searchWithAutoRebuild(query: query, limit: 50)

        // Get note metadata for each result
        var searchResults: [SearchResult] = []
        let allNotes = try database.listNotes(limit: 10000)

        for (noteId, snippet) in ftsResults {
            if let note = allNotes.first(where: { $0.id == noteId }) {
                searchResults.append(SearchResult(
                    id: note.id,
                    title: note.title,
                    folder: note.folder,
                    snippet: snippet.isEmpty ? nil : snippet,
                    score: nil,
                    modifiedAt: note.modifiedAt
                ))
            }
        }

        results = searchResults
    }

    private func performSemanticSearch(_ query: String) async throws {
        guard let semantic = semanticSearch else { return }

        let semanticResults = try await semantic.search(query: query, limit: 20)

        results = semanticResults.map { result in
            SearchResult(
                id: result.noteId,
                title: result.title,
                folder: result.folder,
                snippet: nil,
                score: result.score,
                modifiedAt: nil
            )
        }
    }

    func loadNoteContent(for result: SearchResult) {
        Task {
            do {
                let content = try database.readNote(id: result.id)
                selectedNoteContent = content
            } catch {
                errorMessage = "Failed to load note: \(error.localizedDescription)"
            }
        }
    }

    func openInNotesApp() {
        guard let result = selectedResult else { return }

        // Try URL scheme first
        if let url = URL(string: "notes://showNote?identifier=\(result.id)") {
            NSWorkspace.shared.open(url)
        }
    }

    func copyNoteContent() {
        guard let content = selectedNoteContent else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content.content, forType: .string)
    }

    func copyNoteID() {
        guard let result = selectedResult else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.id, forType: .string)
    }
}
