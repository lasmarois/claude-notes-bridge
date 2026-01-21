# Goal-13: Import/Export (M10)

## Objective
Add import/export capabilities for notes in Markdown and JSON formats.

## Design Decisions (from brainstorming)

### Use Cases
All of: Backup, Migration, Automation, Sharing

### Markdown Format
- Standard CommonMark for maximum compatibility
- Extensible design for future app-specific formats (Obsidian, Bear)
- YAML frontmatter for metadata (round-trip compatible)

### Conflict Handling
- Interactive prompt by default (`--on-conflict ask`)
- Options: skip, replace, duplicate, ask
- Bulk decisions: all-skip, all-replace during prompts

### Attachments
- Hybrid directory structure (Option C)
- Optional via `--no-attachments` flag
- Structure:
  ```
  export/
  ├── Folder Name/
  │   └── Note Title.md
  └── attachments/
      └── Folder Name/
          └── Note Title/
              └── image.png
  ```

### JSON Export
- Configurable: minimal by default
- Flags: `--include-html`, `--full`

### CLI Style
- Subcommands: `export`, `import`

---

## Phases

### Phase 1: Export Infrastructure ✅
- [x] Create `Sources/NotesLib/Export/` directory
- [x] `NoteFormatter` protocol (pluggable formatters)
- [x] `MarkdownFormatter` - StyledNoteContent → Markdown
- [x] `JSONFormatter` - NoteContent → JSON
- [x] `NotesExporter` - orchestrates export

### Phase 2: Export CLI ✅
- [x] Add `Export` subcommand to main.swift
- [x] Single note export (stdout or file)
- [x] Format selection: `--format md|json`
- [x] JSON options: `--include-html`, `--full`
- [x] Markdown options: `--no-frontmatter`

### Phase 3: Batch Export ✅
- [x] `--folder <name>` - export all notes in folder
- [x] `--all` - export all notes
- [x] `-o <directory>` - output directory
- [x] `--no-attachments` - skip attachment copying
- [x] Preserve folder structure

### Phase 4: Import Infrastructure ✅
- [x] Create `Sources/NotesLib/Import/` directory
- [x] `FrontmatterParser` - extract YAML metadata
- [x] `NotesImporter` - file → AppleScript create
- [x] Conflict detection and resolution

### Phase 5: Import CLI ✅
- [x] Add `Import` subcommand
- [x] Single file: `import note.md`
- [x] `--folder <name>` - target folder
- [x] `--on-conflict` - skip|replace|duplicate|ask
- [x] `--dry-run` - preview without executing

### Phase 6: Batch Import ✅
- [x] `--dir <path>` - import directory
- [x] Create folders matching structure
- [x] Interactive conflict resolution

### Phase 7: Tests ✅
- [x] MarkdownFormatter unit tests
- [x] FrontmatterParser unit tests
- [x] Export → Import round-trip test
- [x] ExportOptions and ImportOptions tests

---

## CLI Commands

### Export
```bash
# Single note
notes-bridge export <note-id> --format md              # stdout
notes-bridge export <note-id> --format md -o note.md   # file
notes-bridge export <note-id> --format json --full     # full JSON

# Batch
notes-bridge export --folder "Work" -o ./backup/
notes-bridge export --all -o ./backup/ --no-attachments
```

### Import
```bash
# Single file
notes-bridge import note.md --folder "Work"

# Batch
notes-bridge import --dir ./notes/ --folder "Imported"
notes-bridge import --dir ./notes/ --on-conflict skip
```

---

## Architecture

```
NotesLib/
├── Export/
│   ├── NotesExporter.swift       # Core export logic
│   ├── NoteFormatter.swift       # Protocol
│   ├── MarkdownFormatter.swift   # StyledNoteContent → Markdown
│   └── JSONFormatter.swift       # NoteContent → JSON
└── Import/
    ├── NotesImporter.swift       # Core import logic
    └── FrontmatterParser.swift   # YAML extraction
```

### Key Design: NoteFormatter Protocol
```swift
protocol NoteFormatter {
    func format(_ note: NoteContent, options: ExportOptions) throws -> String
}
```
Allows future Obsidian/Bear formatters without changing core logic.

---

## Codebase Notes

- **Existing MarkdownConverter**: Converts Markdown → HTML (for import)
- **CLI structure**: All commands in `main.swift`, uses ArgumentParser
- **StyledNoteContent**: Has structured text/attributeRuns/tables (good for export)
- **readNote()**: Returns `htmlContent` and plain `content`
