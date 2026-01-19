# Task Plan: M1 Read-Only MVP

## Goal
Build a working Swift MCP server that can read Apple Notes from the database and expose them to Claude.

## Current Phase
Phase 6 (Integration Test)

## Phases

### Phase 1: Swift Package Setup
- [x] Create Package.swift with targets
- [x] Set up directory structure (Sources/, Proto/)
- [x] Add swift-protobuf dependency
- [x] Create Makefile for build/sign/notarize
- [x] Verify build works
- **Status:** complete

### Phase 2: Protobuf Schema
- [x] Manual protobuf parser (skipped swift-protobuf codegen for simplicity)
- [x] Parse NoteStoreProto.Document.Note.note_text
- **Status:** complete (manual parser)

### Phase 3: SQLite Database Access
- [x] Implement database connection (system libsqlite3)
- [x] Query ZICCLOUDSYNCINGOBJECT for note metadata
- [x] Query ZICNOTEDATA for note content
- [x] Handle Full Disk Access permission check
- **Status:** complete

### Phase 4: Note Decoding
- [x] Decompress gzipped ZDATA blob
- [x] Decode protobuf to extract note text
- [ ] Parse AttributeRuns for basic formatting (deferred)
- [x] Build Note model with content + metadata
- **Status:** complete (basic)

### Phase 5: MCP Server
- [x] Implement JSON-RPC over stdio
- [x] Define tools: list_notes, read_note, search_notes
- [x] Handle MCP protocol (initialize, tools/list, tools/call)
- [x] Error handling and responses
- **Status:** complete

### Phase 6: Integration Test
- [x] Grant Full Disk Access to binary
- [x] Test list_notes with real Notes database
- [x] Test read_note content extraction
- [x] Test search_notes
- [ ] Configure in Claude Code (optional, works standalone)
- **Status:** complete

### Phase 7: Archive Goal
- [ ] Update ROADMAP.md (check off M1 items)
- [ ] Move files to planning/history/goal-3/
- [ ] Commit
- **Status:** pending

## Key Questions
1. What's the minimal protobuf subset needed for text notes?
2. Can we read the DB while Notes.app is open?
3. How to handle notes without FDA permission gracefully?

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| | |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| | | |

## Notes
- Start simple: text notes only, no attachments yet
- Test with "On My Mac" notes first
- Keep MCP server minimal but functional
