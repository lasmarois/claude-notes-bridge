import Foundation

/// Formats notes as Markdown with optional YAML frontmatter
public class MarkdownFormatter: NoteFormatter {

    public init() {}

    public var fileExtension: String { "md" }

    /// Format a note as Markdown
    public func format(_ note: NoteContent, options: ExportOptions) throws -> String {
        var output = ""

        // Add YAML frontmatter if requested
        if options.includeFrontmatter {
            output += formatFrontmatter(note)
        }

        // Add title as H1
        output += "# \(note.title)\n\n"

        // Add content (skip first line if it matches title)
        let content = cleanContent(note.content, title: note.title)
        output += content

        // Ensure trailing newline
        if !output.hasSuffix("\n") {
            output += "\n"
        }

        return output
    }

    /// Format a note with styled content for better Markdown output
    public func formatStyled(_ note: NoteContent, styled: StyledNoteContent, options: ExportOptions) throws -> String {
        var output = ""

        // Add YAML frontmatter if requested
        if options.includeFrontmatter {
            output += formatFrontmatter(note)
        }

        // Convert styled content to Markdown
        output += convertStyledToMarkdown(styled)

        // Ensure trailing newline
        if !output.hasSuffix("\n") {
            output += "\n"
        }

        return output
    }

    // MARK: - Private Methods

    private func formatFrontmatter(_ note: NoteContent) -> String {
        var frontmatter = "---\n"
        frontmatter += "title: \(escapeFrontmatterValue(note.title))\n"

        if let folder = note.folder {
            frontmatter += "folder: \(escapeFrontmatterValue(folder))\n"
        }

        if let created = note.createdAt {
            frontmatter += "created: \(formatDate(created))\n"
        }

        if let modified = note.modifiedAt {
            frontmatter += "modified: \(formatDate(modified))\n"
        }

        if !note.hashtags.isEmpty {
            let tags = note.hashtags.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            frontmatter += "tags: [\(tags.joined(separator: ", "))]\n"
        }

        frontmatter += "---\n\n"
        return frontmatter
    }

    private func escapeFrontmatterValue(_ value: String) -> String {
        // Quote values that contain special YAML characters
        if value.contains(":") || value.contains("#") || value.contains("\"") ||
           value.contains("'") || value.contains("\n") || value.hasPrefix(" ") ||
           value.hasSuffix(" ") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func cleanContent(_ content: String, title: String) -> String {
        var lines = content.components(separatedBy: "\n")

        // Remove first line if it matches the title
        if let firstLine = lines.first?.trimmingCharacters(in: .whitespaces),
           firstLine == title {
            lines.removeFirst()
            // Also remove leading empty line if present
            while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                lines.removeFirst()
            }
        }

        return lines.joined(separator: "\n")
    }

    private func convertStyledToMarkdown(_ styled: StyledNoteContent) -> String {
        var output = ""
        let lines = styled.text.components(separatedBy: "\n")

        // Build style map: character offset -> style (CRDT uses character counts)
        var styleAtCharOffset: [(offset: Int, style: NoteStyleType, length: Int)] = []
        var currentCharOffset = 0
        for run in styled.attributeRuns {
            styleAtCharOffset.append((currentCharOffset, run.styleType, run.length))
            currentCharOffset += run.length
        }

        // Find table positions (U+FFFC placeholders)
        var tableIndex = 0
        let sortedTables = styled.tables.sorted { $0.position < $1.position }

        var charPosition = 0
        var inCodeBlock = false
        var codeBlockLines: [String] = []
        var numberedListIndex = 1

        func flushCodeBlock() {
            if !codeBlockLines.isEmpty {
                output += "```\n"
                output += codeBlockLines.joined(separator: "\n")
                output += "\n```\n"
                codeBlockLines = []
            }
        }

        for (index, line) in lines.enumerated() {
            let lineCharCount = line.count

            // Find style for this line (using character position)
            var lineStyle: NoteStyleType = .body
            for (offset, style, _) in styleAtCharOffset.reversed() {
                if offset <= charPosition {
                    lineStyle = style
                    break
                }
            }

            // First line defaults to title if no explicit style
            if index == 0 && lineStyle == .body {
                lineStyle = .title
            }
            // Other lines keep their explicit style (title stays title, heading stays heading)

            // Check for table placeholder
            if line.contains("\u{FFFC}") && tableIndex < sortedTables.count {
                flushCodeBlock()
                output += formatTable(sortedTables[tableIndex])
                tableIndex += 1
                charPosition += lineCharCount + 1
                continue
            }

            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\u{FFFC}", with: "")

            // Handle code blocks
            if lineStyle == .monospaced {
                if !inCodeBlock {
                    inCodeBlock = true
                }
                codeBlockLines.append(line)
                charPosition += lineCharCount + 1
                continue
            } else if inCodeBlock {
                flushCodeBlock()
                inCodeBlock = false
            }

            // Reset numbered list when leaving
            if lineStyle != .numberedList {
                numberedListIndex = 1
            }

            if !trimmedLine.isEmpty {
                switch lineStyle {
                case .title:
                    output += "# \(trimmedLine)\n\n"
                case .heading:
                    output += "## \(trimmedLine)\n\n"
                case .subheading:
                    output += "### \(trimmedLine)\n\n"
                case .subheading2:
                    output += "#### \(trimmedLine)\n\n"
                case .bulletList:
                    output += "- \(trimmedLine)\n"
                case .numberedList:
                    output += "\(numberedListIndex). \(trimmedLine)\n"
                    numberedListIndex += 1
                case .checkbox:
                    output += "- [ ] \(trimmedLine)\n"
                case .checkboxChecked:
                    output += "- [x] \(trimmedLine)\n"
                case .monospaced:
                    // Handled above
                    break
                case .body, .unknown:
                    output += "\(trimmedLine)\n\n"
                }
            } else {
                // Empty line
                if !output.hasSuffix("\n\n") {
                    output += "\n"
                }
            }

            charPosition += lineCharCount + 1
        }

        // Flush any remaining code block
        flushCodeBlock()

        return output
    }

    private func formatTable(_ table: NoteTable) -> String {
        guard !table.rows.isEmpty else { return "" }

        var output = "\n"

        for (rowIndex, row) in table.rows.enumerated() {
            let cells = row.map { "| \($0.text) " }.joined() + "|"
            output += cells + "\n"

            // Add separator after header row
            if rowIndex == 0 {
                let separator = row.map { _ in "|---" }.joined() + "|"
                output += separator + "\n"
            }
        }

        output += "\n"
        return output
    }
}
