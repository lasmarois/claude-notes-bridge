# Progress: Goal-9 Enhanced Search

## Session 1 - 2026-01-19

### Context
User tested the MCP search and found it too limited:
- Searching "grep tricks" required exact title matches
- Had to run multiple searches manually (grep, regex, awk, sed...)
- No fuzzy matching or content search

### Completed
- [x] Created goal-9 in GOALS.md registry
- [x] Analyzed current `searchNotes()` implementation (Database.swift:156-204)
- [x] Documented limitations: title-only, exact match, case-sensitive
- [x] Researched context search approaches
- [x] Documented 4 approaches in findings.md:
  1. Enhanced text search (low complexity)
  2. Metadata-aware search (medium)
  3. SQLite FTS5 (medium)
  4. Semantic/vector search (high)

### Current State
- Phase 1 in progress
- Waiting for user input on approach preference
- Ready to implement once direction is chosen

### Files Modified
- `planning/GOALS.md` - Added goal-9 as in_progress
- `task_plan.md` - Created
- `findings.md` - Created
- `progress.md` - Created

### Next Steps
1. ~~Discuss approach options with user~~ ✅
2. ~~Decide: quick wins first vs full FTS5 vs semantic search~~ ✅ Quick wins chosen
3. ~~Begin implementation based on chosen path~~ ✅ Implemented

---

## Session 1 (continued) - Implementation

### Implemented Quick Wins

**Changes to `Database.swift`:**
1. **Case-insensitive search** - Using `LOWER()` on both columns and query
2. **Snippet search** - Added `ZSNIPPET` column to search (first line of note)
3. **Folder name search** - Added `f.ZTITLE2` (folder name) to search
4. **Content search** - New `searchContent: Bool` parameter
   - When true, decodes protobuf body and searches full content
   - Two-phase: fast index search first, then content search for remaining slots

**Changes to `Server.swift`:**
1. Updated tool description for `search_notes`
2. Added `search_content` parameter (boolean, optional)

### Code Changes Summary

```swift
// Before: Title only, case-sensitive
AND n.ZTITLE1 LIKE '%' || ? || '%'

// After: Title + snippet + folder, case-insensitive
AND (
    LOWER(n.ZTITLE1) LIKE '%' || LOWER(?) || '%'
    OR LOWER(COALESCE(n.ZSNIPPET, '')) LIKE '%' || LOWER(?) || '%'
    OR LOWER(COALESCE(f.ZTITLE2, '')) LIKE '%' || LOWER(?) || '%'
)
```

### Build Status
- ✅ `swift build` passed
- ✅ `swift build -c release` passed
- ⏳ Testing requires new Claude session (MCP server restart)

### Testing Results ✅

All search improvements verified in new Claude session:

| Feature | Test | Result |
|---------|------|--------|
| **Case-insensitive** | `GREP` vs `grep` | ✅ Same 5 results |
| **Folder search** | `commandes cool` | ✅ Found 5 notes in "</> Commandes cool" folder |
| **Folder search** | `regex` | ✅ Found notes in "℞ regex" folder |
| **Content search OFF** | `cmsg` (body-only term) | ✅ No results (correct) |
| **Content search ON** | `cmsg` with search_content=true | ✅ Found Kubernetes note with "cmsg-846d7fb485-fwxtm" in body |

**Quick wins implementation: COMPLETE**

---

## Session 2 - 2026-01-19

### Benchmark Results

Created `Sources/Benchmark/main.swift` to measure search performance.

**With 1798 notes:**

| Scenario | Index Only | With Content | Slowdown |
|----------|------------|--------------|----------|
| 20 index hits (grep) | 7ms | 7ms | 1.0x |
| 14 index hits (sudo) | 7ms | 28ms | 4.2x |
| 0 index hits (cmsg) | 6ms | 167ms | 26.5x |
| No matches (worst case) | 6ms | 170ms | 27x |

**Key insight:** Content search adds ~160ms when it needs to scan all notes. Acceptable for interactive use.

### Threshold Fallback with Hint

Implemented user-requested feature: when few results found, suggest content search.

**Logic:**
- If `search_content=false` AND results < 5 AND results < limit
- Append hint: "💡 Only N result(s) found... Set search_content=true..."

**Test results:**
- `kubectl` (1 result) → ✅ Shows hint
- `ansible` (20 results) → ❌ No hint (enough results)
- `kubectl` + `search_content=true` → ❌ No hint (already searched)
- `cmsg` (0 results) → ✅ Shows hint

### Files Modified
- `Sources/NotesLib/MCP/Server.swift` - Added threshold hint logic
- `Sources/Benchmark/main.swift` - New benchmark tool
- `Package.swift` - Added benchmark target

