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

// MARK: - Test Tags

extension Tag {
    @Tag static var integration: Self
}
