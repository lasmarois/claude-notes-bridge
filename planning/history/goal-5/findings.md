# Goal 5: Findings

## AppleScript Folder Operations

### Tested Capabilities (2026-01-19)

| Operation | Works? | AppleScript |
|-----------|--------|-------------|
| Create folder | ✅ | `make new folder with properties {name:"..."}` |
| Move note | ✅ | `move theNote to targetFolder` |
| Rename folder | ✅ | `set name of folder to "..."` |
| Delete folder | ✅ | `delete folder "..."` |
| Nested folders | ✅ | `tell parentFolder to make new folder...` |

### Key Findings

1. **All folder operations supported via AppleScript**
2. **Nested folders work** - can create folders inside folders
3. **Delete requires empty folder** - must delete notes first (or they move to Recently Deleted)
4. **Move note** - uses `move` command, simple and reliable

### AppleScript Examples

```applescript
-- Create folder
make new folder with properties {name:"My Folder"}

-- Move note to folder
set theNote to note id "x-coredata://..."
move theNote to folder "Target Folder"

-- Rename folder
set name of folder "Old Name" to "New Name"

-- Delete folder (must be empty or notes go to trash)
delete folder "Folder Name"

-- Create nested folder
tell folder "Parent"
    make new folder with properties {name:"Child"}
end tell
```
