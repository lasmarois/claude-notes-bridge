# Progress Log - Goal-15 (CRDT Paragraph Style Investigation)

## Session 1: Initial Investigation

### Context
- User observed Title-styled lines appearing as Body in preview
- Screenshot confirmed Format menu shows "Title" checked
- Database analysis shows Field 1 (style_type) missing in new format

### Completed
- [x] Identified the symptom: Title/Heading styled text renders as Body
- [x] Dumped protobuf structure for multiple notes
- [x] Discovered Field 1 (style_type) is missing in Sequoia-format notes
- [x] Found Field 3=1 and Field 9=UUID present instead
- [x] Archived Goal-14, created Goal-15

### Key Findings So Far
1. Old format (pre-Sequoia): `ParagraphStyle { style_type=0, field3=1, field9=UUID }`
2. New format (Sequoia): `ParagraphStyle { field3=1, field9=UUID }` - NO style_type!
3. Field 3 entries in document contain CRDT operations
4. User's hypothesis: Style info is in CRDT ops, not attribute runs

### Next Steps
- Deep dive into CRDT Field 3 structure
- Map all CRDT operation fields
- Find where paragraph styles are encoded

## Session 1: Deep CRDT Analysis

### Completed Analysis
- [x] Created comprehensive protobuf analysis script
- [x] Analyzed CRDT operations (Field 3) - NO style info, only position/length/tombstone
- [x] Analyzed attribute runs (Field 5) - style info IS here
- [x] Compared old vs new format notes
- [x] Analyzed Field 9 UUIDs - they're replica IDs, not style references

### Critical Finding

**The database shows "Preparation" as BODY, not TITLE:**
```
[11] pos=38 len=12 para={style=body} "Preparation\n"
```

This means either:
1. Notes.app hasn't saved the Title formatting to the database
2. The Format menu is showing stale/cached UI state
3. iCloud sync hasn't completed

### UUID Analysis Results
- Field 9 UUIDs are **replica/author identifiers**, not style references
- Each editing session/author gets a unique UUID
- Same style can have multiple different UUIDs
- UUIDs are for CRDT conflict resolution

### Database State
- ZMERGEABLEDATA, ZMERGEABLEDATA1, ZMERGEABLEDATA2 are all NULL for this note
- Only ZDATA (protobuf blob) contains note content
- ZSERVERRECORDDATA has CloudKit metadata, not style info

### User Verification Tests

1. **Small edit test**: User made edit - text saved but style still body
2. **Explicit Title toggle**: User changed Preparation Body→Title→quit - still body in DB
3. **Sophos note analysis**: Confirmed style_type=1 is HEADING, not Title

### Key Discovery: Title vs Heading

User confirmed:
- Sophos note section headers = **Heading** format (style_type=1)
- User applies Title via **⇧⌘T** to "Preparation" and "Excercice"
- Notes.app shows Title in Format menu but does NOT save to database

**ROOT CAUSE IDENTIFIED:**
- **Title** style (⇧⌘T) only works for the first line
- Applying Title to other lines shows in UI but is NOT persisted
- **Heading** style (⇧⌘H) = style_type=1, IS persisted
- This is likely by design, not a bug - Title is meant for first line only

### Implications for Decoder

1. First line should always render as Title (current behavior is correct)
2. style_type=1 = Heading (NOT Title) - need to fix enum naming
3. Non-first-line Title formatting cannot be read because it's never saved

---

## Session 2: Font Attribute Investigation

### User Question
> "are you able to look at the font size and other font format to distinguish Titles with normal body?"

### Investigation Goal
Determine if font attributes (size, weight, etc.) are stored in the protobuf and could serve as a heuristic to detect "visual Title" styling even when style_type is not set.

### Findings

**Analyzed Seance 30 note (has Title styled "Preparation" line):**

| Run | Text | style_type | FONT WEIGHT | What it means |
|-----|------|------------|-------------|---------------|
| 0-10 | "Seance 30..." | 0 (body) | 1 (bold) | First line (treated as title by convention) |
| 11 | "Preparation" | 0 (body) | 1 (bold) | Title applied via ⇧⌘T but NOT saved as style_type |
| 13 | "Bonjour" | none | none | Regular body text |

**Key Finding:**
- When Title (⇧⌘T) is applied to non-first-line text:
  - `style_type` = 0 (body) - NOT saved as title
  - `FONT WEIGHT` = 1 (bold) - visual styling IS saved

