# Goal 8: Findings

## Tools Inventory

### MCP Tools to Test
| Tool | Parameters | Returns |
|------|------------|---------|
| `list_notes` | limit?, folder? | Array of note summaries |
| `read_note` | id, format? | Note content + metadata |
| `search_notes` | query, limit? | Matching notes |
| `create_note` | title, body, folder? | Created note ID |
| `update_note` | id, title?, body? | Success confirmation |
| `delete_note` | id | Success confirmation |
| `list_folders` | - | Array of folders |
| `create_folder` | name, parent? | Created folder name |
| `move_note` | id, folder | Success confirmation |
| `rename_folder` | name, newName | Success confirmation |
| `delete_folder` | name | Success confirmation |
| `list_hashtags` | - | Array of hashtags |
| `search_by_hashtag` | tag, limit? | Matching notes |
| `list_note_links` | - | Array of note links |
| `get_attachment` | noteId, index? | Attachment metadata/path |
| `add_attachment` | noteId, filePath | Success confirmation |

## Test Framework Research
TBD
