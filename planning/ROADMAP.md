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

### M1: Read-Only MVP `[committed]`
- [ ] Swift package structure
- [ ] SQLite access to NoteStore.sqlite
- [ ] Protobuf decoding (note content)
- [ ] List notes, read single note
- [ ] Full Disk Access permission handling

### M2: MCP Server Integration `[committed]`
- [ ] MCP protocol over stdio (JSON-RPC)
- [ ] Tool definitions: `list_notes`, `read_note`, `search_notes`
- [ ] Integration with Claude Code
- [ ] Basic error handling

### Open Questions (H1)
- How does Notes.app lock the database? Can we read while it's open?
- What's the minimal protobuf subset needed for text notes?

---

## Horizon 2: Write Support (Mid-term)

*Goal: Enable Claude to create and modify notes.*

### M3: Create Notes `[likely]`
- [ ] Protobuf encoding (construct valid note)
- [ ] Insert into ZICNOTEDATA + ZICCLOUDSYNCINGOBJECT
- [ ] Test with "On My Mac" folder (no iCloud)
- [ ] Tool: `create_note`

### M4: iCloud Sync Compatibility `[likely]`
- [ ] Study CloudKit metadata preservation
- [ ] Test create with iCloud-synced folder
- [ ] Handle sync conflicts gracefully

### M5: Update & Delete `[exploratory]`
- [ ] Update existing note content
- [ ] Delete notes safely
- [ ] Folder operations (create, move)
- [ ] Tools: `update_note`, `delete_note`, `move_note`

### Open Questions (H2)
- Can we write to iCloud-synced notes without breaking sync?
- What CloudKit fields must be preserved/updated?
- Does Notes.app detect external DB changes and refresh?

### Pivot Points (H2)
- **If iCloud writes fail:** Fall back to "On My Mac" only, or explore AppleScript hybrid
- **If sync breaks:** May need to trigger Notes.app refresh somehow

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
