# Findings - Goal-13 (M10: Import/Export)

## Codebase Analysis

### Existing Infrastructure

**MarkdownConverter** (`Sources/NotesLib/Notes/MarkdownConverter.swift`)
- Converts Markdown → HTML for note creation
- Handles: code blocks, inline code, bold, italic, strikethrough, headers, lists, blockquotes, tables
- Uses special markers (⟦CODE⟧, ⟦TABLE⟧) during processing
- **Useful for import** - already handles markdown parsing

**StyledNoteContent** (`Sources/NotesLib/Notes/Decoder.swift`)
- Structured representation: `text`, `attributeRuns`, `tables`
- `attributeRuns` has style types: title, heading, body, monospaced, bulletList, etc.
- `tables` has rows/cells with text content
- **Useful for export** - structured data easier than parsing HTML

**CLI Structure** (`Sources/claude-notes-bridge/main.swift`)
- Uses ArgumentParser
- All commands in single file
- Existing: Serve, Search, List, Read, Folders
- Pattern to follow for Export/Import commands

**NoteContent** (returned by `readNote()`)
- `id`, `title`, `content` (plain text), `htmlContent`
- `folder`, `createdAt`, `modifiedAt`
- `attachments`: array with id, filename, contentType, size
- `hashtags`, `noteLinks`

### Export Strategy

**For Markdown export:**
- Use `StyledNoteContent` from `decoder.decodeStyled()`
- Map `NoteStyleType` → Markdown syntax:
  - `.title` → `# ` (first line only)
  - `.heading` → `## `
  - `.subheading` → `### `
  - `.monospaced` → ``` ``` ``` blocks
  - `.bulletList` → `- `
  - `.numberedList` → `1. `
  - `.checkbox` → `- [ ] `
  - `.checkboxChecked` → `- [x] `
- Convert `NoteTable` → Markdown table syntax

**For JSON export:**
- Use `NoteContent` from `readNote()`
- Serialize with Codable
- Filter fields based on options

### Import Strategy

**For Markdown import:**
1. Parse YAML frontmatter (if present)
2. Extract title from frontmatter, `# heading`, or filename
3. Use existing `MarkdownConverter` for body → HTML
4. Call `AppleScript.createNote()` with HTML body

**Conflict Detection:**
- Query `database.searchNotes(query: title, folder: folder)`
- Check for exact title match in target folder

### Attachment Handling

**On Export:**
- `NoteContent.attachments` has metadata
- Need to call `fetchAttachmentPath()` to get actual file location
- Copy from Notes library to export directory

**On Import:**
- `AppleScript.addAttachment()` exists
- Would need to import note first, then add attachments

## Technical Decisions

### Frontmatter Format
```yaml
---
title: Note Title
folder: Folder/Subfolder
created: 2024-01-20T10:00:00Z
modified: 2024-01-20T12:00:00Z
tags: [tag1, tag2]
---
```

### Safe Filename Generation
- Replace `/` with `-`
- Replace `:` with `-`
- Remove `"`, `<`, `>`, `|`, `?`, `*`
- Truncate to 255 chars
- Handle duplicates with `(1)`, `(2)` suffix

### Markdown Table Format
```markdown
| Header 1 | Header 2 |
|----------|----------|
| Cell 1   | Cell 2   |
```
