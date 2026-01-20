# Testing Rules

## When to Run Tests

**Always run tests when:**
- Modifying existing code in `Sources/NotesLib/`
- Fixing bugs
- Refactoring

```bash
swift test
```

**Run specific test suites:**
```bash
# Unit tests only (fast)
swift test --filter "EncoderDecoderTests|PermissionsTests|MarkdownConverterTests|BertTokenizerTests"

# Integration tests (requires Full Disk Access)
swift test --filter ".integration"
```

## When to Add Tests

**Add tests when:**
- Implementing new features
- Adding new public APIs to NotesLib
- Fixing bugs (add regression test)

## Test Structure

Tests live in `Tests/NotesLibTests/NotesLibTests.swift` using Swift Testing framework.

### Adding a Unit Test

```swift
@Suite("My Feature Tests")
struct MyFeatureTests {
    @Test("Description of what it tests")
    func testSomething() throws {
        // Arrange
        let input = "test"

        // Act
        let result = myFunction(input)

        // Assert
        #expect(result == expected)
    }
}
```

### Adding an Integration Test

Integration tests interact with Apple Notes and require `.tags(.integration)`:

```swift
@Suite("My Integration Tests", .tags(.integration), .serialized)
struct MyIntegrationTests {
    let database = NotesDatabase()

    @Test("Test with real database")
    func testWithDatabase() throws {
        // Uses actual Notes database
    }
}
```

## Test Categories

| Suite | Purpose | Speed |
|-------|---------|-------|
| `EncoderDecoderTests` | Protobuf encode/decode | Fast |
| `MarkdownConverterTests` | Markdown to HTML | Fast |
| `BertTokenizerTests` | ML tokenization | Fast |
| `SearchIndexTests` | FTS5 search | Medium |
| `SemanticSearchTests` | AI embeddings | Slow |
| `IntegrationTests` | Full Apple Notes API | Slow |

## Before Committing

1. Run unit tests: `swift test --filter "EncoderDecoderTests"`
2. If you changed search: `swift test --filter "Search"`
3. If you changed database code: `swift test --filter "Database"`
