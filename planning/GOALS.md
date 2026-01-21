# Goals Registry

Single source of truth for project goals. Only ONE goal can be `in_progress` at a time.

## Registry

| Goal | Description | Status |
|------|-------------|--------|
| goal-1 | Research Apple Notes integrability and options | `completed` |
| goal-2 | Define flexible roadmap and integrate into project memory | `completed` |
| goal-3 | M1: Read-Only MVP (Swift scaffolding, SQLite, protobuf, MCP) | `completed` |
| goal-4 | M3+M4: Full CRUD via AppleScript (create, update, delete notes) | `completed` |
| goal-5 | M5: Folder operations (create, move, rename, delete folders) | `completed` |
| goal-6 | M6: Attachments (read metadata, extract content, create with attachments) | `completed` |
| goal-7 | M6.5: Rich Text Support (typography, fonts, colors, emojis, links, tags, tables) | `completed` |
| goal-8 | M6.6: Integration Testing (end-to-end tests, edge cases, round-trips, tables) | `completed` |
| goal-9 | M7: Enhanced Search (fuzzy, multi-term, context search, filters) | `completed` |
| goal-10 | Testing: Unit and integration tests for search features | `completed` |
| goal-11 | M8: CLI Interface (help, version, subcommands, errors) | `completed` |
| goal-12 | M9: Search UI (SwiftUI app for visual note search) | `completed` |
| goal-13 | M10: Import/Export (Markdown, JSON, batch operations) | `completed` |
| goal-14 | M10.5: Import/Export UI (Search UI integration with queue workflow) | `in_progress` |

## Status Legend

- `in_progress` — Currently active goal (planning files at project root)
- `iced` — Paused goal (planning files in `planning/iced/goal-#/`)
- `completed` — Archived goal (planning files in `planning/history/goal-#/`)

## Workflow Checklist

### Starting a new goal
1. Add goal to registry with `in_progress` status
2. Create `task_plan.md`, `progress.md`, `findings.md` at project root
3. Work using planning-with-files workflow

### Completing a goal
1. Move planning files + deliverables to `planning/history/goal-#/`
2. Update registry status to `completed`

### Icing a goal
1. Move planning files + deliverables to `planning/iced/goal-#/`
2. Update registry status to `iced`

### Resuming an iced goal
1. Move files from `planning/iced/goal-#/` back to project root
2. Update registry status to `in_progress`
