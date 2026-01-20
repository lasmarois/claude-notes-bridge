# Goal-12: Findings

## SwiftUI macOS App Structure

### Package.swift App Target
```swift
.executableTarget(
    name: "NotesSearch",
    dependencies: ["NotesLib"],
    path: "Sources/NotesSearch"
)
```

### Basic App Structure
```swift
@main
struct NotesSearchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
```

### Search Debouncing
```swift
.onChange(of: searchText) { _, newValue in
    searchTask?.cancel()
    searchTask = Task {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        await performSearch(newValue)
    }
}
```

### Opening Notes in Notes.app
```swift
// Using AppleScript or URL scheme
NSWorkspace.shared.open(URL(string: "notes://showNote?identifier=\(noteId)")!)

// Or AppleScript for reliability
let script = "tell application \"Notes\" to show note id \"\(noteId)\""
```

## UI Patterns

### Split View
```swift
NavigationSplitView {
    // Sidebar with results
    ResultsList(results: viewModel.results, selection: $selection)
} detail: {
    // Detail pane with preview
    if let note = selection {
        NotePreview(note: note)
    } else {
        Text("Select a note")
    }
}
```

### Search Modes
- **Basic**: Title/snippet search (instant)
- **FTS**: Full-text search with snippets (fast, needs index)
- **Semantic**: AI-powered similarity (slower, ~1-2s)

## Keyboard Shortcuts
| Shortcut | Action |
|----------|--------|
| ⌘F | Focus search bar |
| ↑/↓ | Navigate results |
| ⏎ | Open in Notes.app |
| ⌘C | Copy note content |
| ⎋ | Clear search |
