import Foundation
import SwiftUI
import NotesLib

enum SearchSource: String {
    case basic = "Title"
    case fts = "Content"
    case semantic = "AI"
    case multiple = "Multiple"

    var icon: String {
        switch self {
        case .basic: return "textformat"
        case .fts: return "doc.text"
        case .semantic: return "brain"
        case .multiple: return "sparkles"
        }
    }

    var color: String {
        switch self {
        case .basic: return "blue"
        case .fts: return "green"
        case .semantic: return "purple"
        case .multiple: return "orange"
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
    var sources: Set<SearchSource>

    init(id: String, title: String, folder: String?, snippet: String?, score: Float?, modifiedAt: Date?, source: SearchSource) {
        self.id = id
        self.title = title
        self.folder = folder
        self.snippet = snippet
        self.score = score
        self.modifiedAt = modifiedAt
        self.sources = [source]
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }

    var displaySource: SearchSource {
        if sources.count > 1 { return .multiple }
        return sources.first ?? .basic
    }

    var scorePercentage: Int? {
        guard let score = score else { return nil }
        return Int(score * 100)
    }

    var scoreLabel: String? {
        guard let pct = scorePercentage else { return nil }
        if pct >= 70 { return "High match" }
        if pct >= 50 { return "Good match" }
        if pct >= 30 { return "Partial match" }
        return "Weak match"
    }

    /// Merge another result into this one (for deduplication)
    mutating func merge(with other: SearchResult) {
        sources.formUnion(other.sources)
        // Keep snippet if we don't have one
        // Keep the better score
    }
}

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var results: [SearchResult] = []
    @Published var selectedResult: SearchResult?
    @Published var selectedNoteContent: NoteContent?
    @Published var isSearching: Bool = false
    @Published var errorMessage: String?
    @Published var hasFullDiskAccess: Bool = true

    // Search options
    @Published var fuzzyEnabled: Bool = false
    @Published var selectedFolders: Set<String> = []  // Empty = all folders
    @Published var selectedAccounts: Set<String> = []  // Empty = all accounts
    @Published var availableFolders: [(name: String, account: String?)] = []
    @Published var availableAccounts: [String] = []
    @Published var minSemanticScore: Float = 0.3  // Filter out weak semantic matches

    // All notes (shown when not searching)
    @Published var allNotes: [SearchResult] = []
    @Published var showDeletedNotes: Bool = false

    // Source filters (which result types to show)
    @Published var showTitleResults: Bool = true
    @Published var showContentResults: Bool = true
    @Published var showAIResults: Bool = true

    // Status - tracks which searches are running
    @Published var searchingBasic: Bool = false
    @Published var searchingFTS: Bool = false
    @Published var searchingSemantic: Bool = false
    @Published var semanticStatus: String? = nil

    private let database = NotesDatabase()
    private var searchIndex: SearchIndex?
    private var semanticSearch: SemanticSearch?
    private var searchTask: Task<Void, Never>?

    // Track results by source for merging
    private var resultsBySource: [SearchSource: [String: SearchResult]] = [:]

    init() {
        searchIndex = SearchIndex(notesDB: database)
        semanticSearch = SemanticSearch(notesDB: database)
        checkPermissions()
        loadFolders()
        loadAccounts()
        loadAllNotes()
    }

    func checkPermissions() {
        do {
            _ = try database.listFolders()
            hasFullDiskAccess = true
        } catch {
            hasFullDiskAccess = false
        }
    }

    func loadFolders() {
        do {
            // Get folders with account info, ordered like Notes app
            let folders = try database.listFoldersWithAccounts()
            availableFolders = folders.map { (name: $0.name, account: $0.accountName) }
        } catch {
            availableFolders = []
        }
    }

    func loadAccounts() {
        do {
            let accounts = try database.listAccounts()
            availableAccounts = accounts.map { $0.name }
        } catch {
            availableAccounts = []
        }
    }

    func loadAllNotes() {
        Task {
            do {
                let notes = try database.listNotes(limit: 10000, includeDeleted: showDeletedNotes)
                allNotes = notes.map { note in
                    SearchResult(
                        id: note.id,
                        title: note.title,
                        folder: note.folder,
                        snippet: nil,
                        score: nil,
                        modifiedAt: note.modifiedAt,
                        source: .basic
                    )
                }
            } catch {
                allNotes = []
            }
        }
    }

    func toggleShowDeletedNotes() {
        showDeletedNotes.toggle()
        loadAllNotes()
    }

    @Published var isRefreshing = false

    func refresh() {
        isRefreshing = true
        loadFolders()
        loadAccounts()
        loadAllNotes()
        // Brief delay to show animation
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            isRefreshing = false
        }
    }

