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

## Horizon 3: Production (Far-term)

*Goal: Polish for real-world use.*

### M6: Attachments `[exploratory]`
- [ ] Read attachment metadata
- [ ] Extract attachment content
- [ ] Create notes with attachments

### M7: Production Readiness `[exploratory]`
- [ ] Code signing & notarization
- [ ] Error handling & logging
- [ ] Performance optimization
- [ ] User documentation

### M8: Distribution `[exploratory]`
- [ ] Homebrew formula or similar
- [ ] GitHub releases with signed binaries

### Open Questions (H3)
- What's the best distribution channel for MCP servers?
- Should we support locked/encrypted notes? (May be impossible)

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
