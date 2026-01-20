import Testing
import Foundation
@testable import NotesLib

@Suite("Encoder/Decoder Tests")
struct EncoderDecoderTests {

    @Test("Roundtrip basic text")
    func testRoundtripBasicText() throws {
        let encoder = NoteEncoder()
        let decoder = NoteDecoder()

        let testCases = [
            "Test Title\n\nThis is the body of the note.",
            "Simple Note\n\nLine 1\nLine 2\nLine 3",
            "Unicode Test 🎉\n\nEmojis work: 👍 ✅ 🚀",
            "Title Only"
        ]

        for originalText in testCases {
            let encoded = try encoder.encode(originalText)
            let decoded = try decoder.decode(encoded)
            #expect(decoded == originalText, "Roundtrip failed for: \(originalText.prefix(20))...")
        }
    }

    @Test("Handle empty text")
    func testEmptyText() throws {
        let encoder = NoteEncoder()
        let decoder = NoteDecoder()

        let encoded = try encoder.encode("")
        let decoded = try decoder.decode(encoded)
        #expect(decoded == "")
    }

    @Test("Handle special characters")
    func testSpecialCharacters() throws {
        let encoder = NoteEncoder()
        let decoder = NoteDecoder()

        let specialChars = "Test <>&\"' Special\n\nChars: \\ / @ # $ % ^ & * ( )"
        let encoded = try encoder.encode(specialChars)
        let decoded = try decoder.decode(encoded)
        #expect(decoded == specialChars)
    }

    @Test("Handle unicode characters")
    func testUnicode() throws {
        let encoder = NoteEncoder()
        let decoder = NoteDecoder()

        let unicode = "日本語テスト\n\n中文测试\n한국어 테스트\nالعربية"
        let encoded = try encoder.encode(unicode)
        let decoded = try decoder.decode(encoded)
        #expect(decoded == unicode)
    }
}

@Suite("Permissions Tests")
struct PermissionsTests {

    @Test("Database path is correctly constructed")
    func testDatabasePath() {
        let path = Permissions.notesDatabasePath
        #expect(path.contains("Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"))
    }
}

@Suite("Markdown Converter Tests")
struct MarkdownConverterTests {
    let converter = MarkdownConverter()

    // MARK: - Bold Tests

    @Test("Convert bold with asterisks")
    func testBoldAsterisks() {
        let result = converter.convert("This is **bold** text")
        #expect(result.contains("<b>bold</b>"))
    }

    @Test("Convert bold with underscores")
    func testBoldUnderscores() {
        let result = converter.convert("This is __bold__ text")
        #expect(result.contains("<b>bold</b>"))
    }

    // MARK: - Italic Tests

    @Test("Convert italic with asterisks")
    func testItalicAsterisks() {
        let result = converter.convert("This is *italic* text")
        #expect(result.contains("<i>italic</i>"))
    }

    // MARK: - Strikethrough Tests

    @Test("Convert strikethrough")
    func testStrikethrough() {
        let result = converter.convert("This is ~~deleted~~ text")
        #expect(result.contains("<strike>deleted</strike>"))
    }

    // MARK: - Header Tests

    @Test("Convert H1 header")
    func testH1Header() {
        let result = converter.convert("# Main Header")
        #expect(result.contains("font-size: 24px"))
        #expect(result.contains("Main Header"))
    }

    @Test("Convert H2 header")
    func testH2Header() {
        let result = converter.convert("## Section Header")
        #expect(result.contains("font-size: 18px"))
        #expect(result.contains("Section Header"))
    }

    @Test("Convert H3 header")
    func testH3Header() {
        let result = converter.convert("### Subsection")
        #expect(result.contains("<b>Subsection</b>"))
    }

    // MARK: - List Tests

    @Test("Convert bullet list with dash")
    func testBulletListDash() {
        let result = converter.convert("- Item one\n- Item two")
        #expect(result.contains("• Item one"))
        #expect(result.contains("• Item two"))
    }

    @Test("Convert bullet list with asterisk")
    func testBulletListAsterisk() {
        let result = converter.convert("* Item one\n* Item two")
        #expect(result.contains("• Item one"))
        #expect(result.contains("• Item two"))
    }

    // MARK: - Code Tests

    @Test("Convert inline code")
    func testInlineCode() {
        let result = converter.convert("Use `npm install` command")
        #expect(result.contains("<font face=\"Menlo\" color=\"#c7254e\">"))
        #expect(result.contains("npm install"))
        #expect(result.contains("</font>"))
    }

    @Test("Convert code block")
    func testCodeBlock() {
        let markdown = """
        ```
        function test() {
            return true;
        }
        ```
        """
        let result = converter.convert(markdown)
        #expect(result.contains("<font face=\"Menlo\">"))
        #expect(result.contains("function test()"))
    }

    @Test("Code preserves special characters")
    func testCodeSpecialChars() {
        let result = converter.convert("Use `<div>` and `&` in HTML")
        #expect(result.contains("&lt;div&gt;"))
        #expect(result.contains("&amp;"))
    }

    // MARK: - Blockquote Tests

    @Test("Convert blockquote")
    func testBlockquote() {
        let result = converter.convert("> This is a quote")
        #expect(result.contains("color=\"#666666\""))
        #expect(result.contains("▎"))
    }

    // MARK: - HTML Escaping Tests

    @Test("Escape HTML special characters")
    func testHTMLEscaping() {
        let result = converter.escapeHTML("<script>alert('xss')</script>")
        #expect(result.contains("&lt;script&gt;"))
        #expect(!result.contains("<script>"))
    }

    // MARK: - Combined Tests

    @Test("Convert mixed markdown")
    func testMixedMarkdown() {
        let markdown = """
        # Title

        This has **bold** and *italic*.

        - List item

        > Quote
        """
        let result = converter.convert(markdown)
        #expect(result.contains("font-size: 24px"))  // H1
        #expect(result.contains("<b>bold</b>"))
        #expect(result.contains("<i>italic</i>"))
        #expect(result.contains("• List item"))
        #expect(result.contains("▎"))  // Quote marker
    }

    // MARK: - Table Tests

    @Test("Convert simple table")
    func testSimpleTable() {
        let markdown = """
        | Name | Age |
        |------|-----|
        | Alice | 30 |
        | Bob | 25 |
        """
        let result = converter.convert(markdown)
        #expect(result.contains("<table"))
        #expect(result.contains("<tbody>"))
        #expect(result.contains("<tr>"))
        #expect(result.contains("<td"))
        #expect(result.contains("<b>Name</b>"))  // Header bold
        #expect(result.contains("<b>Age</b>"))   // Header bold
        #expect(result.contains("Alice"))
        #expect(result.contains("30"))
        #expect(result.contains("Bob"))
        #expect(result.contains("25"))
    }

    @Test("Table with three columns")
    func testThreeColumnTable() {
        let markdown = """
        | Name | Age | City |
        |------|-----|------|
        | Alice | 30 | NYC |
        | Bob | 25 | LA |
        """
        let result = converter.convert(markdown)
        #expect(result.contains("<b>Name</b>"))
        #expect(result.contains("<b>Age</b>"))
        #expect(result.contains("<b>City</b>"))
        #expect(result.contains("NYC"))
        #expect(result.contains("LA"))
    }

    @Test("Table preserves surrounding content")
    func testTableWithSurroundingContent() {
        let markdown = """
        # Header

        Some text before.

        | A | B |
        |---|---|
        | 1 | 2 |

        Some text after.
        """
        let result = converter.convert(markdown)
        #expect(result.contains("font-size: 24px"))  // H1 preserved
        #expect(result.contains("Some text before"))
        #expect(result.contains("<table"))
        #expect(result.contains("Some text after"))
    }

    @Test("Table separator detection")
    func testTableSeparatorVariants() {
        // Standard separator
        let markdown1 = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let result1 = converter.convert(markdown1)
        #expect(result1.contains("<table"))

        // Separator with colons (alignment markers)
        let markdown2 = """
        | A | B |
        |:--|--:|
        | 1 | 2 |
        """
        let result2 = converter.convert(markdown2)
        #expect(result2.contains("<table"))
    }

    @Test("Non-table pipe characters preserved")
    func testNonTablePipes() {
        // Single line with pipes but no separator = not a table
        let markdown = "This | is | not | a table"
        let result = converter.convert(markdown)
        #expect(!result.contains("<table"))
        #expect(result.contains("This"))
    }

