# Goal-11: CLI Interface

## Objective
Replace ad-hoc argument handling with a proper CLI using Swift Argument Parser. Add subcommands for common operations, helpful error messages, and scripting support.

## Current Phase
Phase 1 (Swift Argument Parser Setup)

## Phases

### Phase 1: Swift Argument Parser Setup
- [ ] Add swift-argument-parser dependency to Package.swift
- [ ] Create root command structure
- [ ] Migrate `--help` and `--version` to ArgumentParser
- [ ] Remove old ad-hoc argument handling
- **Status:** pending

### Phase 2: Subcommands
- [ ] `serve` - Start MCP server (default behavior)
- [ ] `search <query>` - Search notes from CLI
- [ ] `list [--folder]` - List notes
- [ ] `read <id>` - Read a note
- [ ] `folders` - List folders
- **Status:** pending

### Phase 3: Error Handling & UX
- [ ] Graceful Full Disk Access error with instructions
- [ ] Colored terminal output (titles, errors, success)
- [ ] Proper exit codes (0=success, 1=error, 2=permission)
- [ ] Progress indicators for slow operations
- **Status:** pending

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
