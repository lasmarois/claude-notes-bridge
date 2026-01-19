# Findings: M1 Read-Only MVP

## Requirements
- Swift package with MCP server
- Read notes from NoteStore.sqlite
- Expose via MCP tools: list_notes, read_note, search_notes
- Handle FDA permission gracefully

## Technical References

### From Goal-1 Research
- Database: `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`
- Tables: ZICCLOUDSYNCINGOBJECT (metadata), ZICNOTEDATA (content)
- Format: gzip → protobuf → text + AttributeRuns
- Proto: https://github.com/threeplanetssoftware/apple_cloud_notes_parser/blob/master/proto/notestore.proto

### Swift Dependencies
- SQLite3 (system) - libsqlite3.dylib
- Compression (system) - for gzip
- swift-protobuf - for protobuf decode

## Implementation Notes

### Database Schema (Key Fields)
```sql
-- ZICCLOUDSYNCINGOBJECT
ZIDENTIFIER     -- UUID
ZTITLE1         -- Note title (notes have this, attachments don't)
ZTYPEUTI        -- NULL for notes, set for attachments
ZMODIFICATIONDATE1
ZCREATIONDATE1
ZFOLDER         -- FK to folder (folder has ZTITLE2)

-- ZICNOTEDATA
ZNOTE           -- FK to ZICCLOUDSYNCINGOBJECT.Z_PK
ZDATA           -- gzipped protobuf blob
```

### Key Discovery
- Notes have `ZTYPEUTI = NULL` and `ZTITLE1 IS NOT NULL`
- Attachments have `ZTYPEUTI` set (e.g., 'public.jpeg', 'com.adobe.pdf')
- Query should use `WHERE ZTITLE1 IS NOT NULL` not `WHERE ZTYPEUTI = 'com.apple.notes.note'`

## Resources
- Goal-1 deliverable: planning/history/goal-1/DELIVERABLE-INTEGRATION-OPTIONS-GOAL-1.md