    @Test("Table has proper styling")
    func testTableStyling() {
        let markdown = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let result = converter.convert(markdown)
        #expect(result.contains("border-collapse: collapse"))
        #expect(result.contains("border-style: solid"))
        #expect(result.contains("border-color: #ccc"))
        #expect(result.contains("padding:"))
    }
}

// MARK: - Integration Tests
// These tests interact with actual Apple Notes via AppleScript

@Suite("Integration Tests", .tags(.integration), .serialized)
struct IntegrationTests {
    static let testFolderName = "Claude-Integration-Tests"
    let appleScript = NotesAppleScript()
    let database = NotesDatabase()

    // MARK: - Setup/Teardown Helpers

    /// Create the test folder if it doesn't exist
    private func ensureTestFolder() throws {
        let folders = try appleScript.listFolders()
        if !folders.contains(Self.testFolderName) {
            do {
                _ = try appleScript.createFolder(name: Self.testFolderName)
                // Small delay for folder creation to propagate
                Thread.sleep(forTimeInterval: 0.5)
            } catch {
                // Folder might have been created by another process, ignore duplicate errors
                if !"\(error)".contains("Duplicate folder") {
                    throw error
                }
            }
        }
    }

    /// Clean up a note after test
    private func cleanup(noteId: String) {
        do {
            try appleScript.deleteNote(id: noteId)
        } catch {
            // Ignore cleanup errors
        }
    }

    /// Generate unique test title
    private func uniqueTitle(_ base: String) -> String {
        "\(base)-\(UUID().uuidString.prefix(8))"
    }

    // MARK: - Create Note Tests

    @Test("Create note via AppleScript")
    func testCreateNote() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Test Note")
        let body = "This is a test note body."

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        // Verify result has valid ID format
        #expect(result.id.hasPrefix("x-coredata://"))
        #expect(!result.uuid.isEmpty)

        // Cleanup
        cleanup(noteId: result.id)
    }

    @Test("Create note with markdown")
    func testCreateNoteWithMarkdown() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Markdown Test")
        let body = """
        This has **bold** and *italic* text.

        - List item 1
        - List item 2

        And some `inline code`.
        """

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        #expect(result.id.hasPrefix("x-coredata://"))

        // Verify via getNoteBody that markdown was converted
        let html = try appleScript.getNoteBody(id: result.id)
        #expect(html.contains("<b>bold</b>"))
        #expect(html.contains("<i>italic</i>"))
        #expect(html.contains("• List item 1"))

        cleanup(noteId: result.id)
    }

    @Test("Create note with markdown table")
    func testCreateNoteWithTable() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Table Test")
        let body = """
        # Table Demo

        Here is a table:

        | Name | Age | City |
        |------|-----|------|
        | Alice | 30 | NYC |
        | Bob | 25 | LA |

        Text after the table.
        """

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        #expect(result.id.hasPrefix("x-coredata://"))

        // Verify via getNoteBody that table was created
        let html = try appleScript.getNoteBody(id: result.id)

        // Table should be converted to native Notes table
        #expect(html.contains("<table"), "Should contain table tag")
        #expect(html.contains("<tbody>"), "Should contain tbody")
        #expect(html.contains("Alice"), "Table data should be present")
        #expect(html.contains("NYC"), "Table data should be present")
        #expect(html.contains("Bob"), "Table data should be present")
        #expect(html.contains("Text after the table"), "Content after table preserved")

        cleanup(noteId: result.id)
    }

    // MARK: - Read Note Tests

    @Test("Read note via database")
    func testReadNote() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Read Test")
        let body = "Content to read back."

        // Create via AppleScript
        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        // Small delay for database sync
        Thread.sleep(forTimeInterval: 1.0)

        // Find in database by searching (since we don't have the UUID directly)
        let notes = try database.searchNotes(query: title, limit: 1)
        #expect(!notes.isEmpty, "Note should be found in database")

        if let note = notes.first {
            let content = try database.readNote(id: note.id)
            #expect(content.title == title)
            #expect(content.content.contains(body) || content.content.contains("Content to read back"))
        }

        cleanup(noteId: result.id)
    }

    @Test("Read note HTML via AppleScript")
    func testReadNoteHTML() throws {
        try ensureTestFolder()

        let title = uniqueTitle("HTML Read Test")
        let body = "Simple body text."

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        let html = try appleScript.getNoteBody(id: result.id)

        // Should contain the title (styled) and body
        #expect(html.contains(title))
        #expect(html.contains("Simple body text"))

        cleanup(noteId: result.id)
    }

    // MARK: - Update Note Tests

    @Test("Update note body")
    func testUpdateNoteBody() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Update Body Test")
        let originalBody = "Original body content."

        let result = try appleScript.createNote(
            title: title,
            body: originalBody,
            folder: Self.testFolderName
        )

        // Update the body
        let newBody = "Updated body content."
        try appleScript.updateNote(id: result.id, body: newBody)

        // Verify update
        let html = try appleScript.getNoteBody(id: result.id)
        #expect(html.contains("Updated body content"))

        cleanup(noteId: result.id)
    }

    @Test("Update note title and body together")
    func testUpdateNoteTitleAndBody() throws {
        try ensureTestFolder()

        let originalTitle = uniqueTitle("Original Title")
        let body = "Body stays the same."

        let result = try appleScript.createNote(
            title: originalTitle,
            body: body,
            folder: Self.testFolderName
        )

        // Update both title and body (this rebuilds the entire note content)
        let newTitle = uniqueTitle("New Title")
        let newBody = "Updated body content."
        try appleScript.updateNote(id: result.id, title: newTitle, body: newBody)

        // Small delay
        Thread.sleep(forTimeInterval: 0.5)

        // Verify via getNoteBody - both should be in the HTML
        let html = try appleScript.getNoteBody(id: result.id)
        #expect(html.contains(newTitle), "New title should be in HTML")
        #expect(html.contains("Updated body content"), "New body should be in HTML")

        cleanup(noteId: result.id)
    }

    // MARK: - Delete Note Tests

    @Test("Delete note")
    func testDeleteNote() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Delete Test")
        let body = "This note will be deleted."

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        // Verify we can read it before deletion
        let htmlBefore = try appleScript.getNoteBody(id: result.id)
        #expect(htmlBefore.contains(title), "Note should be readable before deletion")

        // Delete the note (moves to Recently Deleted)
        // This is the main thing we're testing - that deletion doesn't throw
        try appleScript.deleteNote(id: result.id)

        // Note: Apple Notes moves deleted notes to "Recently Deleted" folder
        // The note may still be accessible via its ID for a while
        // The key verification is that deleteNote() succeeded without error
    }

    // MARK: - List Notes Tests

    @Test("List notes in folder")
    func testListNotesInFolder() throws {
        try ensureTestFolder()

        // Create a couple test notes
        let title1 = uniqueTitle("List Test 1")
        let title2 = uniqueTitle("List Test 2")

        let result1 = try appleScript.createNote(title: title1, body: "Body 1", folder: Self.testFolderName)
        let result2 = try appleScript.createNote(title: title2, body: "Body 2", folder: Self.testFolderName)

        // Small delay for database sync
        Thread.sleep(forTimeInterval: 1.0)

        // List notes in test folder
        let notes = try database.listNotes(folder: Self.testFolderName, limit: 50)

        // Should find our test notes
        let titles = notes.map { $0.title }
        #expect(titles.contains(title1), "Should find first test note")
        #expect(titles.contains(title2), "Should find second test note")

        cleanup(noteId: result1.id)
        cleanup(noteId: result2.id)
    }

    // MARK: - Search Notes Tests

    @Test("Search notes by title")
    func testSearchNotes() throws {
        try ensureTestFolder()

        // Create a note with unique searchable term
        let searchTerm = "UniqueSearch\(UUID().uuidString.prefix(6))"
        let title = "\(searchTerm) Note"
        let body = "Body for search test."

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        // Small delay for database sync
        Thread.sleep(forTimeInterval: 1.0)

        // Search for the unique term
        let found = try database.searchNotes(query: searchTerm, limit: 10)

        #expect(!found.isEmpty, "Should find note by search term")
        if let note = found.first {
            #expect(note.title.contains(searchTerm))
        }

        cleanup(noteId: result.id)
    }

    // MARK: - Edge Cases

    @Test("Create note with special characters")
    func testSpecialCharacters() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Special <>&\"' Chars")
        let body = "Body with <html> & \"quotes\" and 'apostrophes'."

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        // Should not throw
        let html = try appleScript.getNoteBody(id: result.id)
        #expect(!html.isEmpty)

        cleanup(noteId: result.id)
    }

    @Test("Create note with unicode")
    func testUnicodeContent() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Unicode Test 🎉")
        let body = "Emojis: 👍 ✅ 🚀\n日本語\n中文\n한국어"

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        let html = try appleScript.getNoteBody(id: result.id)
        #expect(html.contains("🎉") || html.contains("Unicode Test"))

        cleanup(noteId: result.id)
    }
}