    var isAnySearching: Bool {
        searchingBasic || searchingFTS || searchingSemantic
    }

    /// Results filtered by source type preferences
    var filteredResults: [SearchResult] {
        results.filter { result in
            // Check if any of the result's sources are enabled
            for source in result.sources {
                switch source {
                case .basic:
                    if showTitleResults { return true }
                case .fts:
                    if showContentResults { return true }
                case .semantic:
                    if showAIResults { return true }
                case .multiple:
                    // Multiple means it matched multiple sources, show if any are enabled
                    return true
                }
            }
            return false
        }
    }

    /// Check if any source filter is active (not all enabled)
    var hasActiveSourceFilter: Bool {
        !showTitleResults || !showContentResults || !showAIResults
    }

    /// Check if any folder filter is active
    var hasActiveFolderFilter: Bool {
        !selectedFolders.isEmpty
    }

    /// Check if any account filter is active
    var hasActiveAccountFilter: Bool {
        !selectedAccounts.isEmpty
    }

    /// Toggle a folder in the selection
    func toggleFolder(_ folder: String) {
        if selectedFolders.contains(folder) {
            selectedFolders.remove(folder)
        } else {
            selectedFolders.insert(folder)
        }
        // Re-run search with new filter
        if !searchText.isEmpty {
            search()
        }
    }

    /// Toggle an account in the selection
    func toggleAccount(_ account: String) {
        if selectedAccounts.contains(account) {
            selectedAccounts.remove(account)
        } else {
            selectedAccounts.insert(account)
        }
        // Re-run search with new filter
        if !searchText.isEmpty {
            search()
        }
    }

    /// Clear all folder filters
    func clearFolderFilter() {
        selectedFolders.removeAll()
        if !searchText.isEmpty {
            search()
        }
    }

    /// Clear all account filters
    func clearAccountFilter() {
        selectedAccounts.removeAll()
        if !searchText.isEmpty {
            search()
        }
    }

    /// Select only one folder
    func selectOnlyFolder(_ folder: String) {
        selectedFolders = [folder]
        search()
    }

    func search() {
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            resultsBySource = [:]
            return
        }

        // Clear previous results
        results = []
        resultsBySource = [:]
        errorMessage = nil
        semanticStatus = nil

