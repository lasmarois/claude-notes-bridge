# Goal-14: Import/Export UI (M10.5)

## Objective
Integrate import/export capabilities into the Search UI with a queue-based workflow.

## Design Reference
See: `docs/plans/2026-01-20-import-export-ui-design.md`

## Key Features
- Export queue ("shopping cart") - build selection over multiple searches
- Import staging area with conflict detection
- Collapsible right sidebar panel with Export/Import tabs
- Progress bar with real-time feedback
- Toolbar buttons with badge, keyboard shortcuts, menu bar items

---

## Phases

### Phase 1: Export Queue Infrastructure ✅
- [x] Create `ExportViewModel.swift` with queue state management
- [x] Add `exportQueue` property and methods to manage queue
- [x] Integrate with existing `NotesExporter`
- [x] Add "add to queue" methods callable from SearchViewModel

### Phase 2: Import Staging Infrastructure ✅
- [x] Create `ImportViewModel.swift` with staging state management
- [x] Add file/folder picker integration
- [x] Conflict detection on file add
- [x] Integrate with existing `NotesImporter`

### Phase 3: Panel UI - Shell ✅
- [x] Create `ImportExportPanel.swift` with tab switching
- [x] Add panel to ContentView (collapsible right sidebar)
- [x] Panel open/close animation
- [x] Tab state management (Export vs Import)

### Phase 4: Export Tab UI ✅
- [x] Create `ExportTab.swift`
- [x] Queue list view (grouped by folder, collapsible)
- [x] Checkbox selection and remove buttons
- [x] Export options (format, frontmatter, attachments)
- [x] Location picker integration
- [x] Export button and progress display

### Phase 5: Import Tab UI ✅
- [x] Create `ImportTab.swift`
- [x] Staging list view with conflict indicators
- [x] File/folder picker buttons
- [x] Drag and drop support
- [x] Import options (default folder, conflict handling)
- [x] Import button and progress display

### Phase 6: Search Integration ✅
- [x] Add "+" button to search result rows
- [x] Multi-select support (Cmd+click, Shift+click) → Simplified to per-row + Add All
- [x] "Add Selected" and "Add All Results" buttons
- [x] Update SearchViewModel with queue integration

### Phase 7: Toolbar & Menu ✅
- [x] Add Export/Import buttons to toolbar
- [x] Badge showing queue count on Export button
- [x] File menu items (Export..., Import..., Add to Export, Add All)
- [x] Keyboard shortcuts (⌘E, ⌘I, ⌘⇧E, ⌘⌥E)

### Phase 8: Progress & Feedback ✅
- [x] Progress bar component with percentage and current item
- [x] Cancel button during operations
- [x] Success/failure completion views
- [x] "Open in Finder" and "Clear Queue" actions
- [x] Error summary with retry option

### Phase 9: Polish & Edge Cases ✅
- [x] Duplicate detection when adding to queue
- [x] Empty queue state handling
- [x] Panel close confirmation during operation
- [x] Long title truncation
- [x] Keyboard navigation in queue/staging lists

### Phase 10: Testing ✅
- [x] ExportViewModel unit tests → Manual testing (executable target)
- [x] ImportViewModel unit tests → Manual testing (executable target)
- [x] Integration tests for full workflow → Manual checklist
- [x] Manual UI testing → Comprehensive checklist created

---

## Architecture

```
Sources/NotesSearch/
├── NotesSearchApp.swift (existing)
├── ContentView.swift (modify - add panel)
├── SearchViewModel.swift (modify - add queue methods)
├── ImportExportPanel.swift (NEW)
├── ExportTab.swift (NEW)
├── ImportTab.swift (NEW)
├── ExportViewModel.swift (NEW)
└── ImportViewModel.swift (NEW)
```

## Dependencies
- NotesExporter (from Goal-13) ✅
- NotesImporter (from Goal-13) ✅
- ExportOptions, ImportOptions (from Goal-13) ✅
