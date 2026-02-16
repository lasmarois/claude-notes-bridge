# Import/Export UI Manual Testing Checklist

## Prerequisites
- Notes Search app built and running
- Full Disk Access granted
- Apple Notes with at least 3-5 notes in different folders
- Test markdown files for import testing

---

## Export Tab Tests

### Queue Management
- [ ] **Add single note**: Click "+" on a search result → appears in queue
- [ ] **Duplicate prevention**: Click "+" on same note → no duplicate added
- [ ] **Remove from queue**: Click checkmark on queued item → removed
- [ ] **Toggle selection**: Click item checkbox → toggles selected state
- [ ] **Select All**: Menu → Select All → all items selected
- [ ] **Deselect All**: Menu → Deselect All → all items deselected
- [ ] **Clear Queue**: Menu → Clear Queue → queue emptied
- [ ] **Add All Results**: Click "Add All" in results header → all results added

### Queue Display
- [ ] **Empty state**: Shows "Export Queue Empty" with instructions
- [ ] **Grouped by folder**: Notes grouped under folder headers
- [ ] **Badge count**: Toolbar button shows queue count
- [ ] **Tab badge**: Export tab shows queue count

### Export Options
- [ ] **Format: Markdown**: Select Markdown → exports .md files
- [ ] **Format: JSON**: Select JSON → exports .json files
- [ ] **Frontmatter toggle**: Enable → Markdown includes YAML frontmatter
- [ ] **Full metadata toggle**: Enable JSON → includes all metadata
- [ ] **Attachments toggle**: Enable → copies attachments to subfolder
- [ ] **Location picker**: "Choose..." opens folder picker

### Export Execution
- [ ] **Export button disabled**: No items or no location → button disabled
- [ ] **Progress display**: Shows progress bar, current item, count
- [ ] **Cancel export**: Cancel button stops export mid-operation
- [ ] **Success state**: Shows checkmark, count, "Show in Finder" button
- [ ] **Partial failure**: Shows warning, lists failures, "Retry" option
- [ ] **Full failure**: Shows error, "Retry" option

### Keyboard Shortcuts
- [ ] **⌘E**: Opens Export panel
- [ ] **⌘⇧E**: Adds selected note to queue
- [ ] **⌘⌥E**: Adds all results to queue

---

## Import Tab Tests

### Staging Management
- [ ] **Add Files**: "Add Files..." → file picker → files added to staging
- [ ] **Add Folder**: "Add Folder..." → folder picker → all .md files added
- [ ] **Drag and drop files**: Drag .md files onto panel → added to staging
- [ ] **Drag and drop folder**: Drag folder → all .md files added
- [ ] **Remove from staging**: Click X button → item removed
- [ ] **Toggle selection**: Click checkbox → toggles selected state
- [ ] **Clear staging**: Menu → Clear All → staging emptied

### Staging Display
- [ ] **Empty state**: Shows drag zone and picker buttons
- [ ] **Drag hover feedback**: Border highlights when dragging over
- [ ] **Grouped by folder**: Files grouped under target folder headers
- [ ] **Conflict indicators**: Orange triangle on conflicting items
- [ ] **Tab badge**: Import tab shows staging count

### Conflict Detection
- [ ] **Auto-detect**: Conflicts detected when adding files
- [ ] **Refresh conflicts**: Changing default folder re-checks conflicts
- [ ] **Conflict count**: Header shows conflict count

### Import Options
- [ ] **Default folder**: Text field sets target folder
- [ ] **Skip strategy**: Conflicting files skipped
- [ ] **Replace strategy**: Existing notes replaced
- [ ] **Duplicate strategy**: New notes created (may duplicate)

### Import Execution
- [ ] **Import button disabled**: No items → button disabled
- [ ] **Progress display**: Shows progress bar, current item, count
- [ ] **Cancel import**: Cancel button stops import mid-operation
- [ ] **Success state**: Shows checkmark, count, target folder
- [ ] **Partial result**: Shows imported/skipped/failed counts, "Retry" option
- [ ] **Full failure**: Shows error, "Retry" option

### Keyboard Shortcuts
- [ ] **⌘I**: Opens Import panel

---

## Panel Tests

### Panel Display
- [ ] **Toolbar buttons**: Export and Import buttons visible
- [ ] **Open panel**: Click button → panel slides in from right
- [ ] **Close panel**: Click X → panel slides out
- [ ] **Tab switching**: Click tabs → switches between Export/Import

### Operation Protection
- [ ] **Escape key blocked**: During operation, Escape doesn't close
- [ ] **Close confirmation**: Click X during operation → shows alert
- [ ] **Tab switching disabled**: During operation, can't switch tabs
- [ ] **Progress indicator**: Spinner in header during operation

### Animation
- [ ] **Open animation**: Smooth slide + fade in (0.25s)
- [ ] **Close animation**: Smooth slide + fade out (0.25s)

---

## Integration Tests

### Full Export Workflow
1. Search for notes
2. Add several to queue
3. Select export location
4. Choose format and options
5. Export
6. Verify files in Finder
7. Check file contents

### Full Import Workflow
1. Open Import panel
2. Add markdown files
3. Check for conflicts
4. Set options
5. Import
6. Verify notes in Apple Notes

### Round-trip Test
1. Export notes to Markdown
2. Clear queue
3. Import the exported files to different folder
4. Compare original and imported notes

---

## Edge Cases

- [ ] **Very long titles**: Truncated in UI, safe filename generated
- [ ] **Special characters in title**: Handled in filename (/:*?"<>|)
- [ ] **Unicode in content**: Preserved in export/import
- [ ] **Empty notes**: Export/import successfully
- [ ] **Notes with attachments**: Attachments exported when enabled
- [ ] **Large batch (50+ notes)**: Performance acceptable
- [ ] **Network/permission errors**: Graceful error handling

---

## Notes

### Test File Setup
Create test markdown files with:
```markdown
---
title: Test Note
folder: TestFolder
tags: [test, import]
---

# Test Note

This is test content.
```

### Known Limitations
- ViewModels are in executable target (not unit testable without refactor)
- Integration tests require Full Disk Access and real Apple Notes
- Import creates real notes (use test folder, clean up after)
