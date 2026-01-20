# Roadmap: Claude Notes Bridge

> A Swift-based MCP server for full Apple Notes integration.

## How to Read This

- **Horizons:** Near → Mid → Far (uncertainty increases)
- **Confidence:** `[committed]` → `[likely]` → `[exploratory]`
- **Open Questions:** Unknowns that may change direction
- **Pivot Points:** Decisions that could alter the path

---

## Horizon 1: Foundation (Near-term)

*Goal: Prove the approach works end-to-end.*

### M1: Read-Only MVP `[committed]` ✅
- [x] Swift package structure
- [x] SQLite access to NoteStore.sqlite
- [x] Protobuf decoding (note content)
- [x] List notes, read single note
- [x] Full Disk Access permission handling

### M2: MCP Server Integration `[committed]` ✅
- [x] MCP protocol over stdio (JSON-RPC)
- [x] Tool definitions: `list_notes`, `read_note`, `search_notes`
- [x] Integration with Claude Code
- [x] Basic error handling

### Open Questions (H1) — ANSWERED
- ~~How does Notes.app lock the database?~~ → Can read while Notes.app is open (read-only mode)
- ~~What's the minimal protobuf subset needed?~~ → Just NoteStoreProto.Document.Note.note_text

---

## Horizon 2: Write Support (Mid-term)

*Goal: Enable Claude to create and modify notes.*

### M3: Create Notes `[committed]` ✅ — PIVOTED TO APPLESCRIPT
- [x] ~~Protobuf encoding~~ → Not needed (AppleScript handles it)
- [x] ~~Direct DB writes~~ → **Failed** (invisible without CloudKit metadata)
- [x] **Pivot:** AppleScript for writes (see goal-4 findings)
- [x] Tool: `create_note` via AppleScript

### M4: Update & Delete `[committed]` ✅
- [x] Tool: `update_note` via AppleScript
- [x] Tool: `delete_note` via AppleScript

### M5: Folder Operations `[committed]` ✅
- [x] Tool: `create_folder` via AppleScript
- [x] Tool: `move_note` via AppleScript
- [x] Tool: `rename_folder` via AppleScript
- [x] Tool: `delete_folder` via AppleScript
- [x] Nested folders supported

### Open Questions (H2) — ANSWERED
- ~~Can we write to iCloud-synced notes without breaking sync?~~ → **YES, via AppleScript** (handles CloudKit automatically)
- ~~What CloudKit fields must be preserved/updated?~~ → **N/A** (AppleScript manages this)
- ~~Does Notes.app detect external DB changes?~~ → **No** (DB-created notes are invisible)

### Key Finding: AppleScript Supports Full CRUD
**Reference:** goal-4/findings.md "CRITICAL DISCOVERY" section

The original goal-1 research incorrectly stated AppleScript couldn't update/delete notes.
**Verified capabilities:**
- Create: `make new note with properties {...}`
- Update: `set body of note id (noteID) to newBody`
- Delete: `delete note`

**Architecture decision:**
- **Reads:** Database (fast, rich metadata)
- **Writes:** AppleScript (handles CloudKit, guaranteed visibility)

---

## Horizon 3: Rich Content & Polish (Far-term)

*Goal: Full Notes.app feature support and production readiness.*

### M6: Attachments `[committed]` ✅
- [x] Read attachment metadata from DB
- [x] Get attachment file path via AppleScript
- [x] Add attachments to notes via AppleScript
- [x] Tools: `get_attachment`, `add_attachment`

