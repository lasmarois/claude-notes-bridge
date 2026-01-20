import SwiftUI
import NotesLib

@main
struct NotesSearchApp: App {
    @StateObject private var viewModel = SearchViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .textEditing) {
                Button("Find...") {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    // Will trigger search bar focus
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}
