import Foundation

/// Converts markdown text to HTML for Apple Notes
public class MarkdownConverter {

    public init() {}

    /// Convert markdown to HTML
    /// Handles: code blocks, inline code, bold, italic, strikethrough, headers, lists, blockquotes, tables
    public func convert(_ markdown: String) -> String {
        var result = markdown

        // 1. First, handle fenced code blocks: ```lang\ncode\n```
        result = processCodeBlocks(result)

        // 2. Handle inline code: `code`
        result = processInlineCode(result)

        // 3. Handle markdown tables (before escaping)
        result = processTables(result)

        // 4. Escape HTML in non-code parts and restore code/tables
        result = escapeAndRestoreCode(result)

        // 5. Process markdown formatting
        result = processFormatting(result)

        // 6. Handle line-based markdown (headers, lists, quotes)
        result = processLineBasedMarkdown(result)

        return result
    }

    // MARK: - Table Processing

    private func processTables(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Check if this line starts a table (starts with |)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                // Look ahead to see if next line is a separator (|---|---|)
                if i + 1 < lines.count {
                    let nextLine = lines[i + 1]
                    if isTableSeparator(nextLine) {
                        // This is a table! Parse it
                        let tableHTML = parseTable(lines: lines, startIndex: i)
                        result.append("⟦TABLE⟧\(tableHTML)⟦/TABLE⟧")

                        // Skip all table lines
                        i += 1  // Skip header
                        i += 1  // Skip separator
                        while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                            i += 1
                        }
                        // Skip one trailing blank line if present (common markdown pattern)
                        if i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                            i += 1
                        }
                        continue
                    }
                }
            }

            result.append(line)
            i += 1
        }

        return result.joined(separator: "\n")
    }

    private func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return false }

        // Check if it's like |---|---| or | --- | --- |
        let cells = trimmed.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
        return cells.allSatisfy { cell in
            cell.isEmpty || cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private func parseTable(lines: [String], startIndex: Int) -> String {
        // Build table HTML without internal newlines (Notes.app renders them as extra line breaks)
        var html = "<table cellspacing=\"0\" cellpadding=\"0\" style=\"border-collapse: collapse\"><tbody>"

        // Parse header row
        let headerLine = lines[startIndex]
        let headerCells = parseTableRow(headerLine)
        html += "<tr>"
        for cell in headerCells {
            let escapedCell = escapeHTMLInCode(cell)
            html += "<td valign=\"top\" style=\"border-style: solid; border-width: 1px; border-color: #ccc; padding: 3px 5px; min-width: 70px\"><div><b>\(escapedCell)</b></div></td>"
        }
        html += "</tr>"

        // Skip separator line, parse data rows
        var i = startIndex + 2
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") else { break }

            let cells = parseTableRow(line)
            html += "<tr>"
            for cell in cells {
                let escapedCell = escapeHTMLInCode(cell)
                html += "<td valign=\"top\" style=\"border-style: solid; border-width: 1px; border-color: #ccc; padding: 3px 5px; min-width: 70px\"><div>\(escapedCell)</div></td>"
            }
            html += "</tr>"
            i += 1
        }

        html += "</tbody></table>"
        return html
    }

    private func parseTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)

        // Remove leading and trailing |
        if trimmed.hasPrefix("|") { trimmed = String(trimmed.dropFirst()) }
        if trimmed.hasSuffix("|") { trimmed = String(trimmed.dropLast()) }

        return trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Code Processing

    private func processCodeBlocks(_ text: String) -> String {
        var result = text
        let codeBlockPattern = "```(?:\\w*)?\\n([\\s\\S]*?)```"

        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)

            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let codeRange = Range(match.range(at: 1), in: result) else {
                    continue
                }

                let code = String(result[codeRange])
                let escapedCode = escapeHTMLInCode(code)
                    .replacingOccurrences(of: "\n", with: "<br>")

                let replacement = "⟦CODEBLOCK⟧\(escapedCode)⟦/CODEBLOCK⟧"
                result.replaceSubrange(fullRange, with: replacement)
            }
        }

        return result
    }

    private func processInlineCode(_ text: String) -> String {
        var result = text
        let inlinePattern = "`([^`]+)`"

        if let regex = try? NSRegularExpression(pattern: inlinePattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)

            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let codeRange = Range(match.range(at: 1), in: result) else {
                    continue
                }

                let code = String(result[codeRange])
                let escapedCode = escapeHTMLInCode(code)

                let replacement = "⟦CODE⟧\(escapedCode)⟦/CODE⟧"
                result.replaceSubrange(fullRange, with: replacement)
            }
        }

        return result
    }

    private func escapeAndRestoreCode(_ text: String) -> String {
        var escaped = ""
        var remaining = text

        while !remaining.isEmpty {
            // Find the next placeholder (code block, inline code, or table)
            let codeBlockRange = remaining.range(of: "⟦CODEBLOCK⟧")
            let codeRange = remaining.range(of: "⟦CODE⟧")
            let tableRange = remaining.range(of: "⟦TABLE⟧")

            // Determine which placeholder comes first
            var candidates: [(range: Range<String.Index>, type: String)] = []
            if let r = codeBlockRange { candidates.append((r, "codeblock")) }
            if let r = codeRange { candidates.append((r, "code")) }
            if let r = tableRange { candidates.append((r, "table")) }

            candidates.sort { $0.range.lowerBound < $1.range.lowerBound }

            guard let (startRange, placeholderType) = candidates.first else {
                escaped += escapeHTML(remaining)
                break
            }

            let before = String(remaining[..<startRange.lowerBound])
            escaped += escapeHTML(before)

            let afterStart = String(remaining[startRange.upperBound...])
            let endTag: String
            switch placeholderType {
            case "codeblock": endTag = "⟦/CODEBLOCK⟧"
            case "code": endTag = "⟦/CODE⟧"
            case "table": endTag = "⟦/TABLE⟧"
            default: endTag = ""
            }

            if let endRange = afterStart.range(of: endTag) {
                let content = String(afterStart[..<endRange.lowerBound])

                switch placeholderType {
                case "codeblock":
                    escaped += "<font face=\"Menlo\">\(content)</font>"
                case "code":
                    escaped += "<font face=\"Menlo\" color=\"#c7254e\">\(content)</font>"
                case "table":
                    // Table HTML is already properly formatted, just insert it
                    escaped += content
                default:
                    escaped += content
                }

                remaining = String(afterStart[endRange.upperBound...])
            } else {
                escaped += escapeHTML(remaining)
                break
            }
        }

        return escaped
    }

    // MARK: - Formatting

    private func processFormatting(_ text: String) -> String {
        var result = text

        // Links: [text](url) - process before bold/italic to avoid conflicts
        result = applyPattern(result, pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)", replacement: "<a href=\"$2\">$1</a>")

        // Bold+Italic: ***text*** or ___text___ - must come before bold and italic
        result = applyPattern(result, pattern: "\\*\\*\\*(.+?)\\*\\*\\*", replacement: "<b><i>$1</i></b>")
        result = applyPattern(result, pattern: "___(.+?)___", replacement: "<b><i>$1</i></b>")

        // Bold: **text** or __text__
        result = applyPattern(result, pattern: "\\*\\*(.+?)\\*\\*", replacement: "<b>$1</b>")
        result = applyPattern(result, pattern: "__(.+?)__", replacement: "<b>$1</b>")

        // Italic: *text* or _text_
        result = applyPattern(result, pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", replacement: "<i>$1</i>")
        result = applyPattern(result, pattern: "(?<![\\w])_(?!_)(.+?)(?<!_)_(?![\\w])", replacement: "<i>$1</i>")

        // Strikethrough: ~~text~~
        result = applyPattern(result, pattern: "~~(.+?)~~", replacement: "<strike>$1</strike>")

        return result
    }

    private func processLineBasedMarkdown(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")

        for i in 0..<lines.count {
            var line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Horizontal rule: --- or *** or ___ (standalone line)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                line = "<hr style=\"border: none; border-top: 1px solid #ccc; margin: 8px 0;\">"
            }
            // Headers: # ## ###
            else if line.hasPrefix("### ") {
                line = "<b>\(String(line.dropFirst(4)))</b>"
            } else if line.hasPrefix("## ") {
                line = "<b><span style=\"font-size: 18px\">\(String(line.dropFirst(3)))</span></b>"
            } else if line.hasPrefix("# ") {
                line = "<b><span style=\"font-size: 24px\">\(String(line.dropFirst(2)))</span></b>"
            }
            // Blockquotes: > text (note: > was escaped to &gt;)
            else if line.hasPrefix("&gt; ") {
                line = "<font color=\"#666666\">▎ \(String(line.dropFirst(5)))</font>"
            } else if line.hasPrefix("&gt;") && line.count > 4 {
                line = "<font color=\"#666666\">▎ \(String(line.dropFirst(4)))</font>"
            }
            // Nested unordered lists (2+ spaces indent): "  - " or "  * "
            else if line.hasPrefix("  - ") || line.hasPrefix("    - ") {
                let indent = line.hasPrefix("    - ") ? "        " : "    "
                let content = line.trimmingCharacters(in: .whitespaces).dropFirst(2)
                line = "\(indent)◦ \(content)"
            } else if line.hasPrefix("  * ") || line.hasPrefix("    * ") {
                let indent = line.hasPrefix("    * ") ? "        " : "    "
                let content = line.trimmingCharacters(in: .whitespaces).dropFirst(2)
                line = "\(indent)◦ \(content)"
            }
            // Unordered lists: - or *
            else if line.hasPrefix("- ") {
                line = "• \(String(line.dropFirst(2)))"
            } else if line.hasPrefix("* ") {
                line = "• \(String(line.dropFirst(2)))"
            }
            // Numbered lists: 1. 2. etc.
            else if let match = line.range(of: "^\\d+\\. ", options: .regularExpression) {
                let number = line[match].dropLast(2)  // Get just the number
                let content = String(line[match.upperBound...])
                line = "\(number). \(content)"
            }

            lines[i] = line
        }

        // Collapse multiple consecutive blank lines into single <br>
        var result: [String] = []
        var prevWasBlank = false
        for line in lines {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                if !prevWasBlank {
                    result.append("")  // Keep one blank line
                }
                prevWasBlank = true
            } else {
                result.append(line)
                prevWasBlank = false
            }
        }

        return result.joined(separator: "<br>")
    }

    // MARK: - Helpers

    private func applyPattern(_ string: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return string
        }
        let range = NSRange(string.startIndex..., in: string)
        return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: replacement)
    }

    /// Escape HTML special characters
    public func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func escapeHTMLInCode(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
