import Foundation

enum Permissions {
    /// Path to the Notes database
    static let notesDatabasePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"
    }()

    /// Check if we have Full Disk Access by trying to read the Notes database
    static func hasFullDiskAccess() -> Bool {
        FileManager.default.isReadableFile(atPath: notesDatabasePath)
    }

    /// Print instructions for granting Full Disk Access
    static func printAccessInstructions() {
        let message = """
        ╔════════════════════════════════════════════════════════════════╗
        ║                    Full Disk Access Required                   ║
        ╠════════════════════════════════════════════════════════════════╣
        ║                                                                ║
        ║  claude-notes-bridge needs Full Disk Access to read your      ║
        ║  Apple Notes database.                                         ║
        ║                                                                ║
        ║  To grant access:                                              ║
        ║  1. Open System Settings → Privacy & Security → Full Disk Access║
        ║  2. Click the + button                                         ║
        ║  3. Add this application                                       ║
        ║  4. Restart claude-notes-bridge                                ║
        ║                                                                ║
        ╚════════════════════════════════════════════════════════════════╝
        """
        fputs(message + "\n", stderr)

        // Try to open System Settings to the right panel
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]
        try? process.run()
    }
}