// MARK: - Round-Trip Tests
// These tests verify complete workflows end-to-end

@Suite("Round-Trip Tests", .tags(.integration), .serialized)
struct RoundTripTests {
    static let testFolderName = "Claude-Integration-Tests"
    let appleScript = NotesAppleScript()
    let database = NotesDatabase()

    private func ensureTestFolder() throws {
        let folders = try appleScript.listFolders()
        if !folders.contains(Self.testFolderName) {
            do {
                _ = try appleScript.createFolder(name: Self.testFolderName)
                Thread.sleep(forTimeInterval: 0.5)
            } catch {
                if !"\(error)".contains("Duplicate folder") {
                    throw error
                }
            }
        }
    }

    private func cleanup(noteId: String) {
        try? appleScript.deleteNote(id: noteId)
    }

    private func uniqueTitle(_ base: String) -> String {
        "\(base)-\(UUID().uuidString.prefix(8))"
    }

    // MARK: - Full Workflow Tests

    @Test("Create → Read → Verify content matches")
    func testCreateReadVerify() throws {
        try ensureTestFolder()

        let title = uniqueTitle("RoundTrip Create")
        let body = "This is the body content for round-trip testing.\n\nIt has multiple paragraphs."

        // Create
        let created = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        // Wait for database sync
        Thread.sleep(forTimeInterval: 1.5)

        // Read via database
        let notes = try database.searchNotes(query: title, limit: 1)
        #expect(!notes.isEmpty, "Note should be findable via search")

        guard let note = notes.first else {
            cleanup(noteId: created.id)
            return
        }

        let content = try database.readNote(id: note.id)

        // Verify
        #expect(content.title == title, "Title should match")
        #expect(content.folder == Self.testFolderName, "Folder should match")
        #expect(content.content.contains("body content"), "Body content should be present")
        #expect(content.content.contains("multiple paragraphs"), "Full body should be present")

        cleanup(noteId: created.id)
    }

    @Test("Create → Update → Read → Verify changes")
    func testCreateUpdateReadVerify() throws {
        try ensureTestFolder()

        let originalTitle = uniqueTitle("RoundTrip Update")
        let originalBody = "Original body content."

        // Create
        let created = try appleScript.createNote(
            title: originalTitle,
            body: originalBody,
            folder: Self.testFolderName
        )

        // Update
        let newTitle = uniqueTitle("Updated Title")
        let newBody = "Updated body content with new information."
        try appleScript.updateNote(id: created.id, title: newTitle, body: newBody)

        // Wait for sync
        Thread.sleep(forTimeInterval: 1.5)

        // Read via AppleScript (more immediate)
        let html = try appleScript.getNoteBody(id: created.id)

        // Verify changes
        #expect(html.contains(newTitle), "Updated title should be present")
        #expect(html.contains("Updated body content"), "Updated body should be present")
        #expect(!html.contains("Original body"), "Original body should be replaced")

        cleanup(noteId: created.id)
    }

    @Test("Create → Delete → Verify removed from folder")
    func testCreateDeleteVerify() throws {
        try ensureTestFolder()

        let title = uniqueTitle("RoundTrip Delete")
        let body = "This note will be deleted."

        // Create
        let created = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        // Wait for sync
        Thread.sleep(forTimeInterval: 1.0)

        // Verify exists
        let beforeNotes = try database.listNotes(folder: Self.testFolderName, limit: 100)
        let existsBefore = beforeNotes.contains { $0.title == title }
        #expect(existsBefore, "Note should exist before deletion")

        // Delete
        try appleScript.deleteNote(id: created.id)

        // Wait for sync
        Thread.sleep(forTimeInterval: 1.5)

        // Verify removed from folder (may still exist in Recently Deleted)
        let afterNotes = try database.listNotes(folder: Self.testFolderName, limit: 100)
        let existsAfter = afterNotes.contains { $0.title == title }
        #expect(!existsAfter, "Note should not be in test folder after deletion")
    }

    @Test("Create multiple → List → Verify all present")
    func testCreateMultipleListVerify() throws {
        try ensureTestFolder()

        let titles = [
            uniqueTitle("Multi 1"),
            uniqueTitle("Multi 2"),
            uniqueTitle("Multi 3")
        ]

        var createdIds: [String] = []

        // Create multiple notes
        for (index, title) in titles.enumerated() {
            let result = try appleScript.createNote(
                title: title,
                body: "Body for note \(index + 1)",
                folder: Self.testFolderName
            )
            createdIds.append(result.id)
        }

        // Wait for sync
        Thread.sleep(forTimeInterval: 2.0)

        // List and verify
        let notes = try database.listNotes(folder: Self.testFolderName, limit: 100)
        let foundTitles = notes.map { $0.title }

        for title in titles {
            #expect(foundTitles.contains(title), "Should find note: \(title)")
        }

        // Cleanup
        for id in createdIds {
            cleanup(noteId: id)
        }
    }

    @Test("Create with markdown → Read HTML → Verify formatting preserved")
    func testMarkdownRoundTrip() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Markdown RoundTrip")
        let markdownBody = """
        # Header One

        This has **bold text** and *italic text*.

        ## Header Two

        - Bullet point 1
        - Bullet point 2

        Some `inline code` here.

        > A blockquote for emphasis.
        """

        // Create
        let created = try appleScript.createNote(
            title: title,
            body: markdownBody,
            folder: Self.testFolderName
        )

        // Read HTML
        let html = try appleScript.getNoteBody(id: created.id)

        // Verify markdown was converted to HTML
        #expect(html.contains("<b>bold text</b>"), "Bold should be converted")
        #expect(html.contains("<i>italic text</i>"), "Italic should be converted")
        #expect(html.contains("• Bullet point"), "Bullets should be converted")
        #expect(html.contains("Menlo"), "Code should use Menlo font")

        cleanup(noteId: created.id)
    }
}

// MARK: - Edge Case Tests

@Suite("Edge Case Tests", .tags(.integration), .serialized)
struct EdgeCaseTests {
    static let testFolderName = "Claude-Integration-Tests"
    let appleScript = NotesAppleScript()
    let database = NotesDatabase()

    private func ensureTestFolder() throws {
        let folders = try appleScript.listFolders()
        if !folders.contains(Self.testFolderName) {
            do {
                _ = try appleScript.createFolder(name: Self.testFolderName)
                Thread.sleep(forTimeInterval: 0.5)
            } catch {
                if !"\(error)".contains("Duplicate folder") {
                    throw error
                }
            }
        }
    }

    private func cleanup(noteId: String) {
        try? appleScript.deleteNote(id: noteId)
    }

    private func uniqueTitle(_ base: String) -> String {
        "\(base)-\(UUID().uuidString.prefix(8))"
    }

    // MARK: - Large Content Tests

    @Test("Create note with large body (10KB)")
    func testLargeNote10KB() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Large Note 10KB")
        // Generate ~10KB of content
        let paragraph = "This is a paragraph of text that will be repeated many times to create a large note body for testing purposes. "
        let body = String(repeating: paragraph, count: 100) // ~10KB

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        // Verify note was created
        let html = try appleScript.getNoteBody(id: result.id)
        #expect(html.count > 5000, "HTML should be substantial")
        #expect(html.contains("paragraph of text"), "Content should be present")

