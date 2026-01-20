# Goal-10: Search Feature Tests

## Overview
Add comprehensive unit and integration tests for all search features added in Goal-9.

## Test Coverage Needed

### 1. BertTokenizer Tests
- [ ] Basic tokenization (single words, sentences)
- [ ] Special tokens ([CLS], [SEP], [PAD], [UNK])
- [ ] Unicode handling (emojis, accents, CJK)
- [ ] Max length truncation (512 tokens)
- [ ] MLMultiArray output shape verification

### 2. MiniLMEmbeddings Tests
- [ ] Model loading (Bundle.module resource)
- [ ] Embedding dimension (384)
- [ ] Cosine similarity calculation
- [ ] Batch encoding
- [ ] Error handling (model not found)

### 3. SemanticSearch Tests
- [ ] Index building from notes
- [ ] Search with various queries
- [ ] Score ordering (highest first)
- [ ] Limit parameter
- [ ] Empty index handling
- [ ] Note addition/removal

### 4. SearchIndex (FTS5) Tests
- [ ] Index creation
- [ ] Full-text search queries
- [ ] Porter stemmer behavior
- [ ] Staleness detection
- [ ] Background rebuild
- [ ] Snippet highlighting

### 5. Database Search Tests
- [ ] Case-insensitive search
- [ ] Multi-term AND/OR
- [ ] Fuzzy matching (Levenshtein)
- [ ] Content search (protobuf decode)
- [ ] Date range filters
- [ ] Folder scope filter
- [ ] Result snippets

### 6. Integration Tests
- [ ] MCP semantic_search tool end-to-end
- [ ] MCP fts_search tool end-to-end
- [ ] MCP search_notes with all parameters
- [ ] Performance benchmarks (regression tests)

## Notes
- Some tests may require mock data (don't depend on real Notes.app)
- Consider test fixtures for tokenizer/embeddings
- FTS5 tests need isolated SQLite database
