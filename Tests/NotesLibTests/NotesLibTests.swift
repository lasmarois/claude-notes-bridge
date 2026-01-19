import Testing
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
