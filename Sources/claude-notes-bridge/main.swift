import Foundation
import NotesLib

// Handle test mode for encoder verification
if CommandLine.arguments.contains("--test-encoder") {
    runEncoderTest()
    exit(0)
}

// Handle test mode for note creation
if CommandLine.arguments.contains("--test-create") {
    runCreateTest()
    exit(0)
}

// List folders
if CommandLine.arguments.contains("--list-folders") {
    listFoldersCommand()
    exit(0)
}

// Check Full Disk Access first
guard Permissions.hasFullDiskAccess() else {
    Permissions.printAccessInstructions()
    exit(1)
}

// Start MCP server
let server = MCPServer()

// Run the async main loop
let semaphore = DispatchSemaphore(value: 0)
Task {
    await server.run()
    semaphore.signal()
}
semaphore.wait()

// MARK: - Test Functions

func runEncoderTest() {
    print("Testing NoteEncoder/NoteDecoder roundtrip...")

    let encoder = NoteEncoder()
    let decoder = NoteDecoder()

    let testCases = [
        "Test Title\n\nThis is the body of the note.",
        "Simple Note\n\nLine 1\nLine 2\nLine 3",
        "Unicode Test 🎉\n\nEmojis work: 👍 ✅ 🚀",
        "Title Only"
    ]

    var passed = 0
    var failed = 0

    for (index, originalText) in testCases.enumerated() {
        do {
            // Encode
            let encoded = try encoder.encode(originalText)
            print("  Test \(index + 1): Encoded \(originalText.prefix(20))... -> \(encoded.count) bytes")

            // Decode
            let decoded = try decoder.decode(encoded)

            // Compare
            if decoded == originalText {
                print("    ✓ Roundtrip successful")
                passed += 1
            } else {
                print("    ✗ Mismatch!")
                print("      Original: \(originalText.debugDescription)")
                print("      Decoded:  \(decoded.debugDescription)")
                failed += 1
            }
        } catch {
            print("    ✗ Error: \(error)")
            failed += 1
        }
    }

    print("\nResults: \(passed) passed, \(failed) failed")

    if failed > 0 {
        exit(1)
    }
}

func listFoldersCommand() {
    print("Available folders:")
    let db = NotesDatabase()

    do {
        let folders = try db.listFolders()
        for folder in folders {
            print("  [\(folder.pk)] \(folder.name)")
        }
        print("\nTotal: \(folders.count) folders")
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

func runCreateTest() {
    print("Testing note creation...")
    print("⚠️  This will create a real note in your Notes app!")
    print("")

    let db = NotesDatabase()

    // First list folders to show options
    print("Available folders:")
    do {
        let folders = try db.listFolders()
        for folder in folders.prefix(10) {
            print("  - \(folder.name)")
        }
        if folders.count > 10 {
            print("  ... and \(folders.count - 10) more")
        }
    } catch {
        print("Error listing folders: \(error)")
        exit(1)
    }

    print("")

    // Create a test note
    let title = "Test Note from Claude"
    let body = "This note was created by claude-notes-bridge.\n\nTimestamp: \(Date())"
    let folder = "Notes"  // Use default folder

    print("Creating note:")
    print("  Title: \(title)")
    print("  Folder: \(folder)")
    print("")

    do {
        let noteId = try db.createNote(title: title, body: body, folderName: folder)
        print("✓ Note created successfully!")
        print("  ID: \(noteId)")
        print("")
        print("Open Notes.app to verify the note appears.")
    } catch {
        print("✗ Failed to create note: \(error)")
        exit(1)
    }
}
