# Goal-15: CRDT Paragraph Style Investigation

## Objective
Understand and fix the paragraph style (Title/Heading) detection issue in macOS Sequoia. Notes styled with Title/Heading in Notes.app are showing as Body in our preview.

## Background
- Notes.app Format menu shows "Title" checked for certain lines
- Our decoder reads style_type=0 (body) for these lines
- The protobuf Field 1 (style_type) inside ParagraphStyle is MISSING in newer notes
- Only Field 3=1 and Field 9=UUID are present
- Apple appears to have changed the protobuf format in Sequoia

## Hypothesis
The style information is stored in the CRDT (Conflict-free Replicated Data Type) operations in Field 3 of the document, not in the Field 5 attribute runs. We need to investigate how CRDT resolves final paragraph styles.

---

## Phases

### Phase 1: CRDT Structure Analysis ✅
- [x] Map the complete CRDT structure in Field 3 entries
- [x] Understand what each sub-field means (Field 1, 2, 3, 4, 5)
- [x] Identify tombstone markers (deleted text)
- [x] Find where paragraph style might be encoded
- **Result**: CRDT ops do NOT contain style info - only position/length/tombstone

### Phase 2: Compare Old vs New Format ✅
- [x] Find oldest notes with explicit Title/Heading styles
- [x] Compare Field 3/5 structure between old and new notes
- [x] Identify exactly what changed in Sequoia
- **Result**: Heading (style_type=1) IS saved; Title is first-line-only convention

### Phase 3: CRDT Resolution Algorithm ✅
- [x] Research Apple's CRDT implementation
- [x] Understand how position clocks work
- [x] Determine how styles are resolved from CRDT ops
- [x] Check if styles are in CRDT ops vs attribute runs
- **Result**: Styles in Field 5 attribute runs, not CRDT ops

### Phase 4: Style Source Discovery ✅
- [x] Check if style UUID (Field 9) references something
- [x] Examine all protobuf fields for style definitions
- [x] Look for style tables or dictionaries in the data
- [x] Check ZMERGEABLEDATA columns
- **Result**: Field 9 = replica IDs for CRDT, not style refs. ZMERGEABLEDATA = NULL

### Phase 5: Root Cause Identified ✅
- [x] User verification: Title (⇧⌘T) not saved to non-first-line
- [x] Confirmed: style_type=1 = HEADING, not Title
- [x] Confirmed: Heading IS saved properly (Sophos note proves this)
- **Result**: Title is first-line-only by design; our enum naming was wrong

### Phase 6: Implement Fix ✅
- [x] Fix NoteStyleType enum: rename title→heading, add proper title handling
- [x] Update Decoder.swift: first line = title (inferred), style_type=1 = heading
- [x] Update HTML/Markdown rendering for corrected styles
- [x] Test with various note types
- **Result**: Enum renamed, tests pass, committed (c66431b)

### Phase 7: Font Attribute Enhancement ✅
- [x] Investigate font size/name storage in protobuf
- [x] User created test note with 18pt, Skia font
- [x] Discovered: Field 3 contains font info (size=f2 as float, name=f3 as string)
- [x] Added `parseFontInfo()` to Decoder.swift
- [x] HTML rendering now includes inline styles for custom fonts
- [x] Confirmed Title (⇧⌘T) on non-first-line: still body, no special font stored
- **Result**: Font parsing implemented, committed (144e6cd)

### Phase 8: Title Style Discovery - BREAKTHROUGH ✅
- [x] User showed iPhone screenshot: Title styling syncs correctly
- [x] User showed Mac screenshot: Format menu shows Title checked
- [x] Analyzed raw protobuf bytes comparing Title vs Body lines
- [x] **DISCOVERY**: style_type=0 means TITLE, not Body!
- [x] Body is represented by ABSENCE of style_type field, not value 0
- [x] Fixed Decoder.swift: swapped body/title enum values
- [x] Fixed Encoder.swift: Title writes style_type=0, Body omits field
- [x] Tests pass
- **Result**: Title styling now correctly detected on ANY line

---

## Summary

**Goal-15 COMPLETE** - The "bug" where Title styling wasn't detected was actually a misunderstanding of the protobuf encoding:

| What we thought | What it actually is |
|-----------------|---------------------|
| style_type=0 → Body | style_type=0 → **Title** |
| Title = first line only | Title = any line with style_type=0 |
| style_type absent → ? | style_type absent → **Body** |

---

## Key Questions - ANSWERED

1. **What does Field 3 inside ParagraphStyle (always=1) mean?**
   → Unknown flag, possibly "is paragraph" indicator. Not style related.

2. **What does Field 9 (UUID) inside ParagraphStyle reference?**
   → Replica/author ID for CRDT conflict resolution. Not a style reference.

3. **Are paragraph styles stored in CRDT Field 3 ops instead of Field 5 attribute runs?**
   → NO. CRDT ops only have position/length/tombstone. Styles are in Field 5.

4. **How does CRDT resolve the final style for each paragraph?**
   → Field 5 attribute runs contain the resolved styles with style_type field.

5. **Is there a style dictionary/table we're missing?**
   → NO. The real issue: Title (⇧⌘T) is first-line-only and not saved to DB.

## Root Cause Summary

**The "bug" is actually by design:**
- **Title** format only applies to the first line of a note
- Applying Title to other lines shows in UI but is NOT persisted
- **Heading** (⇧⌘H, style_type=1) is the correct format for section headers
- Our code incorrectly named style_type=1 as "title" when it's actually "heading"

---

## Test Notes

| UUID | Title | Purpose |
|------|-------|---------|
| 7ED92F7A-64F5-43D7-9DE7-6BF491459AFB | Seance 30 - javier | Has Title-styled lines that show as Body |
| 10966F0D-B57F-49BD-B936-5261B72A2C3E | Typography Showcase | Rich formatting showcase |
| C988CC0C-3263-436A-A6A0-34D31D5E9654 | Title Test Note Jan 2026 | Fresh test note |
| F2735AFA-6BD5-4EBF-931C-5A55FD766DBD | Sophos... (oldest note) | Old format reference |
