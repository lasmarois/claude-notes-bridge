# Goal-12: Search UI (M9)

## Objective
Create a SwiftUI macOS app for visually searching Apple Notes with real-time results, note preview, and the ability to open notes in Notes.app.

## Current Phase
Phase 1-3 COMPLETE, Phase 4 in progress

## Phases

### Phase 1: Project Setup
- [x] Add new macOS app target to Package.swift
- [x] Create basic SwiftUI app structure
- [ ] Set up app icon and metadata (deferred)
- [x] Configure entitlements (Full Disk Access check)
- **Status:** complete

### Phase 2: Search Interface
- [x] Search bar with debounced input
- [x] Search mode selector (basic, FTS, semantic)
- [x] Results list with note title, folder, date
- [x] Loading indicator for semantic search
- **Status:** complete

### Phase 3: Note Preview
- [x] Split view: results | preview
- [x] Render note content (plain text)
- [x] Show metadata (folder, dates, hashtags)
- [ ] Syntax highlighting for code blocks (deferred)
- **Status:** complete

### Phase 4: Actions & Polish
- [x] "Open in Notes.app" button
- [x] Copy note ID/content
- [ ] Keyboard navigation (up/down arrows, enter)
- [ ] Remember window position/size
- [x] Dark mode support (automatic via SwiftUI)
- **Status:** in progress

## Architecture

```
NotesSearchApp/
├── NotesSearchApp.swift      # @main App
├── ContentView.swift         # Main split view
├── SearchBar.swift           # Search input + mode
├── ResultsList.swift         # List of search results
├── NotePreview.swift         # Note content preview
├── SearchViewModel.swift     # Business logic
└── Models.swift              # View-specific models
```

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Separate app target | Keep MCP server and UI independent |
| SwiftUI | Modern, declarative, native macOS feel |
| Split view | Standard macOS pattern for search apps |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
