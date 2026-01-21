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

### Phase 1: Export Queue Infrastructure
- [ ] Create `ExportViewModel.swift` with queue state management
- [ ] Add `exportQueue` property and methods to manage queue
- [ ] Integrate with existing `NotesExporter`
- [ ] Add "add to queue" methods callable from SearchViewModel

### Phase 2: Import Staging Infrastructure
- [ ] Create `ImportViewModel.swift` with staging state management
- [ ] Add file/folder picker integration
- [ ] Conflict detection on file add
- [ ] Integrate with existing `NotesImporter`

### Phase 3: Panel UI - Shell
- [ ] Create `ImportExportPanel.swift` with tab switching
- [ ] Add panel to ContentView (collapsible right sidebar)
- [ ] Panel open/close animation
- [ ] Tab state management (Export vs Import)

### Phase 4: Export Tab UI
- [ ] Create `ExportTab.swift`
- [ ] Queue list view (grouped by folder, collapsible)
- [ ] Checkbox selection and remove buttons
- [ ] Export options (format, frontmatter, attachments)
- [ ] Location picker integration
- [ ] Export button and progress display

### Phase 5: Import Tab UI
- [ ] Create `ImportTab.swift`
- [ ] Staging list view with conflict indicators
- [ ] File/folder picker buttons
- [ ] Drag and drop support
- [ ] Import options (default folder, conflict handling)
- [ ] Import button and progress display

### Phase 6: Search Integration
- [ ] Add "+" button to search result rows
- [ ] Multi-select support (Cmd+click, Shift+click)
- [ ] "Add Selected" and "Add All Results" buttons
- [ ] Update SearchViewModel with queue integration

### Phase 7: Toolbar & Menu
- [ ] Add Export/Import buttons to toolbar
- [ ] Badge showing queue count on Export button
- [ ] File menu items (Export..., Import..., Add to Export, Add All)
- [ ] Keyboard shortcuts (⌘E, ⌘I, ⌘⇧E, ⌘⌥E)

### Phase 8: Progress & Feedback
- [ ] Progress bar component with percentage and current item
- [ ] Cancel button during operations
- [ ] Success/failure completion views
- [ ] "Open in Finder" and "Clear Queue" actions
- [ ] Error summary with retry option

### Phase 9: Polish & Edge Cases
- [ ] Duplicate detection when adding to queue
- [ ] Empty queue state handling
- [ ] Panel close confirmation during operation
- [ ] Long title truncation
- [ ] Keyboard navigation in queue/staging lists

### Phase 10: Testing
- [ ] ExportViewModel unit tests
- [ ] ImportViewModel unit tests
- [ ] Integration tests for full workflow
- [ ] Manual UI testing

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
