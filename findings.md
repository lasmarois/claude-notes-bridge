# Findings - Goal-15 (CRDT Paragraph Style Investigation)

## Protobuf Structure Overview

### Document Structure (Field 2.3)
```
Field 2 (Document):
  Field 1: version (varint)
  Field 2: unknown (varint)
  Field 3 (DocumentContent):
    Field 2: text content (bytes/string)
    Field 3: CRDT operations (repeated)
    Field 4: author info
    Field 5: attribute runs (repeated)
```

### CRDT Operation (Field 3 entries)
```
Field 3 (CRDT Op):
  Field 1: position clock (sub-message)
    Field 1: author ID (varint)
    Field 2: sequence number (varint)
  Field 2: length (varint)
  Field 3: parent reference (sub-message)
    Field 1: author ID (varint)
    Field 2: sequence number (varint)
  Field 4: tombstone flag (varint, 1=deleted)
  Field 5: op sequence (varint)
```

### Attribute Run (Field 5 entries)
```
Field 5 (AttributeRun):
  Field 1: length (varint)
  Field 2: paragraph_style (sub-message)
    OLD FORMAT:
      Field 1: style_type (0=body, 1=title, 2=heading, etc.)
      Field 3: unknown (always 1)
      Field 9: UUID reference (16 bytes)
    NEW FORMAT (Sequoia):
      Field 3: unknown (always 1)
      Field 9: UUID reference (16 bytes)
      NOTE: Field 1 (style_type) IS MISSING!
  Field 3: font (sub-message)
  Field 5: font_weight (varint)
  Field 13: timestamp (varint)
```

---

## Format Comparison

### Old Note (pre-Sequoia)
Note: F2735AFA-6BD5-4EBF-931C-5A55FD766DBD
```
Field 5 [len-delim]:
  Field 1 [varint]: 9          // length
  Field 2 [len-delim]:         // paragraph_style
    Field 1 [varint]: 0        // style_type = BODY
    Field 3 [varint]: 1        // unknown
    Field 9: UUID
```

### New Note (Sequoia)
Note: 7ED92F7A-64F5-43D7-9DE7-6BF491459AFB
```
Field 5 [len-delim]:
  Field 1 [varint]: 7          // length
  Field 2 [len-delim]:         // paragraph_style
    Field 1 [varint]: 0        // style_type = BODY (explicit)
    Field 9: UUID
    // Note: Some runs have Field 1=0, others have NO Field 1
```

---

## Style Type Values (CORRECTED)

| Value | Style | Notes |
|-------|-------|-------|
| 0 | body | Default paragraph |
| 1 | **HEADING** | Section headers (⇧⌘H) - STORED in protobuf |
| 2 | subheading | Smaller headers |
| 3 | ? | Unknown |
| 4 | monospaced | Code/preformatted |
| 100 | bulletList | Dash list (- item) |
| 101 | numberedList | Numbered (1. item) |
| 102 | checkbox | Unchecked [ ] |
| 103 | checkboxChecked | Checked [x] |
| -1 | unknown | Default when missing |

### Title vs Heading Discovery

**CRITICAL FINDING:**
- **Title** (⇧⌘T) = First line ONLY, NOT stored as style_type in protobuf
- **Heading** (⇧⌘H) = style_type=1, IS stored in protobuf

When user applies Title (⇧⌘T) to non-first-line text:
- Notes.app UI shows "Title" checked in Format menu
- But the style is NOT saved to the database
- Database shows body (0) for these lines

**Evidence:**
- Sophos note: Section headers use Heading (style_type=1) - properly saved
- Seance 30 note: "Preparation" has Title applied via ⇧⌘T - NOT saved (shows body)

### Font Attributes Investigation (Session 2)

**Question:** Can we use font size/weight to detect Title styling?

**Analysis of Seance 30 note protobuf:**
```
"Preparation" line:
  style_type = 0 (body)      ← NOT saved as Title
  FONT WEIGHT = 1 (bold)     ← Bold IS saved
```

**Conclusion: No, we cannot reliably detect Title from font attributes**

