# Goal 5: M5 - Folder Operations

## Objective
Enable folder management and note organization via MCP tools.

## Current Phase
Phase 1 (Research)

## Phases

### Phase 1: Research AppleScript Folder Capabilities
- [x] Test create folder via AppleScript
- [x] Test move note to folder via AppleScript
- [x] Test rename folder via AppleScript
- [x] Test delete folder via AppleScript
- [x] Document available operations
- **Status:** complete

### Phase 2: Implement Folder Tools
- [x] Add `create_folder` MCP tool
- [x] Add `move_note` MCP tool
- [x] Add `rename_folder` MCP tool
- [x] Add `delete_folder` MCP tool
- **Status:** complete

### Phase 3: Test & Verify
- [x] Test all folder operations via MCP
- [x] Verify notes moved correctly
- [x] Test nested folders (supported!)
- **Status:** complete

### Phase 4: Archive Goal
- [ ] Update ROADMAP.md
- [ ] Move files to planning/history/goal-5/
- [ ] Commit
- **Status:** in_progress

## Open Questions — ANSWERED
1. Does AppleScript support nested folders? → **YES**
2. Can we rename folders? → **YES**
3. What happens when deleting a folder with notes? → **Notes move to Recently Deleted**

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Use AppleScript for writes | Consistent with goal-4 architecture |
| DB for folder listing | Fast reads |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