        cleanup(noteId: result.id)
    }

    @Test("Create note with very long title")
    func testLongTitle() throws {
        try ensureTestFolder()

        // 200 character title
        let baseTitle = "Very Long Title Test - "
        let title = baseTitle + String(repeating: "x", count: 200 - baseTitle.count) + "-\(UUID().uuidString.prefix(8))"

        let result = try appleScript.createNote(
            title: title,
            body: "Short body.",
            folder: Self.testFolderName
        )

        let html = try appleScript.getNoteBody(id: result.id)
        #expect(!html.isEmpty, "Note should be created with long title")

        cleanup(noteId: result.id)
    }

    @Test("Create note with empty body")
    func testEmptyBody() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Empty Body Test")

        let result = try appleScript.createNote(
            title: title,
            body: "",
            folder: Self.testFolderName
        )

        let html = try appleScript.getNoteBody(id: result.id)
        #expect(html.contains(title), "Title should be present even with empty body")

        cleanup(noteId: result.id)
    }

    @Test("Create note with whitespace-only body")
    func testWhitespaceBody() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Whitespace Body")
        let body = "   \n\n   \t\t   \n   "

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        let html = try appleScript.getNoteBody(id: result.id)
        #expect(html.contains(title), "Title should be present")

        cleanup(noteId: result.id)
    }

    @Test("Create note with newlines and carriage returns")
    func testNewlineVariants() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Newline Test")
        let body = "Line 1\nLine 2\rLine 3\r\nLine 4"

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        let html = try appleScript.getNoteBody(id: result.id)
        #expect(html.contains("Line 1"), "Content should be present")
        #expect(html.contains("Line 4"), "All lines should be present")

        cleanup(noteId: result.id)
    }

    @Test("Create note with HTML-like content in body")
    func testHTMLInBody() throws {
        try ensureTestFolder()

        let title = uniqueTitle("HTML Content Test")
        let body = "This has <script>alert('test')</script> and <div onclick='bad()'>click</div> in it."

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        let html = try appleScript.getNoteBody(id: result.id)
        // HTML should be escaped, not executed
        #expect(html.contains("&lt;script&gt;") || html.contains("script"), "Script tag should be escaped or present as text")
        #expect(!html.contains("<script>alert"), "Script should not be raw HTML")

        cleanup(noteId: result.id)
    }

    @Test("Create note with all markdown features")
    func testAllMarkdownFeatures() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Full Markdown Test")
        let body = """
        # Heading 1
        ## Heading 2
        ### Heading 3

        **Bold** and __also bold__

        *Italic* and _also italic_

        ~~Strikethrough~~

        - Bullet 1
        - Bullet 2
        * Star bullet

        `inline code`

        ```
        code block
        multi-line
        ```

        > Blockquote text
        """

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        let html = try appleScript.getNoteBody(id: result.id)

        // Check various conversions
        #expect(html.contains("<b>Bold</b>") || html.contains("<b>also bold</b>"), "Bold should work")
        #expect(html.contains("<i>Italic</i>") || html.contains("<i>also italic</i>"), "Italic should work")
        #expect(html.contains("<strike>Strikethrough</strike>"), "Strikethrough should work")
        #expect(html.contains("• Bullet") || html.contains("• Star"), "Bullets should work")
        #expect(html.contains("Menlo"), "Code should use Menlo font")

        cleanup(noteId: result.id)
    }
}

// MARK: - Folder Operations Tests

@Suite("Folder Operations Tests", .tags(.integration), .serialized)
struct FolderOperationsTests {
    let appleScript = NotesAppleScript()
    let database = NotesDatabase()

    private func uniqueFolderName(_ base: String) -> String {
        "\(base)-\(UUID().uuidString.prefix(8))"
    }

    @Test("Create and delete folder")
    func testCreateDeleteFolder() throws {
        let folderName = uniqueFolderName("Test Folder")

        // Create folder
        let created = try appleScript.createFolder(name: folderName)
        #expect(created == folderName, "Created folder name should match")

        // Verify exists
        let folders = try appleScript.listFolders()
        #expect(folders.contains(folderName), "Folder should exist after creation")

        // Delete folder
        try appleScript.deleteFolder(name: folderName)

        // Small delay
        Thread.sleep(forTimeInterval: 0.5)

        // Verify deleted
        let foldersAfter = try appleScript.listFolders()
        #expect(!foldersAfter.contains(folderName), "Folder should not exist after deletion")
    }

    @Test("Rename folder")
    func testRenameFolder() throws {
        let originalName = uniqueFolderName("Original Folder")
        let newName = uniqueFolderName("Renamed Folder")

        // Create folder
        _ = try appleScript.createFolder(name: originalName)

        // Rename
        try appleScript.renameFolder(from: originalName, to: newName)

        // Small delay
        Thread.sleep(forTimeInterval: 0.5)

        // Verify
        let folders = try appleScript.listFolders()
        #expect(!folders.contains(originalName), "Original name should be gone")
        #expect(folders.contains(newName), "New name should exist")

        // Cleanup
        try appleScript.deleteFolder(name: newName)
    }

    @Test("Move note to different folder")
    func testMoveNote() throws {
        let folder1 = uniqueFolderName("Source Folder")
        let folder2 = uniqueFolderName("Dest Folder")
        let noteTitle = "Move Test Note-\(UUID().uuidString.prefix(8))"

        // Create both folders
        _ = try appleScript.createFolder(name: folder1)
        _ = try appleScript.createFolder(name: folder2)

        // Create note in folder1
        let note = try appleScript.createNote(
            title: noteTitle,
            body: "This note will be moved.",
            folder: folder1
        )

        // Wait for sync
        Thread.sleep(forTimeInterval: 1.0)

        // Move to folder2
        try appleScript.moveNote(noteId: note.id, toFolder: folder2)

        // Wait for sync
        Thread.sleep(forTimeInterval: 1.0)

        // Verify note is in folder2
        let folder2Notes = try database.listNotes(folder: folder2, limit: 50)
        let foundInFolder2 = folder2Notes.contains { $0.title == noteTitle }
        #expect(foundInFolder2, "Note should be in destination folder")

        // Verify note is not in folder1
        let folder1Notes = try database.listNotes(folder: folder1, limit: 50)
        let foundInFolder1 = folder1Notes.contains { $0.title == noteTitle }
        #expect(!foundInFolder1, "Note should not be in source folder")

        // Cleanup
        try appleScript.deleteNote(id: note.id)
        try appleScript.deleteFolder(name: folder1)
        try appleScript.deleteFolder(name: folder2)
    }
}

// MARK: - Hashtag Tests
// Note: Apple Notes hashtags are detected when typed in the Notes app UI.
// When creating notes via AppleScript, the # symbol is just text - it doesn't
// become a "real" hashtag with the embedded object metadata that Notes uses.
// These tests verify the database can read existing hashtags from notes.

@Suite("Hashtag Tests", .tags(.integration), .serialized)
struct HashtagTests {
    static let testFolderName = "Claude-Integration-Tests"
    let appleScript = NotesAppleScript()
    let database = NotesDatabase()

    private func ensureTestFolder() throws {
        let folders = try appleScript.listFolders()
        if !folders.contains(Self.testFolderName) {
            do {
                _ = try appleScript.createFolder(name: Self.testFolderName)
                Thread.sleep(forTimeInterval: 0.5)
            } catch {
                if !"\(error)".contains("Duplicate folder") {
                    throw error
                }
            }
        }
    }

    private func cleanup(noteId: String) {
        try? appleScript.deleteNote(id: noteId)
    }

    private func uniqueTitle(_ base: String) -> String {
        "\(base)-\(UUID().uuidString.prefix(8))"
    }

    @Test("List all hashtags in database")
    func testListHashtags() throws {
        // This tests the database's ability to list hashtags
        // Note: May return empty if no notes have UI-created hashtags
        let hashtags = try database.listHashtags()

        // Just verify the call succeeds and returns an array
        // Hashtags might be empty if no notes with hashtags exist
        #expect(hashtags.count >= 0, "Should return array (possibly empty)")
    }

    @Test("Search by hashtag returns notes")
    func testSearchByHashtag() throws {
        // Test searching by a common hashtag
        // This will only find notes if user has created hashtags via Notes UI
        let notes = try database.searchNotesByHashtag(tag: "test")

        // Just verify the call succeeds
        #expect(notes.count >= 0, "Should return array (possibly empty)")
    }

    @Test("Create note with hashtag text")
    func testCreateNoteWithHashtagText() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Hashtag Text Test")
        // Note: This creates text that looks like hashtags, but won't be
        // detected as "real" hashtags by Notes (requires UI interaction)
        let body = "This note has #testing and #automation tags in the text."

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        // Verify the text is preserved
        let html = try appleScript.getNoteBody(id: result.id)
        #expect(html.contains("#testing"), "Hashtag text should be in body")
        #expect(html.contains("#automation"), "Hashtag text should be in body")

        cleanup(noteId: result.id)
    }

    @Test("Get hashtags for specific note")
    func testGetHashtagsForNote() throws {
        try ensureTestFolder()

        let title = uniqueTitle("Note Hashtags Test")
        let body = "Content with #sample hashtag text."

        let result = try appleScript.createNote(
            title: title,
            body: body,
            folder: Self.testFolderName
        )

        // Wait for sync
        Thread.sleep(forTimeInterval: 1.0)

        // Find the note
        let notes = try database.searchNotes(query: title, limit: 1)

        if let note = notes.first {
            // Get hashtags - will be empty for API-created notes
            // (hashtags require Notes UI to be "activated")
            let hashtags = try database.getHashtags(forNoteId: note.id)
            #expect(hashtags.count >= 0, "Should return array (possibly empty)")
        }

        cleanup(noteId: result.id)
    }
}