---

## Session 2 (continued) - Semantic Search Research & Implementation Attempt

### Core ML Semantic Search Research ✅

Researched options for semantic/vector search:

| Option | Vector Size | Dependencies | Platform |
|--------|-------------|--------------|----------|
| Apple NLEmbedding | 512 | None (built-in) | macOS 10.15+ |
| Apple NLContextualEmbedding | 512/token | Asset download | macOS 14+ |
| Custom Core ML (sentence-transformers) | 384 | ~100MB model | macOS 13+ |

Found two Swift libraries for semantic search:

1. **SimilaritySearchKit** (recommended)
   - GitHub: https://github.com/ZachNagengast/similarity-search-kit
   - Bundled MiniLM model (46MB, 384-dim)
   - High-level API: `index.addItem()`, `index.search()`
   - Platform: macOS 13+, iOS 16+

2. **swift-embeddings**
   - GitHub: https://github.com/jkrukowski/swift-embeddings
   - Downloads models from Hugging Face
   - Requires macOS 15+ (MLTensor)

### Implementation Attempted

**Files created:**
- `Sources/NotesLib/Search/SemanticSearch.swift` - Actor wrapping SimilarityIndex
  - Auto-builds index on first search
  - Indexes note title + folder for semantic matching
  - Methods: `buildIndex()`, `search()`, `addNote()`, `removeNote()`

**Files modified:**
- `Package.swift` - Added SimilaritySearchKit dependency, bumped to macOS 13
- `Server.swift` - Added `semanticSearch` instance and `semantic_search` MCP tool

### Build Issue ⚠️

**Problem:** SimilaritySearchKit build failed with Core ML model generation errors.

The bundled MiniLM `.mlpackage` couldn't be processed during Swift build.

### Current State: TEMPORARILY DISABLED

All semantic search code has been **commented out** pending resolution:

```swift
// Package.swift - dependency commented out
// .package(url: "https://github.com/ZachNagengast/similarity-search-kit.git", from: "0.0.1")

// Package.swift - file excluded from build
exclude: ["Search/SemanticSearch.swift"]

// Server.swift - semantic search disabled
// private let semanticSearch: SemanticSearch
// case "semantic_search": ...
```

### Next Steps for Semantic Search

Options to investigate:
1. **Debug SimilaritySearchKit** - Check GitHub issues for Core ML build fix
2. **Try swift-embeddings** - Requires macOS 15, downloads models at runtime
3. **Use Apple NLEmbedding** - Built-in, simpler, potentially lower quality
4. **Manual Core ML conversion** - Use coremltools Python to convert model ourselves

### Research Findings Saved

All semantic search research documented in `findings.md`:
- Detailed comparison of embedding options
- Code examples for each approach
- Vector storage options (sqlite-vec, pure Swift)
- Architecture sketch for semantic search pipeline

---

## Session 3 - 2026-01-19

### Implemented Features

**Multi-term search:**
- `term1 AND term2` - all terms must match
- `term1 OR term2` - any term matches
- Works with index search, content search, and fuzzy search

**Fuzzy matching:**
- Levenshtein distance-based typo tolerance
- `ansble` → `ansible`, `doker` → `docker`
- Threshold: 2 edits for words ≤5 chars, 3 for longer

**Filters:**
- `folder` - exact match (case-insensitive)
- `modified_after` / `modified_before` - ISO 8601 date
- `created_after` / `created_before` - ISO 8601 date

### Completed

**Result snippets with highlights:**
- Added `matchSnippet` field to Note model
- Extract snippet with 40-60 char context window
- Highlight matching terms with **bold** markers

**FTS5 Full-Text Search Index:**
- New `SearchIndex` class manages separate SQLite database
- Stores index in `~/Library/Caches/claude-notes-bridge/search_index.db`
- Uses FTS5 virtual table with porter stemmer tokenization
- New MCP tools: `build_search_index`, `fts_search`

### Benchmark Results - FTS5 vs Content Scan

| Query | Content Scan | FTS5 | Speedup |
|-------|-------------|------|---------|
| kubectl | 175ms | 0.12ms | **1512x** |
| cmsg | 179ms | 0.06ms | **3198x** |
| sudo | 32ms | 0.50ms | **64x** |
| grep | 7ms | 0.50ms | **13x** |

FTS5 is **1000-3000x faster** for content searches!

### Commits
- `eb6dc29` - Enhanced search with content search and threshold hints
- `32d7cab` - Multi-term, fuzzy matching, and filter support
- `07118d8` - Result snippets with highlights