### M6.5: Rich Text Support `[committed]` ✅
- [x] Typography: bold, italic, underline, strikethrough
- [x] Headings (visual via HTML, not semantic)
- [x] Lists: bullets (•), numbered
- [x] Fonts: monospace (Menlo) for code
- [x] Text colors: inline code (#C7254E), blockquotes (#666)
- [x] Emojis (preserved on read/write)
- [x] Markdown-to-HTML conversion for create/update
- [x] Hashtags: read-only (list, search, extract)
- [x] Note links: read-only (list, extract)
- [x] **Limitation:** Native paragraph styles (Title/Heading/Subheading in Format menu) cannot be set programmatically

### M6.6: Integration Testing `[committed]` ✅
- [x] End-to-end test suite (Goal-8 + Goal-10)
- [x] Round-trip tests (create → read → update → verify)
- [x] Edge cases: special characters, unicode, large notes
- [x] Table rendering tests
- [x] Search feature unit tests (44 tests)
- [ ] iCloud sync verification (manual only, not automated)

### M7: Enhanced Search `[committed]` ✅
- [x] Case-insensitive search
- [x] Content search (protobuf body decoding)
- [x] Multi-term queries (AND/OR)
- [x] Fuzzy matching (Levenshtein distance)
- [x] Date range and folder filters
- [x] Result snippets with highlights
- [x] FTS5 full-text index (3000x faster)
- [x] Semantic search (MiniLM AI embeddings, Core ML)
- [x] Tools: `search_notes`, `fts_search`, `build_search_index`, `semantic_search`

### M8: CLI Interface `[committed]`
- [ ] `--help` with usage documentation
- [ ] `--version` flag
- [ ] Subcommands: `serve` (MCP), `search`, `list`, `export`, `import`
- [ ] Graceful error messages (e.g., missing Full Disk Access)
- [ ] Colored terminal output
- [ ] Exit codes for scripting

### M9: Search UI `[likely]`
- [ ] SwiftUI app for visual search
- [ ] Real-time search results (FTS + semantic)
- [ ] Preview note content
- [ ] Open note in Notes.app
- [ ] Keyboard navigation

### M10: Import/Export `[likely]`
- [ ] Export notes to Markdown files
- [ ] Export to JSON (structured data)
- [ ] Import from Markdown
- [ ] Batch export (folder or all notes)
- [ ] Preserve folder structure

### M11: Distribution `[exploratory]`
- [ ] Code signing & notarization
- [ ] Homebrew formula
- [ ] GitHub releases with signed binaries
- [ ] User documentation

### M12: Backward Compatibility `[exploratory]`
- [ ] Support macOS 12 (Monterey) — async/await floor
- [ ] Support macOS 10.15-11 — feature flags for async/await
- [ ] Graceful degradation: disable semantic search on older systems
- [ ] `#available` checks for Core ML features
- [ ] Test matrix for supported macOS versions

**Version requirements analysis:**
| Feature | Min macOS |
|---------|-----------|
| Core features (SQLite, FTS5, AppleScript) | 10.12 |
| Core ML semantic search | 10.14 |
| SPM Bundle.module | 10.15 |
| async/await | 12.0 |
| **Current minimum** | **13.0** |

### Open Questions (H3)
- What's the best distribution channel for MCP servers?
- Should we support locked/encrypted notes? (May be impossible)
- What's the oldest macOS version worth supporting? (10.15? 12?)

---

## Out of Scope (For Now)

- iOS support (macOS only)
- Real-time sync (polling or on-demand is fine)
- Note sharing/collaboration features
- Rich text editing UI

---

## Version History

| Date | Change |
|------|--------|
| 2026-01-18 | Initial roadmap based on goal-1 research |
| 2026-01-18 | M1 + M2 complete: Read-only MCP server working |
| 2026-01-18 | **PIVOT:** M3 approach changed from DB writes to AppleScript. Direct DB writes create invisible notes (missing CloudKit metadata). AppleScript confirmed to support full CRUD (corrects goal-1 error). See goal-4/findings.md |
| 2026-01-18 | **M3 + M4 complete:** Full CRUD via hybrid architecture (DB reads + AppleScript writes). Tools: create_note, update_note, delete_note |
| 2026-01-19 | **M5 complete:** Folder operations. Tools: create_folder, move_note, rename_folder, delete_folder |
| 2026-01-19 | Added M6.5 (Rich Text Support) and M6.6 (Integration Testing) milestones between M6 and M7 |
| 2026-01-19 | **M6 complete:** Attachments. Tools: get_attachment, add_attachment. read_note now includes attachment metadata |
| 2026-01-19 | **M6.5 complete:** Rich text support. Markdown-to-HTML conversion, hashtags/links read-only. Native paragraph styles documented as platform limitation. |
| 2026-01-19 | **M7 complete:** Enhanced search. FTS5 index, fuzzy matching, multi-term, filters, semantic search with MiniLM Core ML. |
| 2026-01-19 | Added M10 (Backward Compatibility) for supporting older macOS versions. Renumbered M8→M9 (Distribution). |
| 2026-01-20 | **M6.6 complete:** Integration testing done via Goal-8 (CRUD, edge cases, tables) + Goal-10 (44 search tests). |
| 2026-01-20 | **Roadmap expansion:** Added M8 (CLI Interface), M9 (Search UI), M10 (Import/Export). Renumbered Distribution→M11, Backward Compat→M12. |