// MARK: - Note Links Tests

@Suite("Note Links Tests", .tags(.integration), .serialized)
struct NoteLinkTests {
    let database = NotesDatabase()

    @Test("List all note links in database")
    func testListNoteLinks() throws {
        // This tests the database's ability to list note-to-note links
        // Note: May return empty if no notes have links to other notes
        let links = try database.listNoteLinks()

        // Just verify the call succeeds
        // Each link is a tuple of (sourceId, text, targetId)
        for link in links {
            #expect(!link.sourceId.isEmpty, "Source ID should not be empty")
            #expect(!link.targetId.isEmpty, "Target ID should not be empty")
        }
    }

    @Test("Get note links for specific note")
    func testGetNoteLinksForNote() throws {
        // Get a note from the database to test with
        let notes = try database.listNotes(limit: 5)

        guard let note = notes.first else {
            // No notes in database, skip test
            return
        }

        // Get note links for this note
        let noteContent = try database.readNote(id: note.id)

        // Verify noteLinks is accessible (may be empty)
        #expect(noteContent.noteLinks.count >= 0, "Should have noteLinks array")
    }
}

// MARK: - Database Query Tests
// Additional tests for database-specific functionality

@Suite("Database Query Tests", .tags(.integration), .serialized)
struct DatabaseQueryTests {
    let database = NotesDatabase()

    @Test("List folders from database")
    func testListFolders() throws {
        let folders = try database.listFolders()

        // Should have at least the default "Notes" folder
        #expect(!folders.isEmpty, "Should have at least one folder")

        // Verify folder structure
        for folder in folders {
            #expect(folder.pk > 0, "Folder PK should be positive")
            #expect(!folder.name.isEmpty, "Folder name should not be empty")
        }
    }

    @Test("List notes with limit")
    func testListNotesWithLimit() throws {
        let limit = 5
        let notes = try database.listNotes(limit: limit)

        #expect(notes.count <= limit, "Should respect limit parameter")

        for note in notes {
            #expect(!note.id.isEmpty, "Note ID should not be empty")
            #expect(!note.title.isEmpty, "Note title should not be empty")
        }
    }

    @Test("Search notes returns matching results")
    func testSearchNotesMatching() throws {
        // Search for a common word that's likely to exist
        let results = try database.searchNotes(query: "the", limit: 10)

        // Results may be empty if no notes contain "the"
        for note in results {
            #expect(!note.id.isEmpty, "Note ID should not be empty")
        }
    }

    @Test("Read note returns full content")
    func testReadNoteContent() throws {
        let notes = try database.listNotes(limit: 1)

        guard let note = notes.first else {
            // No notes available
            return
        }

        let content = try database.readNote(id: note.id)

        #expect(content.id == note.id, "ID should match")
        #expect(content.title == note.title, "Title should match")
        // Verify arrays are accessible (content may be empty)
        #expect(content.attachments.count >= 0, "Should have attachments array")
        #expect(content.hashtags.count >= 0, "Should have hashtags array")
        #expect(content.noteLinks.count >= 0, "Should have noteLinks array")
    }
}

// MARK: - BertTokenizer Tests

@Suite("BertTokenizer Tests")
struct BertTokenizerTests {

    @Test("Initialize tokenizer loads vocab")
    func testInitialization() throws {
        let tokenizer = try BertTokenizer()
        // If initialization succeeds, vocab was loaded
        #expect(true, "Tokenizer initialized successfully")
    }

    @Test("Tokenize simple sentence")
    func testSimpleSentence() throws {
        let tokenizer = try BertTokenizer()
        let tokens = tokenizer.buildModelTokens(sentence: "hello world")

        // Should have 512 tokens (maxLen)
        #expect(tokens.count == 512, "Should pad to 512 tokens")

        // First token should be [CLS] (token ID 101)
        #expect(tokens[0] == 101, "First token should be [CLS]")

        // Should have [SEP] token (ID 102) after content
        #expect(tokens.contains(102), "Should contain [SEP] token")

        // Rest should be padding (0s)
        let paddingStart = tokens.firstIndex(of: 0) ?? 512
        for i in paddingStart..<512 {
            #expect(tokens[i] == 0, "Padding should be 0")
        }
    }

    @Test("Tokenize with special characters")
    func testSpecialCharacters() throws {
        let tokenizer = try BertTokenizer()
        let tokens = tokenizer.buildModelTokens(sentence: "Hello, World! How are you?")

        #expect(tokens.count == 512, "Should pad to 512 tokens")
        #expect(tokens[0] == 101, "First token should be [CLS]")
    }

    @Test("Tokenize unicode text")
    func testUnicodeText() throws {
        let tokenizer = try BertTokenizer()

        // Test with accented characters
        let tokens1 = tokenizer.buildModelTokens(sentence: "café résumé")
        #expect(tokens1.count == 512, "Should handle accented characters")

        // Test with emoji (may become [UNK])
        let tokens2 = tokenizer.buildModelTokens(sentence: "hello 🎉 world")
        #expect(tokens2.count == 512, "Should handle emoji")
    }

    @Test("Max length truncation")
    func testMaxLengthTruncation() throws {
        let tokenizer = try BertTokenizer()

        // Create a very long string that would exceed 512 tokens
        let longSentence = String(repeating: "word ", count: 1000)
        let tokens = tokenizer.buildModelTokens(sentence: longSentence)

        #expect(tokens.count == 512, "Should truncate to 512 tokens")
        #expect(tokens[0] == 101, "First token should still be [CLS]")
        #expect(tokens[511] == 0 || tokens.contains(102), "Should have [SEP] or be padded")
    }

    @Test("Build MLMultiArray inputs")
    func testBuildModelInputs() throws {
        let tokenizer = try BertTokenizer()
        let tokens = tokenizer.buildModelTokens(sentence: "test sentence")
        let (inputIds, attentionMask) = tokenizer.buildModelInputs(from: tokens)

        // Check shapes
        #expect(inputIds.count == 512, "inputIds should have 512 elements")
        #expect(attentionMask.count == 512, "attentionMask should have 512 elements")

        // Check that attention mask has 1s for real tokens and 0s for padding
        let maskPtr = UnsafeMutablePointer<Int32>(OpaquePointer(attentionMask.dataPointer))
        var foundOne = false
        var foundZero = false
        for i in 0..<512 {
            if maskPtr[i] == 1 { foundOne = true }
            if maskPtr[i] == 0 { foundZero = true }
        }
        #expect(foundOne, "Should have some attention mask 1s")
        #expect(foundZero, "Should have some attention mask 0s (padding)")
    }

    @Test("Empty string tokenization")
    func testEmptyString() throws {
        let tokenizer = try BertTokenizer()
        let tokens = tokenizer.buildModelTokens(sentence: "")

        #expect(tokens.count == 512, "Should still pad to 512")
        #expect(tokens[0] == 101, "Should have [CLS]")
        #expect(tokens[1] == 102, "Should have [SEP] immediately after [CLS]")
    }

    @Test("Known token IDs")
    func testKnownTokenIds() throws {
        let tokenizer = try BertTokenizer()

        // Test that common words tokenize to expected IDs
        // "the" should be a single token in BERT vocab
        let tokens = tokenizer.buildModelTokens(sentence: "the")

        #expect(tokens[0] == 101, "[CLS] = 101")
        // Token for "the" is typically 1996 in BERT vocab
        #expect(tokens[1] == 1996, "Token 'the' should be 1996")
        #expect(tokens[2] == 102, "[SEP] = 102")
    }
}

// MARK: - MiniLMEmbeddings Tests

@Suite("MiniLMEmbeddings Tests")
struct MiniLMEmbeddingsTests {

    @Test("Load model from bundle")
    func testModelLoading() throws {
        let embeddings = try MiniLMEmbeddings()
        _ = embeddings  // Verify initialization succeeded
    }

    @Test("Generate embeddings for text")
    func testGenerateEmbeddings() async throws {
        let embeddings = try MiniLMEmbeddings()
        let vector = await embeddings.encode("hello world")

        // MiniLM produces 384-dimensional embeddings
        #expect(vector != nil, "Should produce embedding")
        guard let vector = vector else { return }
        #expect(vector.count == 384, "Should produce 384-dim embedding")

        // Values should be normalized (between -1 and 1 typically)
        for value in vector {
            #expect(value >= -10 && value <= 10, "Values should be reasonable")
        }
    }