        // Run all searches in parallel
        searchTask = Task {
            await withTaskGroup(of: Void.self) { group in
                // Basic search (fastest)
                group.addTask { @MainActor in
                    await self.runBasicSearch(query)
                }

                // FTS search (fast)
                group.addTask { @MainActor in
                    await self.runFTSSearch(query)
                }

                // Semantic search (slower)
                group.addTask { @MainActor in
                    await self.runSemanticSearch(query)
                }
            }
        }
    }

    private func runBasicSearch(_ query: String) async {
        searchingBasic = true
        defer { searchingBasic = false }

        do {
            // Search in each selected folder, or all if none selected
            let foldersToSearch: [String?] = selectedFolders.isEmpty ? [nil] : selectedFolders.map { $0 }

            var allNotes: [Note] = []
            for folder in foldersToSearch {
                let notes = try database.searchNotes(
                    query: query,
                    limit: 30,
                    searchContent: false,  // FTS handles content search more efficiently
                    fuzzy: fuzzyEnabled,
                    folder: folder
                )
                allNotes.append(contentsOf: notes)
            }

            let newResults = allNotes.map { note in
                SearchResult(
                    id: note.id,
                    title: note.title,
                    folder: note.folder,
                    snippet: note.matchSnippet,
                    score: nil,
                    modifiedAt: note.modifiedAt,
                    source: .basic
                )
            }

            mergeResults(newResults, from: .basic)
        } catch {
            // Basic search failed, continue with others
        }
    }

    private func runFTSSearch(_ query: String) async {
        guard let index = searchIndex else { return }
        searchingFTS = true
        defer { searchingFTS = false }

        do {
            let (ftsResults, _, _) = try index.searchWithAutoRebuild(query: query, limit: 30)

            // Get note metadata
            let allNotes = try database.listNotes(limit: 10000)
            var newResults: [SearchResult] = []

            for (noteId, snippet) in ftsResults {
                if let note = allNotes.first(where: { $0.id == noteId }) {
                    // Filter by selected folders (if any)
                    if !selectedFolders.isEmpty {
                        guard let noteFolder = note.folder, selectedFolders.contains(noteFolder) else {
                            continue
                        }
                    }
                    newResults.append(SearchResult(
                        id: note.id,
                        title: note.title,
                        folder: note.folder,
                        snippet: snippet.isEmpty ? nil : snippet,
                        score: nil,
                        modifiedAt: note.modifiedAt,
                        source: .fts
                    ))
                }
            }

            mergeResults(newResults, from: .fts)
        } catch {
            // FTS failed, continue with others
        }
    }

    private func runSemanticSearch(_ query: String) async {
        guard let semantic = semanticSearch else { return }
        searchingSemantic = true
        defer {
            searchingSemantic = false
            semanticStatus = nil
        }

        do {
            let indexedCount = await semantic.indexedCount
            if indexedCount == 0 {
                semanticStatus = "Building AI index..."
            } else {
                semanticStatus = "AI searching..."
            }

            let semanticResults = try await semantic.search(query: query, limit: 20)

            let filtered = semanticResults.filter { result in
                if result.score < minSemanticScore { return false }
                // Filter by selected folders (if any)
                if !selectedFolders.isEmpty {
                    guard let folder = result.folder, selectedFolders.contains(folder) else {
                        return false
                    }
                }
                return true
            }

            let newResults = filtered.map { result in
                SearchResult(
                    id: result.noteId,
                    title: result.title,
                    folder: result.folder,
                    snippet: nil,
                    score: result.score,
                    modifiedAt: nil,
                    source: .semantic
                )
            }

            mergeResults(newResults, from: .semantic)
        } catch {
            // Semantic search failed, continue with others
        }
    }

    /// Merge new results into the combined results list
    private func mergeResults(_ newResults: [SearchResult], from source: SearchSource) {
        // Store results by source
        var sourceResults: [String: SearchResult] = [:]
        for result in newResults {
            sourceResults[result.id] = result
        }
        resultsBySource[source] = sourceResults

        // Rebuild combined results
        var combined: [String: SearchResult] = [:]

        for (source, sourceResults) in resultsBySource {
            for (id, result) in sourceResults {
                if var existing = combined[id] {
                    existing.sources.insert(source)
                    combined[id] = existing
                } else {
                    combined[id] = result
                }
            }
        }

        // Sort: prioritize multi-source matches, then by score/date
        results = combined.values.sorted { a, b in
            // Multi-source wins
            if a.sources.count != b.sources.count {
                return a.sources.count > b.sources.count
            }
            // Then by semantic score if available
            if let aScore = a.score, let bScore = b.score {
                return aScore > bScore
            }
            // Then by date
            if let aDate = a.modifiedAt, let bDate = b.modifiedAt {
                return aDate > bDate
            }
            // Prefer ones with scores
            if a.score != nil && b.score == nil { return true }
            if b.score != nil && a.score == nil { return false }
            return a.title < b.title
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

    // MARK: - Keyboard Navigation

    func selectNext() {
        guard !results.isEmpty else { return }

        if let current = selectedResult,
           let currentIndex = results.firstIndex(of: current) {
            let nextIndex = min(currentIndex + 1, results.count - 1)
            selectedResult = results[nextIndex]
        } else {
            selectedResult = results.first
        }

        if let result = selectedResult {
            loadNoteContent(for: result)
        }
    }

    func selectPrevious() {
        guard !results.isEmpty else { return }

        if let current = selectedResult,
           let currentIndex = results.firstIndex(of: current) {
            let prevIndex = max(currentIndex - 1, 0)
            selectedResult = results[prevIndex]
        } else {
            selectedResult = results.first
        }

        if let result = selectedResult {
            loadNoteContent(for: result)
        }
    }

    func clearSearch() {
        searchText = ""
        results = []
        resultsBySource = [:]
        selectedResult = nil
        selectedNoteContent = nil
        errorMessage = nil
    }
}
