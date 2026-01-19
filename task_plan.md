# Goal 8: M6.6 - Integration Testing

## Objective
Build a comprehensive test suite to verify all MCP tools work correctly end-to-end, with proper handling of edge cases.

## Current Phase
Phase 1 (Research & Planning)

## Phases

### Phase 1: Research & Planning
- [ ] Audit existing tools and their expected behaviors
- [ ] Identify test framework options (XCTest, swift-testing, shell scripts)
- [ ] Define test categories and coverage goals
- **Status:** in_progress

### Phase 2: Basic Tool Tests
- [ ] Test `list_notes` (pagination, empty results)
- [ ] Test `read_note` (plain/html formats, missing note)
- [ ] Test `search_notes` (query matching, special chars)
- [ ] Test `create_note` (basic, with markdown)
- [ ] Test `update_note` (title, body, both)
- [ ] Test `delete_note` (existing, missing)
- **Status:** pending

### Phase 3: Round-Trip Tests
- [ ] Create → Read → Verify content matches
- [ ] Create → Update → Read → Verify changes
- [ ] Create → Delete → Verify gone
- [ ] Folder operations round-trip
- **Status:** pending

### Phase 4: Edge Cases
- [ ] Special characters: `< > & " ' \ /`
- [ ] Unicode: emojis, CJK, RTL text
- [ ] Large notes (10KB+, 100KB+)
- [ ] Empty content, whitespace-only
- [ ] Very long titles
- **Status:** pending

### Phase 5: Hashtags & Links
- [ ] Create note with #hashtags → verify detected
- [ ] Note links round-trip
- [ ] Markdown with all features
- **Status:** pending

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

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