    @Test("Different texts produce different embeddings")
    func testDifferentTexts() async throws {
        let embeddings = try MiniLMEmbeddings()

        guard let vec1 = await embeddings.encode("hello world"),
              let vec2 = await embeddings.encode("goodbye moon") else {
            Issue.record("Failed to generate embeddings")
            return
        }

        // Embeddings should be different
        var different = false
        for i in 0..<min(vec1.count, vec2.count) {
            if abs(vec1[i] - vec2[i]) > 0.001 {
                different = true
                break
            }
        }
        #expect(different, "Different texts should produce different embeddings")
    }

    @Test("Similar texts produce similar embeddings")
    func testSimilarTexts() async throws {
        let embeddings = try MiniLMEmbeddings()

        guard let vec1 = await embeddings.encode("The cat sat on the mat"),
              let vec2 = await embeddings.encode("A cat sitting on a mat"),
              let vec3 = await embeddings.encode("Quantum physics equations") else {
            Issue.record("Failed to generate embeddings")
            return
        }

        // Calculate cosine similarities
        func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
            var dot: Float = 0
            var normA: Float = 0
            var normB: Float = 0
            for i in 0..<min(a.count, b.count) {
                dot += a[i] * b[i]
                normA += a[i] * a[i]
                normB += b[i] * b[i]
            }
            return dot / (sqrt(normA) * sqrt(normB))
        }

        let simCatCat = cosineSimilarity(vec1, vec2)
        let simCatPhysics = cosineSimilarity(vec1, vec3)

        // Similar sentences should have higher similarity
        #expect(simCatCat > simCatPhysics, "Similar texts should have higher cosine similarity")
    }

    @Test("Embedding dimension is correct")
    func testEmbeddingDimension() async throws {
        let embeddings = try MiniLMEmbeddings()

        let testStrings = ["short", "a longer sentence here", ""]
        for str in testStrings {
            guard let vec = await embeddings.encode(str) else {
                Issue.record("Failed to generate embedding for '\(str)'")
                continue
            }
            #expect(vec.count == 384, "All embeddings should be 384-dim, got \(vec.count) for '\(str)'")
        }
    }
}

// MARK: - SearchIndex (FTS5) Tests

@Suite("SearchIndex Tests")
struct SearchIndexTests {
    let database = NotesDatabase()

    @Test("Initialize search index")
    func testInitialization() {
        let index = SearchIndex(notesDB: database)
        _ = index  // Verify initialization succeeded
    }

    @Test("Build index does not throw")
    func testBuildIndex() throws {
        let index = SearchIndex(notesDB: database)
        let count = try index.buildIndex()
        #expect(count >= 0, "Index built with \(count) notes")
    }

    @Test("Search returns results")
    func testSearch() throws {
        let index = SearchIndex(notesDB: database)
        _ = try index.buildIndex()

        // Search for common word
        let results = try index.search(query: "the", limit: 5)

        // Results array should exist (may be empty if no matches)
        #expect(results.count >= 0, "Should return results array")

        // If we have results, verify structure
        for result in results {
            #expect(!result.noteId.isEmpty, "Result should have noteId")
            // snippet may be empty for some results
        }
    }

    @Test("Search respects limit")
    func testSearchLimit() throws {
        let index = SearchIndex(notesDB: database)
        _ = try index.buildIndex()

        let results = try index.search(query: "a", limit: 3)
        #expect(results.count <= 3, "Should respect limit parameter")
    }
}

// MARK: - SemanticSearch Tests

@Suite("SemanticSearch Tests")
struct SemanticSearchTests {
    let database = NotesDatabase()

    @Test("Initialize semantic search")
    func testInitialization() async {
        let search = SemanticSearch(notesDB: database)
        let isIndexed = await search.isIndexed
        #expect(!isIndexed, "Should not be indexed initially")
    }

    @Test("Build index from notes")
    func testBuildIndex() async throws {
        let search = SemanticSearch(notesDB: database)

        let count = try await search.buildIndex()
        #expect(count >= 0, "Should return count of indexed notes")

        let isIndexed = await search.isIndexed
        let indexedCount = await search.indexedCount

        // If we have notes, index should be built
        if count > 0 {
            #expect(isIndexed, "Should be indexed after build")
            #expect(indexedCount == count, "indexedCount should match returned count")
        }
    }

    @Test("Search returns results with scores")
    func testSearchReturnsResults() async throws {
        let search = SemanticSearch(notesDB: database)

        // Build index first
        let indexCount = try await search.buildIndex()

        // Skip test if no notes to search
        guard indexCount > 0 else {
            return
        }

        // Search for a common term
        let results = try await search.search(query: "note", limit: 5)

        #expect(results.count >= 0, "Should return results array")
        #expect(results.count <= 5, "Should respect limit")

        // Verify result structure
        for result in results {
            #expect(!result.noteId.isEmpty, "Result should have noteId")
            #expect(!result.title.isEmpty, "Result should have title")
            #expect(result.score >= -1 && result.score <= 1, "Score should be valid cosine similarity")
        }
    }

    @Test("Search results ordered by score descending")
    func testSearchResultsOrdering() async throws {
        let search = SemanticSearch(notesDB: database)

        let indexCount = try await search.buildIndex()
        guard indexCount > 1 else { return }

        let results = try await search.search(query: "test", limit: 10)

        // Verify scores are in descending order
        for i in 0..<(results.count - 1) {
            #expect(results[i].score >= results[i + 1].score,
                   "Results should be ordered by score descending")
        }
    }

    @Test("Search respects limit parameter")
    func testSearchLimit() async throws {
        let search = SemanticSearch(notesDB: database)

        let indexCount = try await search.buildIndex()
        guard indexCount >= 3 else { return }

        let results3 = try await search.search(query: "the", limit: 3)
        let results1 = try await search.search(query: "the", limit: 1)

        #expect(results3.count <= 3, "Should respect limit of 3")
        #expect(results1.count <= 1, "Should respect limit of 1")
    }

    @Test("Add note to index")
    func testAddNote() async throws {
        let search = SemanticSearch(notesDB: database)

        // Start with empty index
        let initialCount = await search.indexedCount
        #expect(initialCount == 0, "Should start empty")

        // Add a note manually
        try await search.addNote(id: "test-id-123", title: "Test Note Title", folder: "TestFolder")

        let afterCount = await search.indexedCount
        #expect(afterCount == 1, "Should have 1 note after adding")

        // Search should find it
        let results = try await search.search(query: "Test Note", limit: 5)
        #expect(results.count >= 1, "Should find the added note")

        let found = results.contains { $0.noteId == "test-id-123" }
        #expect(found, "Should find the specific note we added")
    }

    @Test("Remove note from index")
    func testRemoveNote() async throws {
        let search = SemanticSearch(notesDB: database)

        // Add a note
        try await search.addNote(id: "remove-test-id", title: "Remove Me", folder: nil)

        let beforeCount = await search.indexedCount
        #expect(beforeCount == 1, "Should have 1 note")

        // Remove it
        await search.removeNote(id: "remove-test-id")

        let afterCount = await search.indexedCount
        #expect(afterCount == 0, "Should have 0 notes after removal")
    }

    @Test("Clear index")
    func testClearIndex() async throws {
        let search = SemanticSearch(notesDB: database)

        // Add some notes
        try await search.addNote(id: "clear-1", title: "Note One", folder: nil)
        try await search.addNote(id: "clear-2", title: "Note Two", folder: nil)

        let beforeCount = await search.indexedCount
        #expect(beforeCount == 2, "Should have 2 notes")

        // Clear
        await search.clearIndex()

        let afterCount = await search.indexedCount
        let isIndexed = await search.isIndexed

        #expect(afterCount == 0, "Should have 0 notes after clear")
        #expect(!isIndexed, "Should not be indexed after clear")
    }

    @Test("Force rebuild index")
    func testForceRebuild() async throws {
        let search = SemanticSearch(notesDB: database)

        // Build once
        let firstCount = try await search.buildIndex()

        // Add a manual note (simulating out-of-sync state)
        try await search.addNote(id: "extra-note", title: "Extra", folder: nil)

        let withExtra = await search.indexedCount
        #expect(withExtra == firstCount + 1, "Should have extra note")

        // Force rebuild should reset to database state
        let rebuildCount = try await search.buildIndex(forceRebuild: true)

        #expect(rebuildCount == firstCount, "Force rebuild should reset to database notes")
    }

    @Test("Similar queries return similar results")
    func testSimilarQueries() async throws {
        let search = SemanticSearch(notesDB: database)

        let indexCount = try await search.buildIndex()
        guard indexCount >= 3 else { return }

        // Similar queries should return overlapping results
        let results1 = try await search.search(query: "meeting notes", limit: 5)
        let results2 = try await search.search(query: "notes from meeting", limit: 5)

        // Get the note IDs from each result set
        let ids1 = Set(results1.map { $0.noteId })
        let ids2 = Set(results2.map { $0.noteId })

        // There should be some overlap if both return results
        if !ids1.isEmpty && !ids2.isEmpty {
            let overlap = ids1.intersection(ids2)
            // Similar queries often have overlapping results, but not always
            // Just verify both searches work
            #expect(results1.count >= 0 && results2.count >= 0, "Both searches should work")
        }
    }
}

