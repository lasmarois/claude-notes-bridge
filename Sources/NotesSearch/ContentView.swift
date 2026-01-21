import SwiftUI
import AppKit
import WebKit
import NotesLib

// MARK: - Focused Values for Menu Commands

struct ShowExportPanelKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ShowImportPanelKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct AddSelectedToExportKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct AddAllToExportKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ExportQueueCountKey: FocusedValueKey {
    typealias Value = Int
}

struct HasSelectedResultKey: FocusedValueKey {
    typealias Value = Bool
}

struct HasResultsKey: FocusedValueKey {
    typealias Value = Bool
}

struct RefreshNotesKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var showExportPanel: (() -> Void)? {
        get { self[ShowExportPanelKey.self] }
        set { self[ShowExportPanelKey.self] = newValue }
    }

    var showImportPanel: (() -> Void)? {
        get { self[ShowImportPanelKey.self] }
        set { self[ShowImportPanelKey.self] = newValue }
    }

    var addSelectedToExport: (() -> Void)? {
        get { self[AddSelectedToExportKey.self] }
        set { self[AddSelectedToExportKey.self] = newValue }
    }

    var addAllToExport: (() -> Void)? {
        get { self[AddAllToExportKey.self] }
        set { self[AddAllToExportKey.self] = newValue }
    }

    var exportQueueCount: Int? {
        get { self[ExportQueueCountKey.self] }
        set { self[ExportQueueCountKey.self] = newValue }
    }

    var hasSelectedResult: Bool? {
        get { self[HasSelectedResultKey.self] }
        set { self[HasSelectedResultKey.self] = newValue }
    }

    var hasResults: Bool? {
        get { self[HasResultsKey.self] }
        set { self[HasResultsKey.self] = newValue }
    }

    var refreshNotes: (() -> Void)? {
        get { self[RefreshNotesKey.self] }
        set { self[RefreshNotesKey.self] = newValue }
    }
}

