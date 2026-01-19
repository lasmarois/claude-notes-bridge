# Claude Notes Bridge

Bridge Claude/LLM to Apple Notes API for reading, updating, and organizing notes.

## Planning Context

@planning/ROADMAP.md
@planning/GOALS.md
@task_plan.md
@progress.md
@findings.md

## Project Workflow

This project uses the `planning-with-files` skill for goal-based planning.

### Structure

```
planning/
├── GOALS.md           # Goals registry (single source of truth)
├── history/goal-#/    # Completed goals' planning files
└── iced/goal-#/       # Paused goals' planning files

Root planning files (task_plan.md, progress.md, findings.md) = current goal ONLY
```

### Goals Registry Rules

- Only ONE goal can be `in_progress` at a time
- GOALS.md contains the registry table tracking all goals and their status
- Statuses: `in_progress` | `iced` | `completed`

### File Lifecycle

| Action | What happens |
|--------|--------------|
| Complete goal | Move planning files + deliverables to `planning/history/goal-#/` |
| Ice goal | Move planning files + deliverables to `planning/iced/goal-#/` |
| Resume iced goal | Move files from `planning/iced/goal-#/` back to root |

### Naming Conventions

- Future goal specs: `ISSUE-descr-goal-#.md` (e.g., `ISSUE-add-folder-sync-goal-2.md`)
- Goal deliverables: `DELIVERABLE-DESCR-GOAL-#.md` (e.g., `DELIVERABLE-API-SPEC-GOAL-1.md`)
- These files are archived/iced with their associated goal