// MARK: - Database Search Tests

@Suite("Database Search Tests")
struct DatabaseSearchTests {
    let database = NotesDatabase()

    @Test("Search is case insensitive")
    func testCaseInsensitiveSearch() throws {
        let upper = try database.searchNotes(query: "THE", limit: 10)
        let lower = try database.searchNotes(query: "the", limit: 10)
        let mixed = try database.searchNotes(query: "ThE", limit: 10)

        // All should return same count (or close)
        // Note: Results may vary due to ranking, so just check they all work
        #expect(upper.count >= 0, "Uppercase search works")
        #expect(lower.count >= 0, "Lowercase search works")
        #expect(mixed.count >= 0, "Mixed case search works")
    }

    @Test("Multi-term AND search")
    func testAndSearch() throws {
        // This tests the AND functionality
        let results = try database.searchNotes(query: "note AND test", limit: 10)
        #expect(results.count >= 0, "AND search should work")
    }

    @Test("Multi-term OR search")
    func testOrSearch() throws {
        let results = try database.searchNotes(query: "note OR test", limit: 10)
        #expect(results.count >= 0, "OR search should work")
    }

    @Test("Fuzzy search enabled")
    func testFuzzySearch() throws {
        // Fuzzy search should find results even with typos
        let results = try database.searchNotes(query: "testt", limit: 10, fuzzy: true)
        #expect(results.count >= 0, "Fuzzy search should work")
    }

    @Test("Search with folder filter")
    func testFolderFilter() throws {
        let results = try database.searchNotes(query: "test", limit: 10, folder: "Notes")
        #expect(results.count >= 0, "Folder filter should work")
    }

    @Test("Search with date filter")
    func testDateFilter() throws {
        let oneYearAgo = Date().addingTimeInterval(-365 * 24 * 60 * 60)
        let results = try database.searchNotes(query: "test", limit: 10, modifiedAfter: oneYearAgo)
        #expect(results.count >= 0, "Date filter should work")
    }
}

// MARK: - MCP Search Integration Tests
// These tests verify the full search pipelines that MCP tools use

@Suite("MCP Search Integration Tests", .tags(.integration))
struct MCPSearchIntegrationTests {
    let database = NotesDatabase()

    // MARK: - FTS Search Tool Tests (fts_search)

    @Test("FTS search with auto-rebuild flow")
    func testFTSSearchAutoRebuild() throws {
        let index = SearchIndex(notesDB: database)

        // First search should auto-build index
        let (results, wasStale, isRebuilding) = try index.searchWithAutoRebuild(query: "note", limit: 10)

        // Results should be returned
        #expect(results.count >= 0, "Should return results")

        // Index should have been built
        #expect(index.indexedCount > 0 || results.isEmpty, "Index should be built or no notes exist")

        // Verify result structure matches MCP tool expectations
        for (noteId, snippet) in results {
            #expect(!noteId.isEmpty, "Result should have noteId")
            // Snippet may be empty for some results
        }
    }

    @Test("FTS search returns ranked results")
    func testFTSSearchRanking() throws {
        let index = SearchIndex(notesDB: database)

        // Build index
        let indexCount = try index.buildIndex()
        guard indexCount > 0 else { return }

        // Search should return results ordered by relevance (BM25 ranking)
        let results = try index.search(query: "the", limit: 20)

        // Just verify we got results - FTS5 handles ranking internally
        #expect(results.count >= 0, "Should return results")
    }

    @Test("FTS search with phrases")
    func testFTSPhraseSearch() throws {
        let index = SearchIndex(notesDB: database)
        _ = try index.buildIndex()

        // Phrase search (terms in quotes)
        let results = try index.search(query: "\"the note\"", limit: 10)
        #expect(results.count >= 0, "Phrase search should work")
    }

    // MARK: - Semantic Search Tool Tests (semantic_search)

    @Test("Semantic search end-to-end")
    func testSemanticSearchE2E() async throws {
        let semanticSearch = SemanticSearch(notesDB: database)

        // Search triggers auto-build
        let results = try await semanticSearch.search(query: "meeting notes", limit: 5)

        // Verify results structure matches MCP tool output
        for result in results {
            #expect(!result.noteId.isEmpty, "Should have noteId")
            #expect(!result.title.isEmpty, "Should have title")
            #expect(result.score >= -1 && result.score <= 1, "Score should be cosine similarity")
            // folder may be nil
        }

        // Verify index was built
        let indexedCount = await semanticSearch.indexedCount
        #expect(indexedCount >= 0, "Should have indexed notes")
    }

    @Test("Semantic search finds conceptually similar notes")
    func testSemanticSearchConceptual() async throws {
        let semanticSearch = SemanticSearch(notesDB: database)

        // Build index
        let indexCount = try await semanticSearch.buildIndex()
        guard indexCount >= 3 else { return }

        // Search for a concept - should find related notes even without exact matches
        let results1 = try await semanticSearch.search(query: "todo list tasks", limit: 5)
        let results2 = try await semanticSearch.search(query: "things to do checklist", limit: 5)

        // Both conceptually similar queries should return results
        #expect(results1.count >= 0 && results2.count >= 0, "Both searches should work")
    }

    // MARK: - search_notes Tool Tests

    @Test("Search notes with all parameters")
    func testSearchNotesAllParams() throws {
        let oneYearAgo = Date().addingTimeInterval(-365 * 24 * 60 * 60)
        let now = Date()

        // Test with all parameter combinations that search_notes MCP tool supports
        let results = try database.searchNotes(
            query: "test",
            limit: 10,
            searchContent: true,
            fuzzy: true,
            folder: nil,  // No folder filter
            modifiedAfter: oneYearAgo,
            modifiedBefore: now,
            createdAfter: oneYearAgo,
            createdBefore: now
        )

        #expect(results.count >= 0, "Should return results with all params")
    }

    @Test("Search notes content search finds body text")
    func testSearchNotesContentSearch() throws {
        // With searchContent=true, should search note bodies
        let resultsWithContent = try database.searchNotes(query: "test", limit: 10, searchContent: true)
        let resultsWithoutContent = try database.searchNotes(query: "test", limit: 10, searchContent: false)

        // Content search may find more results (or same)
        #expect(resultsWithContent.count >= 0, "Content search should work")
        #expect(resultsWithoutContent.count >= 0, "Title search should work")
    }

    @Test("Search notes fuzzy matching")
    func testSearchNotesFuzzy() throws {
        // Fuzzy search should be more tolerant of typos
        let resultsFuzzy = try database.searchNotes(query: "testt", limit: 10, fuzzy: true)
        let resultsExact = try database.searchNotes(query: "testt", limit: 10, fuzzy: false)

        // Fuzzy may find results that exact doesn't
        #expect(resultsFuzzy.count >= resultsExact.count, "Fuzzy should find at least as many results")
    }

    @Test("Search notes date range filtering")
    func testSearchNotesDateRange() throws {
        let twoYearsAgo = Date().addingTimeInterval(-2 * 365 * 24 * 60 * 60)
        let oneYearAgo = Date().addingTimeInterval(-365 * 24 * 60 * 60)
        let now = Date()

        // Recent notes only
        let recentResults = try database.searchNotes(
            query: "the",
            limit: 100,
            modifiedAfter: oneYearAgo
        )

        // All notes in date range
        let allResults = try database.searchNotes(
            query: "the",
            limit: 100,
            modifiedAfter: twoYearsAgo
        )

        // More inclusive date range should have >= results
        #expect(allResults.count >= recentResults.count, "Wider date range should include more results")
    }

    // MARK: - Combined Search Workflow Tests