struct ContentView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @EnvironmentObject var exportViewModel: ExportViewModel
    @EnvironmentObject var importViewModel: ImportViewModel
    @FocusState private var isSearchFocused: Bool

    // Panel state
    @State private var showPanel: Bool = false
    @State private var selectedPanelTab: ImportExportTab = .export

    var body: some View {
        if !viewModel.hasFullDiskAccess {
            PermissionView()
        } else {
            HStack(spacing: 0) {
                // Main content
                NavigationSplitView {
                    sidebarContent
                } detail: {
                    detailContent
                }
                .navigationSplitViewStyle(.balanced)

                // Import/Export panel (collapsible)
                if showPanel {
                    Divider()

                    ImportExportPanel(
                        selectedTab: $selectedPanelTab,
                        isOpen: $showPanel,
                        exportViewModel: exportViewModel,
                        importViewModel: importViewModel
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showPanel)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    importButton
                    exportButton
                }
            }
            .focusedValue(\.showExportPanel) {
                withAnimation {
                    selectedPanelTab = .export
                    showPanel = true
                }
            }
            .focusedValue(\.showImportPanel) {
                withAnimation {
                    selectedPanelTab = .import
                    showPanel = true
                }
            }
            .focusedValue(\.addSelectedToExport) {
                if let result = viewModel.selectedResult {
                    exportViewModel.addToQueue(result)
                }
            }
            .focusedValue(\.addAllToExport) {
                exportViewModel.addAllToQueue(viewModel.results)
            }
            .focusedValue(\.exportQueueCount, exportViewModel.queueCount)
            .focusedValue(\.hasSelectedResult, viewModel.selectedResult != nil)
            .focusedValue(\.hasResults, !viewModel.results.isEmpty)
            .focusedValue(\.refreshNotes) { viewModel.refresh() }
            .onAppear {
                // Delay focus to ensure window is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isSearchFocused = true
                    activateApp()
                }
            }
            .onExitCommand {
                viewModel.clearSearch()
                isSearchFocused = true
            }
            .background(KeyboardHandler(
                onArrowDown: { viewModel.selectNext() },
                onArrowUp: { viewModel.selectPrevious() },
                onEnter: { viewModel.openInNotesApp() },
                onEscape: {
                    if showPanel {
                        // Don't close panel during operations (must use X button)
                        let isOperationInProgress = exportViewModel.isExporting || importViewModel.isImporting
                        if !isOperationInProgress {
                            withAnimation { showPanel = false }
                        }
                    } else {
                        viewModel.clearSearch()
                        isSearchFocused = true
                    }
                }
            ))
        }
    }

    // MARK: - Toolbar Buttons

    private var exportButton: some View {
        Button(action: {
            withAnimation {
                selectedPanelTab = .export
                showPanel = true
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                if !exportViewModel.isEmpty {
                    Text("\(exportViewModel.queueCount)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .help("Show Export panel (⌘E)")
    }

    private var importButton: some View {
        Button(action: {
            withAnimation {
                selectedPanelTab = .import
                showPanel = true
            }
        }) {
            Image(systemName: "square.and.arrow.down")
        }
        .help("Show Import panel (⌘I)")
    }

    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            window.makeKey()
            window.orderFrontRegardless()
        }
    }

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchBarView(isSearchFocused: $isSearchFocused)
                .padding()

            // Filter bar
            SearchFilterBar()
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            Divider()

            // Search status indicators
            if viewModel.isAnySearching {
                SearchStatusView()
                    .padding(.horizontal)
            }

            // Results list
            if viewModel.isAnySearching {
                Spacer()
                ProgressView("Searching...")
                    .padding()
                Spacer()
            } else if viewModel.searchText.isEmpty {
                // Browse mode - show all notes
                if viewModel.allNotes.isEmpty {
                    Spacer()
                    ProgressView("Loading notes...")
                        .padding()
                    Spacer()
                } else {
                    ResultsListView()
                }
            } else if viewModel.results.isEmpty {
                // Search mode with no results
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                // Search mode with results
                ResultsListView()
            }

            if let error = viewModel.errorMessage {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 300)
    }

    private var detailContent: some View {
        Group {
            if let note = viewModel.selectedNoteContent {
                NotePreviewView(note: note)
            } else if viewModel.selectedResult != nil {
                ProgressView("Loading note...")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a note to preview")
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 400)
    }
}

// MARK: - Search Bar

struct SearchBarView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search notes...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit {
                    viewModel.search()
                }
                .onChange(of: viewModel.searchText) { _ in
                    // Debounced search
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        viewModel.search()
                    }
                }

            if !viewModel.searchText.isEmpty {
                Button(action: {
                    viewModel.searchText = ""
                    viewModel.results = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Search Filter Bar

struct SearchFilterBar: View {
    @EnvironmentObject var viewModel: SearchViewModel

    var body: some View {
        HStack(spacing: 6) {
            // Source type filters (compact icons) - only show when searching
            if !viewModel.searchText.isEmpty {
                HStack(spacing: 2) {
                    FilterToggle(icon: "textformat", color: .blue, isOn: $viewModel.showTitleResults, tooltip: "Toggle title search results")
                    FilterToggle(icon: "doc.text", color: .green, isOn: $viewModel.showContentResults, tooltip: "Toggle full-text content results")
                    FilterToggle(icon: "brain", color: .purple, isOn: $viewModel.showAIResults, tooltip: "Toggle AI semantic search results")
                }

                Divider()
                    .frame(height: 16)
            }

            // Account filter
            if viewModel.availableAccounts.count > 1 {
                AccountFilterButton()
            }

            // Folder filter
            FolderFilterButton()

            Spacer()

            // Show deleted notes toggle
            Button(action: { viewModel.toggleShowDeletedNotes() }) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(viewModel.showDeletedNotes ? .red : .secondary.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(viewModel.showDeletedNotes ? Color.red.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .quickTooltip(viewModel.showDeletedNotes ? "Hide deleted notes" : "Show deleted notes")

            // Refresh button
            Button(action: { viewModel.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                    .animation(viewModel.isRefreshing ? .linear(duration: 0.5).repeatForever(autoreverses: false) : .default, value: viewModel.isRefreshing)
            }
            .buttonStyle(.plain)
            .quickTooltip("Refresh notes (⌘R)")
        }
    }
}

// MARK: - Account Filter

struct AccountFilterButton: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @State private var showPopover = false
    @State private var showTooltip = false
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?

    private var tooltipText: String {
        viewModel.hasActiveAccountFilter ? "Filtering \(viewModel.selectedAccounts.count) account(s)" : "Filter by account (iCloud, On My Mac...)"
    }

    var body: some View {
        Button(action: {
            showTooltip = false
            showPopover.toggle()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "person.circle")
                    .font(.system(size: 11))
                if !viewModel.selectedAccounts.isEmpty {
                    Text("\(viewModel.selectedAccounts.count)")
                        .font(.system(size: 9, weight: .medium))
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
            }
            .foregroundColor(viewModel.hasActiveAccountFilter ? .orange : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            hoverTask?.cancel()
            if hovering && !showPopover {
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    if !Task.isCancelled && isHovering && !showPopover {
                        showTooltip = true
                    }
                }
            } else {
                showTooltip = false
            }
        }
        .popover(isPresented: $showTooltip, arrowEdge: .bottom) {
            Text(tooltipText)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .fixedSize()
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            AccountPopover(viewModel: viewModel)
        }
    }
}

struct AccountPopover: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Accounts")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if viewModel.hasActiveAccountFilter {
                    Button("Clear") {
                        viewModel.clearAccountFilter()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Account list
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.availableAccounts, id: \.self) { account in
                        AccountRowView(account: account, viewModel: viewModel)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 200)
        }
        .frame(width: 180)
    }
}

struct AccountRowView: View {
    let account: String
    @ObservedObject var viewModel: SearchViewModel

    private var isSelected: Bool {
        viewModel.selectedAccounts.contains(account)
    }

    var body: some View {
        Button(action: { viewModel.toggleAccount(account) }) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "person.circle.fill" : "person.circle")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .orange : .secondary)

                Text(account)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .orange : .primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.orange.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Folder Filter

struct FolderFilterButton: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @State private var showPopover = false
    @State private var showTooltip = false
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?

    private var tooltipText: String {
        viewModel.hasActiveFolderFilter ? "Filtering \(viewModel.selectedFolders.count) folder(s)" : "Filter by folder"
    }

    var body: some View {
        Button(action: {
            showTooltip = false
            showPopover.toggle()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                if !viewModel.selectedFolders.isEmpty {
                    Text("\(viewModel.selectedFolders.count)")
                        .font(.system(size: 9, weight: .medium))
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
            }
            .foregroundColor(viewModel.hasActiveFolderFilter ? .accentColor : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            hoverTask?.cancel()
            if hovering && !showPopover {
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    if !Task.isCancelled && isHovering && !showPopover {
                        showTooltip = true
                    }
                }
            } else {
                showTooltip = false
            }
        }
        .popover(isPresented: $showTooltip, arrowEdge: .bottom) {
            Text(tooltipText)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .fixedSize()
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            FolderTreePopover(viewModel: viewModel)
        }
    }
}

struct FolderTreePopover: View {
    @ObservedObject var viewModel: SearchViewModel
    @Environment(\.dismiss) private var dismiss

    // Group folders by account
    private var foldersByAccount: [(account: String, folders: [String])] {
        var grouped: [String: [String]] = [:]
        for folder in viewModel.availableFolders {
            let account = folder.account ?? "Local"
            grouped[account, default: []].append(folder.name)
        }
        // Sort accounts to match database order (use availableAccounts order)
        return viewModel.availableAccounts.compactMap { account in
            guard let folders = grouped[account] else { return nil }
            return (account: account, folders: folders)
        } + (grouped["Local"] != nil ? [(account: "Local", folders: grouped["Local"]!)] : [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Folders")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if viewModel.hasActiveFolderFilter {
                    Button("Clear") {
                        viewModel.clearFolderFilter()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Folder list grouped by account
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(foldersByAccount, id: \.account) { group in
                        // Account header (only if multiple accounts)
                        if viewModel.availableAccounts.count > 1 {
                            Text(group.account)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                        }

                        ForEach(group.folders, id: \.self) { folder in
                            FolderRowView(folder: folder, viewModel: viewModel)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 200)
    }
}

struct FolderRowView: View {
    let folder: String
    @ObservedObject var viewModel: SearchViewModel

    private var isSelected: Bool {
        viewModel.selectedFolders.contains(folder)
    }

    var body: some View {
        Button(action: { viewModel.toggleFolder(folder) }) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(folder)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Tooltip

struct QuickTooltip: ViewModifier {
    let text: String
    @State private var isHovering = false
    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        if !Task.isCancelled && isHovering {
                            showTooltip = true
                        }
                    }
                } else {
                    showTooltip = false
                }
            }
            .popover(isPresented: $showTooltip, arrowEdge: .bottom) {
                Text(text)
                    .font(.system(size: 11))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .fixedSize()
            }
    }
}

extension View {
    func quickTooltip(_ text: String) -> some View {
        modifier(QuickTooltip(text: text))
    }
}

struct FilterToggle: View {
    let icon: String
    let color: Color
    @Binding var isOn: Bool
    let tooltip: String

    var body: some View {
        Button(action: { isOn.toggle() }) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 20, height: 20)
                .background(isOn ? color.opacity(0.2) : Color.clear)
                .foregroundColor(isOn ? color : .secondary.opacity(0.6))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .quickTooltip(tooltip)
    }
}

// MARK: - Search Status

struct SearchStatusView: View {
    @EnvironmentObject var viewModel: SearchViewModel

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(active: viewModel.searchingBasic, label: "Title", color: .blue)
            StatusDot(active: viewModel.searchingFTS, label: "Content", color: .green)
            StatusDot(active: viewModel.searchingSemantic, label: "AI", color: .purple)

            if let status = viewModel.semanticStatus {
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct StatusDot: View {
    let active: Bool
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? color : color.opacity(0.3))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundColor(active ? .primary : .secondary)
        }
    }
}

// MARK: - Results List

struct ResultsListView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @EnvironmentObject var exportViewModel: ExportViewModel

    private var displayResults: [SearchResult] {
        // Show all notes when not searching, otherwise show filtered search results
        if viewModel.searchText.isEmpty {
            return viewModel.allNotes
        }
        return viewModel.filteredResults
    }

    private var isShowingAllNotes: Bool {
        viewModel.searchText.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Results header with bulk actions
            if !displayResults.isEmpty {
                resultsHeader
                Divider()
            }

            // Results list
            ScrollViewReader { proxy in
                List(displayResults, selection: $viewModel.selectedResult) { result in
                    ResultRowView(result: result)
                        .tag(result)
                        .id(result.id)
                }
                .listStyle(.sidebar)
                .onChange(of: viewModel.selectedResult) { newValue in
                    if let result = newValue {
                        viewModel.loadNoteContent(for: result)
                        // Scroll to selected item
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(result.id, anchor: .center)
                        }
                    } else {
                        viewModel.selectedNoteContent = nil
                    }
                }
            }
        }
    }

    private var resultsHeader: some View {
        HStack {
            if isShowingAllNotes {
                Text("\(displayResults.count) note(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if viewModel.hasActiveSourceFilter {
                Text("\(displayResults.count) of \(viewModel.results.count) result(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("\(viewModel.results.count) result(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: addAllToExport) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text("Add All")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .help("Add all visible \(isShowingAllNotes ? "notes" : "results") to export queue")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func addAllToExport() {
        exportViewModel.addAllToQueue(displayResults)
    }
}

struct ResultRowView: View {
    let result: SearchResult
    @EnvironmentObject var exportViewModel: ExportViewModel
    @State private var isHovering: Bool = false

    private var isInQueue: Bool {
        exportViewModel.isInQueue(id: result.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                // Add to queue button (show on hover or if in queue)
                if isHovering || isInQueue {
                    addToQueueButton
                }

                // Source badges
                SourceBadge(source: result.displaySource)
            }

            HStack {
                if let folder = result.folder {
                    Label(folder, systemImage: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let score = result.score {
                    Text(String(format: "%.0f%%", score * 100))
                        .font(.caption)
                        .foregroundColor(.purple)
                }

                if let date = result.modifiedAt {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let snippet = result.snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var addToQueueButton: some View {
        Button(action: toggleInQueue) {
            Image(systemName: isInQueue ? "checkmark.circle.fill" : "plus.circle")
                .foregroundColor(isInQueue ? .green : .accentColor)
        }
        .buttonStyle(.plain)
        .help(isInQueue ? "Remove from export queue" : "Add to export queue")
    }

    private func toggleInQueue() {
        if isInQueue {
            exportViewModel.removeFromQueue(id: result.id)
        } else {
            exportViewModel.addToQueue(result)
        }
    }
}

struct SourceBadge: View {
    let source: SearchSource

    var color: Color {
        switch source {
        case .basic: return .blue
        case .fts: return .green
        case .semantic: return .purple
        case .multiple: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: source.icon)
                .font(.caption2)
            Text(source.rawValue)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(4)
    }
}

// MARK: - Note Preview

struct NotePreviewView: View {
    let note: NoteContent
    @EnvironmentObject var viewModel: SearchViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with actions
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        if let folder = note.folder {
                            Label(folder, systemImage: "folder")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let modified = note.modifiedAt {
                            Label {
                                Text(modified, style: .date)
                            } icon: {
                                Image(systemName: "clock")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: 8) {
                    Button(action: { viewModel.openInNotesApp() }) {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }

                    Menu {
                        Button("Copy Content") { viewModel.copyNoteContent() }
                        Button("Copy ID") { viewModel.copyNoteID() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content - use HTML if available
            if let html = note.htmlContent {
                HTMLView(html: html, darkMode: colorScheme == .dark)
            } else {
                ScrollView {
                    Text(note.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }

            // Footer with metadata
            if !note.hashtags.isEmpty || !note.attachments.isEmpty {
                Divider()
                HStack {
                    if !note.hashtags.isEmpty {
                        ForEach(note.hashtags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }

                    Spacer()

                    if !note.attachments.isEmpty {
                        Label("\(note.attachments.count) attachment(s)", systemImage: "paperclip")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - HTML View (WKWebView wrapper)

struct HTMLView: NSViewRepresentable {
    let html: String
    let darkMode: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Update HTML with correct dark mode setting
        let updatedHTML = updateHTMLForDarkMode(html, darkMode: darkMode)
        webView.loadHTMLString(updatedHTML, baseURL: nil)
    }

    private func updateHTMLForDarkMode(_ html: String, darkMode: Bool) -> String {
        // If the HTML already has the correct mode, return as-is
        // Otherwise, regenerate with correct colors
        let bgColor = darkMode ? "#1e1e1e" : "#ffffff"
        let textColor = darkMode ? "#e0e0e0" : "#1d1d1f"
        let codeBackground = darkMode ? "#2d2d2d" : "#f5f5f7"

        var result = html
        // Quick replacement of color values
        if darkMode {
            result = result
                .replacingOccurrences(of: "background-color: #ffffff", with: "background-color: #1e1e1e")
                .replacingOccurrences(of: "color: #1d1d1f", with: "color: #e0e0e0")
                .replacingOccurrences(of: "background-color: #f5f5f7", with: "background-color: #2d2d2d")
        }
        return result
    }
}

// MARK: - Permission View

struct PermissionView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            Text("Full Disk Access Required")
                .font(.title)
                .fontWeight(.semibold)

            Text("Notes Search needs Full Disk Access to read your Apple Notes database.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("To grant access:")
                    .fontWeight(.medium)
                Text("1. Open System Settings")
                Text("2. Go to Privacy & Security > Full Disk Access")
                Text("3. Click '+' and add Notes Search")
                Text("4. Restart the app")
            }
            .font(.callout)

            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Keyboard Handler

struct KeyboardHandler: NSViewRepresentable {
    let onArrowDown: () -> Void
    let onArrowUp: () -> Void
    let onEnter: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyboardHandlerView {
        let view = KeyboardHandlerView()
        view.onArrowDown = onArrowDown
        view.onArrowUp = onArrowUp
        view.onEnter = onEnter
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: KeyboardHandlerView, context: Context) {
        nsView.onArrowDown = onArrowDown
        nsView.onArrowUp = onArrowUp
        nsView.onEnter = onEnter
        nsView.onEscape = onEscape
    }
}

class KeyboardHandlerView: NSView {
    var onArrowDown: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onEnter: (() -> Void)?
    var onEscape: (() -> Void)?

    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil && monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                return self?.handleKeyEvent(event)
            }
        }
    }

    override func removeFromSuperview() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        super.removeFromSuperview()
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        // Don't intercept if a text field is focused (let typing work)
        if let firstResponder = window?.firstResponder,
           firstResponder is NSTextView || firstResponder is NSTextField {
            // Only handle Escape in text fields
            if event.keyCode == 53 { // Escape
                onEscape?()
                return nil
            }
            // Let all other keys pass through to the text field
            return event
        }

        switch event.keyCode {
        case 125: // Down arrow
            onArrowDown?()
            return nil
        case 126: // Up arrow
            onArrowUp?()
            return nil
        case 36: // Return/Enter
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                onEnter?()
                return nil
            }
        case 53: // Escape
            onEscape?()
            return nil
        default:
            break
        }
        return event
    }

    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// Preview not available in SPM builds
// Use Xcode project for previews
