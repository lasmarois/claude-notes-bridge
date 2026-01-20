import SwiftUI
import AppKit
import NotesLib

struct ContentView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        if !viewModel.hasFullDiskAccess {
            PermissionView()
        } else {
            NavigationSplitView {
                sidebarContent
            } detail: {
                detailContent
            }
            .navigationSplitViewStyle(.balanced)
            .onAppear {
                // Delay focus to ensure window is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isSearchFocused = true
                    activateApp()
                }
            }
        }
    }

    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            window.makeKey()
            window.orderFrontRegardless()
        }
    }

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchBarView(isSearchFocused: $isSearchFocused)
                .padding()

            Divider()

            // Search status indicators
            if viewModel.isAnySearching {
                SearchStatusView()
                    .padding(.horizontal)
            }

            // Results list
            if viewModel.results.isEmpty && viewModel.isAnySearching {
                Spacer()
                ProgressView("Searching...")
                    .padding()
                Spacer()
            } else if viewModel.results.isEmpty && !viewModel.searchText.isEmpty && !viewModel.isAnySearching {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if viewModel.results.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Search your notes")
                        .foregroundColor(.secondary)
                    Text("Try basic, full-text, or semantic search")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ResultsListView()
            }

            if let error = viewModel.errorMessage {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 300)
    }

    private var detailContent: some View {
        Group {
            if let note = viewModel.selectedNoteContent {
                NotePreviewView(note: note)
            } else if viewModel.selectedResult != nil {
                ProgressView("Loading note...")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a note to preview")
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 400)
    }
}

// MARK: - Search Bar

struct SearchBarView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search notes...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit {
                    viewModel.search()
                }
                .onChange(of: viewModel.searchText) { _ in
                    // Debounced search
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        viewModel.search()
                    }
                }

            if !viewModel.searchText.isEmpty {
                Button(action: {
                    viewModel.searchText = ""
                    viewModel.results = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Search Status

struct SearchStatusView: View {
    @EnvironmentObject var viewModel: SearchViewModel

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(active: viewModel.searchingBasic, label: "Title", color: .blue)
            StatusDot(active: viewModel.searchingFTS, label: "Content", color: .green)
            StatusDot(active: viewModel.searchingSemantic, label: "AI", color: .purple)

            if let status = viewModel.semanticStatus {
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct StatusDot: View {
    let active: Bool
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? color : color.opacity(0.3))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundColor(active ? .primary : .secondary)
        }
    }
}

// MARK: - Results List

struct ResultsListView: View {
    @EnvironmentObject var viewModel: SearchViewModel

    var body: some View {
        List(viewModel.results, selection: $viewModel.selectedResult) { result in
            ResultRowView(result: result)
                .tag(result)
        }
        .listStyle(.sidebar)
        .onChange(of: viewModel.selectedResult) { newValue in
            if let result = newValue {
                viewModel.loadNoteContent(for: result)
            } else {
                viewModel.selectedNoteContent = nil
            }
        }
    }
}

struct ResultRowView: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                // Source badges
                SourceBadge(source: result.displaySource)
            }

            HStack {
                if let folder = result.folder {
                    Label(folder, systemImage: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let score = result.score {
                    Text(String(format: "%.0f%%", score * 100))
                        .font(.caption)
                        .foregroundColor(.purple)
                }

                if let date = result.modifiedAt {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let snippet = result.snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SourceBadge: View {
    let source: SearchSource

    var color: Color {
        switch source {
        case .basic: return .blue
        case .fts: return .green
        case .semantic: return .purple
        case .multiple: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: source.icon)
                .font(.caption2)
            Text(source.rawValue)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(4)
    }
}

// MARK: - Note Preview

struct NotePreviewView: View {
    let note: NoteContent
    @EnvironmentObject var viewModel: SearchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(spacing: 12) {
                        if let folder = note.folder {
                            Label(folder, systemImage: "folder")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let modified = note.modifiedAt {
                            Label {
                                Text(modified, style: .date)
                            } icon: {
                                Image(systemName: "clock")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: 8) {
                    Button(action: { viewModel.openInNotesApp() }) {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }

                    Menu {
                        Button("Copy Content") { viewModel.copyNoteContent() }
                        Button("Copy ID") { viewModel.copyNoteID() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                Text(note.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            // Footer with metadata
            if !note.hashtags.isEmpty || !note.attachments.isEmpty {
                Divider()
                HStack {
                    if !note.hashtags.isEmpty {
                        ForEach(note.hashtags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }

                    Spacer()

                    if !note.attachments.isEmpty {
                        Label("\(note.attachments.count) attachment(s)", systemImage: "paperclip")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Permission View

struct PermissionView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            Text("Full Disk Access Required")
                .font(.title)
                .fontWeight(.semibold)

            Text("Notes Search needs Full Disk Access to read your Apple Notes database.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("To grant access:")
                    .fontWeight(.medium)
                Text("1. Open System Settings")
                Text("2. Go to Privacy & Security > Full Disk Access")
                Text("3. Click '+' and add Notes Search")
                Text("4. Restart the app")
            }
            .font(.callout)

            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Preview not available in SPM builds
// Use Xcode project for previews