**Conclusion: Font weight cannot reliably distinguish Title from body**
- Bold text (FONT WEIGHT=1) could be:
  1. Title applied to first line (correct)
  2. Title applied to non-first-line (user's case)
  3. Manually bolded body text (common)
- No font size field was observed in the attribute runs
- We cannot distinguish cases 2 and 3

### Full Protobuf Dump Analysis

Dumped ALL fields in attribute runs to confirm no hidden size info:

```
Sophos note (style_type=1 Heading):
  f1 [varint]: 25          ← length
  f2 [msg]:                ← paragraph_style
    f1 [varint]: 1         ← style_type = Heading
    f3 [varint]: 1         ← unknown flag
    f9 [uuid]: ...         ← replica ID
  f5 [varint]: 1           ← font_weight (bold)
  f13 [varint]: ...        ← timestamp

Seance note (Title applied to first line):
  f1 [varint]: 7           ← length
  f2 [msg]:                ← paragraph_style
    f1 [varint]: 0         ← style_type = Body
    f9 [uuid]: ...         ← replica ID
  f5 [varint]: 1           ← font_weight (bold)
```

**Confirmed: NO font size field exists.** Only `style_type` determines visual size (applied via CSS rendering).

### Enum Rename Completed

Changed `NoteStyleType` to properly reflect Apple Notes' protobuf values:

| Old Name | New Name | Raw Value | Meaning |
|----------|----------|-----------|---------|
| title | heading | 1 | Section header (⇧⌘H) |
| heading | subheading | 2 | Second-level header |
| subheading | subheading2 | 3 | Third-level header |
| (new) | title | -2 | First line (inferred, not from protobuf) |

Files updated:
- `Decoder.swift` - main enum definition + switch statement
- `Encoder.swift` - local enum + markdown parsing logic
- `MarkdownFormatter.swift` - export switch statement

Tests: ✅ All pass (EncoderDecoderTests)

---

---

## Session 3: Font Size/Name Discovery & Implementation

### What Happened
User challenged previous finding that "font size is not stored" - created test note with 18pt text and Skia font.

### Key Discovery
**Font size and font name ARE stored!** Previous analysis missed this because:
1. Field 3 can be EITHER a message (for font size) OR a string (for font name)
2. Didn't have test notes with explicit font customization

### Findings
- Font size: `f3.f2` as 32-bit float (e.g., 18.0)
- Font name: `f3` as string (e.g., "\nSkia-Regular")
- Title (⇧⌘T) on non-first-line: Confirmed NOT stored (still body, no font attributes)

### Commits Made
1. `c66431b` - Rename NoteStyleType: title→heading to match Apple Notes protobuf
2. `144e6cd` - Add font size and font name parsing to attribute runs

### Implementation
- Added `parseFontInfo()` function to Decoder.swift
- `AttributeRun` now includes `fontSize: Float?` and `fontName: String?`
- HTML rendering generates inline styles for custom fonts
- Tests pass

---

## Session 4: MAJOR BREAKTHROUGH - Title Style Discovery

### What Happened
User challenged our finding by showing iPhone screenshot where Title styling was visible on a non-first-line. This proved Title styling IS being synced, so it MUST be stored somewhere.

### The Investigation
1. Compared Mac UI - also shows "Title" checked in Format menu
2. Dumped raw protobuf bytes for Title-styled lines vs body lines
3. Discovered the key difference: **presence vs absence** of f2.f1 field

### The Discovery

**We had the encoding backwards!**

| Protobuf | Old interpretation | CORRECT interpretation |
|----------|--------------------|-----------------------|
| f2.f1 = 0 | Body | **Title** |
| f2.f1 absent | (unknown) | **Body** |

Title (⇧⌘T) DOES save style_type=0 to the database! Body is when the field is **omitted entirely**.

### Code Changes
- **Decoder.swift**: Swapped `body = 0` to `title = 0`, `body = -2` (sentinel for absent field)
- **Encoder.swift**:
  - Title writes `style_type=0` explicitly
  - Body omits the field entirely (passes `nil`)
- Tests: All pass

### Impact
- Title styling now correctly detected on ANY line
- Previous "first-line-only Title" hypothesis was WRONG
- Notes.app works as expected - we just misread the protobuf

---

## 5-Question Reboot Check
| Question | Answer |
|----------|--------|
| Where am I? | Goal-15 COMPLETE - major discovery made |
| Where am I going? | Commit the fix, archive Goal-15 |
| What's the goal? | Fix Title/Heading detection (DONE!) |
| What have I learned? | style_type=0 means Title, absence means Body |
| What have I done? | Fixed Decoder + Encoder, all tests pass |