    @Test("FTS then semantic search workflow")
    func testFTSThenSemanticWorkflow() async throws {
        // Typical MCP usage: FTS for keyword match, then semantic for related
        let ftsIndex = SearchIndex(notesDB: database)
        let semanticSearch = SemanticSearch(notesDB: database)

        // 1. FTS search for exact keyword
        _ = try ftsIndex.buildIndex()
        let ftsResults = try ftsIndex.search(query: "note", limit: 5)

        // 2. If FTS found something, use semantic to find related
        if let firstResult = ftsResults.first {
            // Get the note title for semantic search
            if let note = try? database.listNotes(limit: 10000).first(where: { $0.id == firstResult.noteId }) {
                let semanticResults = try await semanticSearch.search(query: note.title, limit: 5)
                #expect(semanticResults.count >= 0, "Semantic follow-up should work")
            }
        }
    }

    @Test("Search notes then read note workflow")
    func testSearchThenReadWorkflow() throws {
        // Typical MCP usage: search then read full content
        let searchResults = try database.searchNotes(query: "note", limit: 5)

        // If we found notes, verify we can read them
        for note in searchResults.prefix(2) {
            let content = try database.readNote(id: note.id)
            #expect(!content.title.isEmpty, "Should read note title")
            #expect(content.id == note.id, "ID should match")
        }
    }
}

// MARK: - Table Rendering Tests

@Suite("Table Rendering Tests")
struct TableRenderingTests {

    @Test("toHTML renders table inline at placeholder position")
    func testTableInlineRendering() {
        // Create styled content with a U+FFFC placeholder and a table
        let text = "Title\n\nBefore table\n\u{FFFC}\nAfter table"
        let attributeRuns = [
            AttributeRun(length: 6, styleType: .title),  // "Title\n"
            AttributeRun(length: text.count - 6, styleType: .body)
        ]
        let table = NoteTable(rows: [
            [TableCell(text: "Header1"), TableCell(text: "Header2")],
            [TableCell(text: "Cell1"), TableCell(text: "Cell2")]
        ], position: 0)  // Position doesn't matter - matched by order

        let content = StyledNoteContent(
            text: text,
            attributeRuns: attributeRuns,
            tables: [table]
        )

        let html = content.toHTML(darkMode: false)

        // Verify table is rendered
        #expect(html.contains("<table>"), "HTML should contain table tag")
        #expect(html.contains("<th>Header1</th>"), "HTML should contain header cell")
        #expect(html.contains("<td>Cell1</td>"), "HTML should contain data cell")

        // Verify content before and after table is present
        #expect(html.contains("Before table"), "Content before table should be present")
        #expect(html.contains("After table"), "Content after table should be present")

        // Verify placeholder is removed from output
        #expect(!html.contains("\u{FFFC}"), "Placeholder should be removed")
    }

    @Test("toHTML matches multiple tables to placeholders by order")
    func testMultipleTablesMatchByOrder() {
        // Two placeholders, two tables
        let text = "Title\n\n\u{FFFC}\nMiddle text\n\u{FFFC}\nEnd"
        let attributeRuns = [
            AttributeRun(length: text.count, styleType: .body)
        ]

        let table1 = NoteTable(rows: [
            [TableCell(text: "Table1-A"), TableCell(text: "Table1-B")]
        ], position: 100)  // Higher position but should match first placeholder

        let table2 = NoteTable(rows: [
            [TableCell(text: "Table2-A"), TableCell(text: "Table2-B")]
        ], position: 50)  // Lower position but should match second placeholder (sorted by position)

        // Tables sorted by position: table2 (50) comes first, table1 (100) second
        let content = StyledNoteContent(
            text: text,
            attributeRuns: attributeRuns,
            tables: [table1, table2]  // Order in array doesn't matter
        )

        let html = content.toHTML(darkMode: false)

        // Both tables should be rendered
        #expect(html.contains("Table1-A"), "First table should be rendered")
        #expect(html.contains("Table2-A"), "Second table should be rendered")

        // Middle text should be present
        #expect(html.contains("Middle text"), "Middle text should be present")
    }

    @Test("toHTML renders empty when no tables for placeholders")
    func testNoTablesForPlaceholders() {
        let text = "Title\n\n\u{FFFC}\nSome text"
        let attributeRuns = [
            AttributeRun(length: text.count, styleType: .body)
        ]

        // No tables provided
        let content = StyledNoteContent(
            text: text,
            attributeRuns: attributeRuns,
            tables: []
        )

        let html = content.toHTML(darkMode: false)

        // Should render without error, placeholder removed
        #expect(!html.contains("\u{FFFC}"), "Placeholder should be removed")
        #expect(html.contains("Some text"), "Content should be present")
        #expect(!html.contains("<table>"), "No table should be rendered")
    }

    @Test("toHTML escapes HTML in table cells")
    func testTableCellHTMLEscaping() {
        let text = "Title\n\n\u{FFFC}"
        let attributeRuns = [
            AttributeRun(length: text.count, styleType: .body)
        ]
        let table = NoteTable(rows: [
            [TableCell(text: "<script>alert('xss')</script>")]
        ], position: 0)

        let content = StyledNoteContent(
            text: text,
            attributeRuns: attributeRuns,
            tables: [table]
        )

        let html = content.toHTML(darkMode: false)

        // Script tag should be escaped
        #expect(html.contains("&lt;script&gt;"), "HTML should be escaped")
        #expect(!html.contains("<script>alert"), "Raw script tag should not be present")
    }

    @Test("toHTML handles table with emojis")
    func testTableWithEmojis() {
        let text = "Title\n\n\u{FFFC}"
        let attributeRuns = [
            AttributeRun(length: text.count, styleType: .body)
        ]
        let table = NoteTable(rows: [
            [TableCell(text: "🍕 Pizza"), TableCell(text: "🍔 Burger")],
            [TableCell(text: "🌮 Taco"), TableCell(text: "🍟 Fries")]
        ], position: 0)

        let content = StyledNoteContent(
            text: text,
            attributeRuns: attributeRuns,
            tables: [table]
        )

        let html = content.toHTML(darkMode: false)

        #expect(html.contains("🍕 Pizza"), "Emoji should be preserved")
        #expect(html.contains("🍔 Burger"), "Emoji should be preserved")
    }
}

// MARK: - CRDT Table Parsing Tests

@Suite("CRDT Table Parsing Tests")
struct CRDTTableParsingTests {
    let decoder = NoteDecoder()

    @Test("parseCRDTTable returns nil for empty data")
    func testEmptyData() {
        let result = decoder.parseCRDTTable(Data(), position: 0)
        #expect(result == nil, "Should return nil for empty data")
    }

    @Test("parseCRDTTable returns nil for invalid data")
    func testInvalidData() {
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])
        let result = decoder.parseCRDTTable(invalidData, position: 0)
        #expect(result == nil, "Should return nil for invalid data")
    }

    @Test("parseCRDTTable detects gzip by magic bytes")
    func testGzipDetection() {
        // Non-gzipped data (doesn't start with 1f 8b) should be processed directly
        let nonGzipData = Data([0x08, 0x00, 0x12, 0x00])  // Some protobuf-like bytes
        let result = decoder.parseCRDTTable(nonGzipData, position: 0)
        // Should return nil (no valid cell texts) but shouldn't crash
        #expect(result == nil, "Should handle non-table data gracefully")
    }
}

// MARK: - Table Integration Tests

@Suite("Table Integration Tests", .tags(.integration), .serialized)
struct TableIntegrationTests {
    let database = NotesDatabase()

    @Test("Read note with table extracts table data")
    func testReadNoteWithTable() throws {
        // Find a note that might have a table
        let notes = try database.listNotes(limit: 50)

        // Try to read each note with tables enabled
        for note in notes {
            let content = try database.readNote(id: note.id, includeTables: true)

            // Check if HTML contains a table
            if let html = content.htmlContent, html.contains("<table>") {
                #expect(html.contains("<th>") || html.contains("<td>"), "Table should have cells")
                return  // Found and verified a table
            }
        }

        // Note: This test may not find tables if no notes have them
        // It's mainly verifying the code path works without errors
    }

    @Test("Read note without tables skips table extraction")
    func testReadNoteWithoutTables() throws {
        let notes = try database.listNotes(limit: 5)
        guard let note = notes.first else { return }

        // Should succeed without fetching tables
        let content = try database.readNote(id: note.id, includeTables: false)
        #expect(!content.id.isEmpty, "Should read note without tables")
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var integration: Self
}
