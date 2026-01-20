# Goal-11: CLI Interface

## Objective
Replace ad-hoc argument handling with a proper CLI using Swift Argument Parser. Add subcommands for common operations, helpful error messages, and scripting support.

## Current Phase
Phase 1-3 COMPLETE

## Phases

### Phase 1: Swift Argument Parser Setup
- [x] Add swift-argument-parser dependency to Package.swift
- [x] Create root command structure
- [x] Migrate `--help` and `--version` to ArgumentParser
- [x] Remove old ad-hoc argument handling
- **Status:** complete

### Phase 2: Subcommands
- [x] `serve` - Start MCP server (default behavior)
- [x] `search <query>` - Search notes from CLI (with --semantic, --fts, --fuzzy, --content)
- [x] `list [--folder]` - List notes
- [x] `read <id>` - Read a note (with --json)
- [x] `folders` - List folders
- **Status:** complete

### Phase 3: Error Handling & UX
- [x] Graceful Full Disk Access error with instructions
- [x] Colored terminal output (titles, errors, success)
- [x] Proper exit codes (0=success, 1=error, 2=permission, 3=not found)
- [ ] Progress indicators for slow operations (deferred)
- **Status:** complete

### Phase 4: Export/Import Subcommands (Preview for M10)
- [ ] `export <id> [--format md|json]` - Export single note
- [ ] `export --folder <name> --output <dir>` - Batch export
- [ ] `import <file>` - Import from Markdown
- **Status:** pending

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Use swift-argument-parser | Industry standard, declarative, auto-generates help |
| `serve` as default | Backward compatible with existing MCP usage |
| Keep test commands internal | Use `--test-*` flags only in debug builds |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
