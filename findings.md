# Findings - Goal-14 (M10.5: Import/Export UI)

## Existing Infrastructure

### Search UI Structure (from Goal-12)

**Files:**
- `NotesSearchApp.swift` - App entry, window setup
- `ContentView.swift` - Main UI with NavigationSplitView
- `SearchViewModel.swift` - Search state and logic

**Current Layout:**
```
NavigationSplitView
├── Sidebar: SearchBarView + ResultsListView
└── Detail: NotePreviewView
```

**Key Components:**
- `SearchResult` - Model for search results
- `ResultRowView` - Individual result row
- `NotePreviewView` - Preview with actions menu

### Import/Export Infrastructure (from Goal-13)

**Export:**
- `NotesExporter` - Orchestrates export operations
- `MarkdownFormatter` - Converts notes to Markdown
- `JSONFormatter` - Converts notes to JSON
- `ExportOptions` - Configuration for export
- `ExportResult` - Result with success/failure info

**Import:**
- `NotesImporter` - Orchestrates import operations
- `FrontmatterParser` - Parses YAML frontmatter
- `ImportOptions` - Configuration for import
- `ImportResult` - Result with imported/skipped/failed
- `ConflictStrategy` - skip/replace/duplicate/ask

## SwiftUI Patterns to Use

### Sidebar Panel
```swift
// Use GeometryReader or fixed width
HStack(spacing: 0) {
    // Existing content
    existingContent

    // Collapsible panel
    if showPanel {
        ImportExportPanel()
            .frame(width: 300)
            .transition(.move(edge: .trailing))
    }
}
.animation(.easeInOut(duration: 0.25), value: showPanel)
```

### Tab View in Panel
```swift
TabView(selection: $selectedTab) {
    ExportTab()
        .tag(Tab.export)
    ImportTab()
        .tag(Tab.import)
}
.tabViewStyle(.automatic)
```

### Progress View
```swift
VStack {
    ProgressView(value: progress, total: 1.0)
    Text("\(currentItem) of \(totalItems)")
}
```

### File Picker
```swift
// For import
let panel = NSOpenPanel()
panel.allowsMultipleSelection = true
panel.allowedContentTypes = [.plainText, .json]
panel.canChooseDirectories = true

// For export location
let panel = NSOpenPanel()
panel.canChooseFiles = false
panel.canChooseDirectories = true
```

## State Management Approach

### ExportViewModel
```swift
@MainActor
class ExportViewModel: ObservableObject {
    @Published var queue: [ExportQueueItem] = []
    @Published var isExporting = false
    @Published var progress: Double = 0
    @Published var currentItem: String = ""
    @Published var exportResult: ExportResult?

    // Options
    @Published var format: ExportFormat = .markdown
    @Published var includeFrontmatter = true
    @Published var includeAttachments = false
    @Published var outputURL: URL?

    private let exporter: NotesExporter

    func addToQueue(_ result: SearchResult) { }
    func addAllToQueue(_ results: [SearchResult]) { }
    func removeFromQueue(_ item: ExportQueueItem) { }
    func clearQueue() { }
    func export() async { }
    func cancelExport() { }
}
```

### ImportViewModel
```swift
@MainActor
class ImportViewModel: ObservableObject {
    @Published var staging: [ImportStagingItem] = []
    @Published var isImporting = false
    @Published var progress: Double = 0
    @Published var currentItem: String = ""
    @Published var importResult: ImportResult?

    // Options
    @Published var defaultFolder: String = "Notes"
    @Published var conflictStrategy: ConflictStrategy = .ask

    private let importer: NotesImporter

    func addFiles(_ urls: [URL]) { }
    func addFolder(_ url: URL) { }
    func removeFromStaging(_ item: ImportStagingItem) { }
    func clearStaging() { }
    func detectConflicts() { }
    func importAll() async { }
    func cancelImport() { }
}
```

## Keyboard Shortcuts

```swift
// In App or Commands
.commands {
    CommandGroup(after: .importExport) {
        Button("Export...") { showExportPanel() }
            .keyboardShortcut("e", modifiers: .command)

        Button("Import...") { showImportPanel() }
            .keyboardShortcut("i", modifiers: .command)

        Divider()

        Button("Add to Export") { addSelectedToQueue() }
            .keyboardShortcut("e", modifiers: [.command, .shift])

        Button("Add All to Export") { addAllToQueue() }
            .keyboardShortcut("e", modifiers: [.command, .option])
    }
}
```

## Badge on Button

```swift
Button {
    toggleExportPanel()
} label: {
    HStack(spacing: 4) {
        Text("Export")
        if !exportQueue.isEmpty {
            Text("(\(exportQueue.count))")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(Capsule())
        }
    }
}
```
