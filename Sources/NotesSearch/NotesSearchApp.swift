import SwiftUI
import AppKit
import NotesLib

@main
struct NotesSearchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = SearchViewModel()
    @StateObject private var exportViewModel = ExportViewModel()
    @StateObject private var importViewModel = ImportViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(exportViewModel)
                .environmentObject(importViewModel)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .textEditing) {
                Button("Find...") {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            // Import/Export commands
            ImportExportCommands()

            // View commands
            ViewCommands()
        }
    }
}

// MARK: - Import/Export Menu Commands

struct ImportExportCommands: Commands {
    @FocusedValue(\.showExportPanel) var showExportPanel
    @FocusedValue(\.showImportPanel) var showImportPanel
    @FocusedValue(\.addSelectedToExport) var addSelectedToExport
    @FocusedValue(\.addAllToExport) var addAllToExport
    @FocusedValue(\.exportQueueCount) var exportQueueCount
    @FocusedValue(\.hasSelectedResult) var hasSelectedResult
    @FocusedValue(\.hasResults) var hasResults

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export...") {
                showExportPanel?()
            }
            .keyboardShortcut("e", modifiers: .command)

            Button("Import...") {
                showImportPanel?()
            }
            .keyboardShortcut("i", modifiers: .command)

            Divider()

            Button("Add to Export Queue") {
                addSelectedToExport?()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(hasSelectedResult != true)

            Button("Add All Results to Export") {
                addAllToExport?()
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(hasResults != true)
        }
    }
}

// MARK: - View Menu Commands

struct ViewCommands: Commands {
    @FocusedValue(\.refreshNotes) var refreshNotes

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Refresh Notes") {
                refreshNotes?()
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set as regular app (shows in Dock) BEFORE windows are created
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Use NSRunningApplication API for activation
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

        // Keep trying to focus the window
        for delay in [0.1, 0.3, 0.5, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.forceActivate()
            }
        }
    }

    private func forceActivate() {
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            // Try to find and focus the text field
            self.focusSearchField(in: window.contentView)
        }
    }

    private func focusSearchField(in view: NSView?) {
        guard let view = view else { return }
        if let textField = view as? NSTextField, textField.isEditable {
            view.window?.makeFirstResponder(textField)
            return
        }
        for subview in view.subviews {
            focusSearchField(in: subview)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