Reasons:
1. **No font size field** exists in attribute runs - only FONT WEIGHT (field 5)
2. **Bold is ambiguous** - could be:
   - Title applied to first line
   - Title applied to non-first-line (user's case)
   - Manually bolded body text
3. We cannot distinguish between cases 2 and 3

**Detailed analysis (622 bold runs examined):**
| Attribute | Title-styled first line | Title-styled "Preparation" | Manual bold |
|-----------|------------------------|---------------------------|-------------|
| style_type | 0 (body) | 0 (body) | 0 (body) |
| fontWeight | 1 (bold) | 1 (bold) | 1 (bold) |
| font size | nil | nil | nil |
| font name | nil | nil | nil |

All three cases are **IDENTICAL** in the protobuf - no distinguishing attributes.

**How font size is applied:**
- Font size is NOT stored in protobuf
- Notes.app applies font size via CSS based on `style_type` during rendering
- style_type=1 (Heading) renders at 22px, body at 15px
- Title is first-line only, styled in CSS at 28px

**Recommendation:**
- Keep current behavior: first line = title by convention
- Users wanting section headers should use Heading (⇧⌘H)
- Title (⇧⌘T) is designed for first-line only by Apple
- Rename enum: `title` → `heading` (since style_type=1 is Heading)

---

## Font Size and Font Name Discovery (Session 3)

### Investigation Trigger
User created test note "Nico Test Note font size and name" with:
- Text in 18pt font size
- Text using Skia font
- Title applied via ⇧⌘T on non-first-line

### Key Finding: Font Size and Name ARE Stored!

**Previous assumption was WRONG.** Font size and font name are stored in **Field 3** of attribute runs.

**Font info encoding in Field 3:**
```
f3 [msg 7b]:              ← When size is set
    f2 [32bit]: 00009041  ← Float: 18.0 (font size in points)
    f3: 1                 ← Unknown flag

f3 [str 14b]: "\nSkia-Regular"  ← Font name as string (leading \n)
```

### Protobuf Structure Update

```
Field 5 (AttributeRun):
  Field 1: length (varint)
  Field 2: paragraph_style (sub-message)
  Field 3: font (sub-message OR string)
    AS MESSAGE:
      Field 2: font size (32-bit float)
      Field 3: unknown flag
    AS STRING:
      Font name (e.g., "\nSkia-Regular")
  Field 5: font_weight (varint)
  Field 13: timestamp (varint)
```

### Test Note Analysis

| Run | Text | style_type | Font Size | Font Name | Bold |
|-----|------|------------|-----------|-----------|------|
| 3-8 | "Bonjour I am bold and size 18\n" | body (0) | 18.0 | nil | yes |
| 11-28 | "Bonjour I am not bold and regular..." | body (0) | nil | nil | no |
| 29-42 | "...using font name skia" | body (0) | nil | Skia-Regular | no |
| 43-55 | "Bonjour I am a title created with ⇧⌘T" | body (0) | nil | nil | no |

### Title on Non-First-Line: Still Not Stored
The Title-styled line (⇧⌘T) shows:
- `style_type = 0` (body) - NOT title
- No special font size
- No font weight
- No distinguishing attributes

**Conclusion confirmed:** Title format (⇧⌘T) on non-first-line is purely UI state, never persisted.

### Implementation
Font parsing added to Decoder.swift:
- New `parseFontInfo()` function handles both message and string formats
- `AttributeRun` now includes `fontSize: Float?` and `fontName: String?`
- HTML rendering generates inline styles for custom fonts

Commits:
- `c66431b` - Rename NoteStyleType: title→heading
- `144e6cd` - Add font size and font name parsing

---

## MAJOR DISCOVERY: Title Style Encoding (Session 4)

### The Breakthrough

**User observation:** Title styling (⇧⌘T) applied to non-first-line text syncs correctly between Mac and iPhone, but our decoder was showing it as Body.

**Investigation:** User provided screenshots showing:
1. iPhone: Title line displayed with large bold Title styling
2. Mac: Format menu shows "Title" checked for that line
3. But our protobuf dump showed `style_type=0` (which we thought was Body)

### Key Finding: Presence vs Absence of style_type Field

After examining raw protobuf bytes, discovered the actual encoding:

| Protobuf state | f2.f1 value | Meaning |
|----------------|-------------|---------|
| **Field f2.f1 ABSENT** | (not present) | **Body** (default) |
| **Field f2.f1 = 0** | 0 | **Title** |
| Field f2.f1 = 1 | 1 | Heading |
| Field f2.f1 = 4 | 4 | Monospaced |
| etc. | | |

**The critical insight:** We were interpreting `style_type=0` as Body, but it actually means **Title**. Body is represented by the **complete absence** of the style_type field.

### Evidence

Analyzed "Nico Test Note" attribute runs:

```
Run 0 (first line, displays as Title):
  f2 [20b]: 08 00 4a 10 [uuid]   ← f1=0 PRESENT → Title

Run 11 (body text):
  f2 [18b]: 4a 10 [uuid]         ← f1 ABSENT → Body

Run 43 (Title via ⇧⌘T, displays as Title):
  f2 [20b]: 08 00 4a 10 [uuid]   ← f1=0 PRESENT → Title
```

### Updated Style Type Mapping

```
Protobuf style_type | Apple Notes Style | Keyboard
--------------------|-------------------|----------
(field absent)      | Body              | (default)
0                   | Title             | ⇧⌘T
1                   | Heading           | ⇧⌘H
2                   | Subheading        | ⇧⌘J
3                   | Subheading2       | -
4                   | Monospaced        | ⇧⌘M
100                 | Bulleted List     | ⇧⌘7
101                 | Numbered List     | ⇧⌘9
102                 | Checkbox          | ⇧⌘L
103                 | Checked Checkbox  | -
```

### Code Fix Applied

**Decoder.swift:**
- Changed `NoteStyleType.body = 0` to `NoteStyleType.title = 0`
- Changed `NoteStyleType.title = -2` to `NoteStyleType.body = -2`
- Body is now the fallback when style_type field is absent

**Encoder.swift:**
- For Title: explicitly write `style_type=0`
- For Body: **omit** the style_type field entirely (pass `nil` for paragraphStyle)
- For other styles: write their respective values

### Why This Matters

1. **Title styling now correctly detected** on any line (not just first line)
2. **Round-trip encoding/decoding** now works correctly
3. **Syncing works** because we're reading the same data iPhone/Mac use
4. **Previous "first-line-only" assumption was wrong** - Title CAN be applied anywhere

### Remaining First-Line Behavior

The first-line-as-title logic in `noteToHTML()` is still useful as a fallback:
- If first line has no explicit style (body), we still render it as Title for display
- This matches Notes.app's visual rendering behavior

---

## Open Questions

1. **Field 3 in ParagraphStyle**: Always value=1. What does it mean?
2. **Field 9 UUID**: What does this reference? Style definition table?
3. **CRDT ops**: Do they contain paragraph style info?
4. **Missing style_type**: Where is Title/Heading stored in new format?

---

## CRDT Analysis Results (Session 1)

### Key Finding: CRDT Ops Do NOT Contain Style Info
The CRDT operations (Field 3 entries) only contain:
- Field 1: Position clock (author_id, sequence_num)
- Field 2: Length
- Field 3: Parent reference
- Field 4: Tombstone flag (deleted text)
- Field 5: Op sequence number

**No extra fields for paragraph styling!** Style info is in Field 5 attribute runs, not CRDT ops.

### Format Comparison Results

| Note | styleType Present | Without styleType | Observation |
|------|-------------------|-------------------|-------------|
| Sophos (old) | 20 runs | 10 runs | HAS Title (style=1) correctly |
| Seance 30 | 59 runs | 24 runs | Title lines show as BODY (style=0) |
| Typography | 1 run | 52 runs | Almost all runs missing styleType |

### Critical Finding: Seance 30 Note

The "Preparation" and "Excercice" lines that show as Title in Notes.app are stored as **BODY (style=0)** in the database:
```
[11] pos=38 len=12 para={style=body} "Preparation\n"
[18] pos=60 len=3 para={style=body} "ce\n"  (Excercice)
```

**This means Notes.app's Format menu shows Title, but the database has Body.**

### Possible Explanations

1. **Unsaved State**: Notes.app UI shows Title but hasn't persisted to database
2. **CloudKit Sync**: Formatting stored in CloudKit, not yet synced to local SQLite
3. **Different Storage**: Style stored elsewhere (ZMERGEABLEDATA?)
4. **Bug in Notes.app**: Format menu shows incorrect state

### ParagraphStyle Field 3 Analysis

Field 3 inside ParagraphStyle is almost always `1`. It appears across:
- Old notes: 25/30 runs have f3=1
- Problem note: 46/83 runs have f3=1
- Typography: 51/53 runs have f3=1

**Field 3 is NOT the style type** - it's some other flag (possibly "is paragraph" or similar).

---

## CRDT Research

### Apple CRDT Implementation
- Type: Likely RGA (Replicated Growable Array) variant
- Used for: Collaborative editing, conflict resolution
- Storage: Field 3 contains CRDT ops, Field 5 contains resolved attributes

### Key CRDT Concepts
- **Position clock**: (author_id, sequence_num) uniquely identifies each character
- **Tombstone**: Marks deleted text without removing from CRDT
- **Parent reference**: Points to character this was inserted after
