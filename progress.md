# Goal 7: Progress Log

## Session: 2026-01-19

### Phase 1-4: Research & Testing
- **Status:** complete
- **Started:** 2026-01-19
- Created test notes with various formatting (bold, italic, colors, fonts, emojis)
- Tested protobuf decoder - extracts plain text only
- Tested AppleScript HTML body - preserves formatting
- Documented supported vs unsupported features (see findings.md)

### Phase 5: Fix Issues & Document
- **Status:** in_progress
- Added `format` parameter to `read_note` tool (plain/html)
- Added `getNoteBody()` to AppleScript.swift
- Added `getNotePK()` to Database.swift
- HTML format returns rich text with formatting preserved
- **Hashtag features added:**
  - `list_hashtags` tool - lists all unique hashtags (55 found in test)
  - `search_by_hashtag` tool - finds notes by tag
  - Hashtags now included in note metadata (extracted from ZSNIPPET)
  - `getHashtags()`, `listHashtags()`, `searchNotesByHashtag()` in Database.swift

### Key Findings
- **Write:** AppleScript HTML body supports most formatting
- **Read (plain):** Protobuf decoder extracts plain text only (fast)
- **Read (html):** AppleScript body returns HTML with formatting (slower)
- **Hashtags:** Read-only - can list, search, extract but cannot create programmatically
- **Note Links:** Read-only - can list and read but cannot create via AppleScript

### Session 2 Progress (2026-01-19)
- Investigated `macnotesapp` and `apple-notes-parser` projects
- Discovered proper embedded objects approach:
  - `ZTYPEUTI1` + `ZALTTEXT` for hashtags
  - `ZTOKENCONTENTIDENTIFIER` for note links
- Updated implementation to use embedded objects table
- Added `list_note_links` tool (found 24 links)
- Added `noteLinks` field to `NoteContent` model
- Note-to-note links now included in `read_note` output
- All hashtag/link features are **read-only** (confirmed limitation)

### Session 3 Progress (2026-01-19)
- Implemented full markdown-to-HTML conversion in AppleScript.swift
- Added support for: headers, bold, italic, strikethrough, code (inline + blocks), bullets, quotes
- Fixed duplicate title issue (Notes shows title automatically)
- Inline code styled with Menlo font + dark red color (#c7254e)
- **3 commits made:**
  - `d606dd3` Fix duplicate title and finalize markdown support
  - `1ba21e8` Add full markdown to HTML conversion for notes
  - `2946e62` Add hashtag and note-link reading support (M6.5)

### Native Styles Investigation (Concluded)
- **Root cause found:** AppleScript sets visual formatting (font size/weight), not semantic `style_type`
- **Why Monospaced works:** Notes.app maps Menlo/Courier fonts to style_type=4 automatically
- **Tested approaches:**
  - Direct protobuf with style_type=1/2/3 → CloudKit sync issues
  - Hybrid (AppleScript + ZDATA update) → Styles not recognized
- **Decision:** Accept as platform limitation, use AppleScript HTML for visual formatting
- Cleaned up test notes

## 5-Question Reboot Check
| Question | Answer |
|----------|--------|
| Where am I? | Phase 5 complete, native styles investigation concluded |
| Where am I going? | Phase 6: Archive goal-7 |
| What's the goal? | Rich text support for Notes.app |
| What have I learned? | Native styles are a platform limitation |
| What have I done? | Markdown-to-HTML conversion working, 3 commits |
