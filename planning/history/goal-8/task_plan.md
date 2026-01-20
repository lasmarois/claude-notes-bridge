# Goal 8: M6.6 - Integration Testing

## Objective
Build a comprehensive test suite to verify all MCP tools work correctly end-to-end, with proper handling of edge cases.

## Current Phase
Phase 6 (iCloud Sync Verification) - Optional/Manual

## Phases

### Phase 1: Research & Planning
- [x] Audit existing tools and their expected behaviors
- [x] Identify test framework options (XCTest, swift-testing, shell scripts)
- [x] Define test categories and coverage goals
- **Status:** complete

### Phase 2: Basic Tool Tests
- [x] Test `list_notes` (folder filtering)
- [x] Test `read_note` (database and AppleScript HTML)
- [x] Test `search_notes` (query matching)
- [x] Test `create_note` (basic, with markdown)
- [x] Test `update_note` (body, title+body)
- [x] Test `delete_note` (move to Recently Deleted)
- **Status:** complete

### Phase 3: Round-Trip Tests
- [x] Create → Read → Verify content matches
- [x] Create → Update → Read → Verify changes
- [x] Create → Delete → Verify gone
- [x] Create multiple → List → Verify all
- [x] Markdown round-trip with formatting
- [x] Folder operations round-trip (create, rename, delete, move note)
- **Status:** complete

### Phase 4: Edge Cases
- [x] Special characters: `< > & " ' \ /`
- [x] Unicode: emojis, CJK
- [x] Large notes (10KB)
- [x] Empty content, whitespace-only
- [x] Very long titles
- [x] HTML-like content (XSS prevention)
- [x] All markdown features
- [x] Tables (markdown to native Notes format)
- **Status:** complete

### Phase 5: Hashtags & Links
- [x] List all hashtags in database
- [x] Search by hashtag
- [x] Create note with hashtag text (preserved as text)
- [x] Get hashtags for specific note
- [x] List all note links in database
- [x] Get note links for specific note
- Note: "Real" hashtags require Notes UI interaction; API creates text only
- **Status:** complete

### Phase 6: iCloud Sync Verification
- [ ] Create note → appears on other device/web
- [ ] Modify note → syncs correctly
- [ ] Delete note → removed from cloud
- **Status:** pending

## Open Questions
1. What test framework to use? (XCTest, swift-testing, shell scripts with jq)
2. Should tests be automated in CI or manual?
3. How to verify iCloud sync without manual intervention?

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Use swift-testing framework | Modern, works without Xcode, supports tags and serialization |
| Use dedicated test folder "Claude-Integration-Tests" | Isolates test data from user's real notes |
| Serialize integration tests | Avoid race conditions when creating test folder |
| Test via AppleScript + Database | AppleScript for writes (CloudKit compat), Database for reads |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| Duplicate folder name error | 1 | Made integration tests serialized |
| Delete test expecting error | 1 | Notes moves to Recently Deleted, simplified test |
