import Foundation
import Compression

/// Style types from Apple Notes protobuf
///
/// Note: "Title" (⇧⌘T) only works for the first line of a note and is NOT saved
/// to the protobuf. It's inferred by our code for rendering purposes.
/// "Heading" (⇧⌘H) is style_type=1 and IS properly saved.
public enum NoteStyleType: Int, Codable {
    case title = 0             // Title - protobuf style_type=0 (when EXPLICITLY present)
    case heading = 1           // Section header (⇧⌘H) - saved to protobuf as style_type=1
    case subheading = 2        // Smaller header - saved as style_type=2
    case subheading2 = 3       // Third level - saved as style_type=3
    case monospaced = 4
    case bulletList = 100      // Dash list (- item)
    case numberedList = 101    // Numbered list (1. item)
    case checkbox = 102        // Unchecked checkbox
    case checkboxChecked = 103 // Checked checkbox
    case body = -2             // Body - when style_type field is ABSENT from protobuf
    case unknown = -1          // Fallback for unrecognized styles

    public init(rawValue: Int) {
        switch rawValue {
        case 0: self = .title   // style_type=0 explicitly means Title
        case 1: self = .heading
        case 2: self = .subheading
        case 3: self = .subheading2
        case 4: self = .monospaced
        case 100: self = .bulletList
        case 101: self = .numberedList
        case 102: self = .checkbox
        case 103: self = .checkboxChecked
        default: self = .body  // Treat unknown as body
        }
    }

    public var htmlTag: String {
        switch self {
        case .title: return "h1"       // First line (inferred)
        case .heading: return "h2"     // ⇧⌘H
        case .subheading: return "h3"  // style_type=2
        case .subheading2: return "h4" // style_type=3
        case .monospaced: return "pre"
        case .bulletList: return "li"
        case .numberedList: return "li"
        case .checkbox: return "li"
        case .checkboxChecked: return "li"
        case .body, .unknown: return "p"
        }
    }
}

/// A styled text run with length and style info
public struct AttributeRun: Codable {
    public let length: Int
    public let styleType: NoteStyleType
    public let fontWeight: Int?      // f5: 1 = bold, 0 = normal
    public let fontSize: Float?      // f3.f2: font size in points (e.g., 18.0)
    public let fontName: String?     // f3 as string: font name (e.g., "Skia-Regular")

    public init(length: Int, styleType: NoteStyleType, fontWeight: Int? = nil, fontSize: Float? = nil, fontName: String? = nil) {
        self.length = length
        self.styleType = styleType
        self.fontWeight = fontWeight
        self.fontSize = fontSize
        self.fontName = fontName
    }

    public var isBold: Bool {
        return fontWeight == 1
    }
}

/// Table cell from Apple Notes
public struct TableCell {
    public let text: String
}

/// Table from Apple Notes
public struct NoteTable {
    public let rows: [[TableCell]]
    public let position: Int  // Byte position in text where table appears

    public init(rows: [[TableCell]], position: Int) {
        self.rows = rows
        self.position = position
    }
}

/// Reference to an embedded table object
public struct TableReference {
    public let uuid: String
    public let type: String
    public let position: Int
}

/// Styled note content with text and formatting
public struct StyledNoteContent {
    public let text: String
    public let attributeRuns: [AttributeRun]
    public var tables: [NoteTable] = []
    public var tableReferences: [TableReference] = []

    public init(text: String, attributeRuns: [AttributeRun], tables: [NoteTable] = [], tableReferences: [TableReference] = []) {
        self.text = text
        self.attributeRuns = attributeRuns
        self.tables = tables
        self.tableReferences = tableReferences
    }

    /// Convert to HTML for rendering
    /// Uses a line-based approach with style lookup from attribute runs
    /// Tables are inserted inline where U+FFFC placeholders appear
    public func toHTML(darkMode: Bool = false) -> String {
        let bgColor = darkMode ? "#1e1e1e" : "#ffffff"
        let textColor = darkMode ? "#e0e0e0" : "#1d1d1f"
        let secondaryColor = darkMode ? "#a0a0a0" : "#86868b"
        let codeBackground = darkMode ? "#2d2d2d" : "#f5f5f7"

        var html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
                font-size: 15px;
                line-height: 1.5;
                color: \(textColor);
                background-color: \(bgColor);
                padding: 16px;
                margin: 0;
            }
            h1 {
                font-size: 28px;
                font-weight: 700;
                margin: 0 0 12px 0;
                color: \(textColor);
            }
            h2 {
                font-size: 22px;
                font-weight: 600;
                margin: 16px 0 8px 0;
                color: \(textColor);
            }
            h3 {
                font-size: 18px;
                font-weight: 600;
                margin: 12px 0 6px 0;
                color: \(textColor);
            }
            p {
                margin: 0 0 8px 0;
            }
            pre {
                font-family: 'SF Mono', Menlo, monospace;
                font-size: 13px;
                background-color: \(codeBackground);
                padding: 12px;
                border-radius: 6px;
                overflow-x: auto;
                margin: 8px 0;
                white-space: pre-wrap;
                word-wrap: break-word;
            }
            table {
                border-collapse: collapse;
                margin: 12px 0;
                width: 100%;
            }
            th, td {
                border: 1px solid \(darkMode ? "#444" : "#ddd");
                padding: 8px 12px;
                text-align: left;
            }
            th {
                background-color: \(darkMode ? "#2a2a2a" : "#f5f5f7");
                font-weight: 600;
            }
            .checkbox {
                color: \(secondaryColor);
            }
            .checkbox::before {
                content: "☐ ";
            }
            .checkbox-checked {
                color: \(secondaryColor);
                text-decoration: line-through;
            }
            .checkbox-checked::before {
                content: "☑ ";
            }
        </style>
        </head>
        <body>
        """

        // Build a map of character offset -> style info for the start of each run
        // Note: CRDT attribute run lengths are in CHARACTERS, not bytes
        struct StyleInfo {
            let style: NoteStyleType
            let fontSize: Float?
            let fontName: String?
            let isBold: Bool
        }
        var styleAtCharOffset: [(offset: Int, info: StyleInfo)] = []
        var currentCharOffset = 0
        for run in attributeRuns {
            let info = StyleInfo(
                style: run.styleType,
                fontSize: run.fontSize,
                fontName: run.fontName,
                isBold: run.isBold
            )
            styleAtCharOffset.append((currentCharOffset, info))
            currentCharOffset += run.length
        }

        // Find all U+FFFC placeholder positions (in characters) and match with tables by order
        var fffcCharPositions: [Int] = []
        for (charPos, char) in text.enumerated() {
            if char == "\u{FFFC}" {
                fffcCharPositions.append(charPos)
            }
        }

        // Sort tables by position and match to placeholders in order
        let sortedTables = tables.sorted { $0.position < $1.position }
        var tableAtCharPosition: [Int: NoteTable] = [:]
        for (index, fffcPos) in fffcCharPositions.enumerated() {
            if index < sortedTables.count {
                tableAtCharPosition[fffcPos] = sortedTables[index]
            }
        }

        // Helper to render a table as HTML
        func renderTable(_ table: NoteTable) -> String {
            guard !table.rows.isEmpty else { return "" }
            var tableHtml = "<table>\n"
            for (rowIndex, row) in table.rows.enumerated() {
                tableHtml += "<tr>\n"
                for cell in row {
                    let tag = rowIndex == 0 ? "th" : "td"
                    tableHtml += "<\(tag)>\(escapeHTML(cell.text))</\(tag)>\n"
                }
                tableHtml += "</tr>\n"
            }
            tableHtml += "</table>\n"
            return tableHtml
        }

        // Process text line by line, tracking CHARACTER position
        let lines = text.components(separatedBy: "\n")
        var charPosition = 0
        var codeBlockLines: [String] = []  // Buffer for consecutive code lines
        var numberedListIndex = 1

        func flushCodeBlock() {
            if !codeBlockLines.isEmpty {
                let codeContent = codeBlockLines.joined(separator: "\n")
                html += "<pre>\(escapeHTML(codeContent))</pre>\n"
                codeBlockLines = []
            }
        }

        for (index, line) in lines.enumerated() {
            // Count characters in the line
            let lineCharCount = line.count

            // Find the style info for this line's starting character position
            var lineStyle: NoteStyleType = .body
            var lineFontSize: Float? = nil
            var lineFontName: String? = nil
            var lineIsBold: Bool = false
            for (offset, info) in styleAtCharOffset.reversed() {
                if offset <= charPosition {
                    lineStyle = info.style
                    lineFontSize = info.fontSize
                    lineFontName = info.fontName
                    lineIsBold = info.isBold
                    break
                }
            }

            // First line defaults to title if no explicit style
            if index == 0 && lineStyle == .body {
                lineStyle = .title
            }
            // Other lines keep their explicit style (title stays title, heading stays heading)

            // Check for table placeholder (U+FFFC) in this line
            // If found, render the table inline and remove the placeholder
            var processedLine = line
            var lineCharIndex = 0
            for char in line {
                if char == "\u{FFFC}" {
                    let absoluteCharPos = charPosition + lineCharIndex
                    if let table = tableAtCharPosition[absoluteCharPos] {
                        // Flush any pending code block before table
                        flushCodeBlock()
                        html += renderTable(table)
                    }
                }
                lineCharIndex += 1
            }
            // Remove placeholder characters for display
            processedLine = processedLine.replacingOccurrences(of: "\u{FFFC}", with: "")

            let trimmedLine = processedLine.trimmingCharacters(in: .whitespaces)

            // Handle monospaced (code) - group consecutive lines
            if lineStyle == .monospaced {
                codeBlockLines.append(processedLine)  // Keep original indentation for code
                charPosition += lineCharCount + 1  // +1 for newline
                continue
            } else {
                flushCodeBlock()
            }

            // Reset numbered list index when leaving numbered list
            if lineStyle != .numberedList {
                numberedListIndex = 1
            }

            if !trimmedLine.isEmpty {
                let escapedText = escapeHTML(trimmedLine)

                // Build inline style for custom font properties
                var inlineStyles: [String] = []
                if let size = lineFontSize {
                    inlineStyles.append("font-size: \(Int(size))pt")
                }
                if let fontName = lineFontName {
                    inlineStyles.append("font-family: '\(fontName)'")
                }
                if lineIsBold {
                    inlineStyles.append("font-weight: bold")
                }
                let styleAttr = inlineStyles.isEmpty ? "" : " style=\"\(inlineStyles.joined(separator: "; "))\""

                switch lineStyle {
                case .title:
                    html += "<h1\(styleAttr)>\(escapedText)</h1>\n"
                case .heading:
                    html += "<h2\(styleAttr)>\(escapedText)</h2>\n"
                case .subheading:
                    html += "<h3\(styleAttr)>\(escapedText)</h3>\n"
                case .subheading2:
                    html += "<h4\(styleAttr)>\(escapedText)</h4>\n"
                case .monospaced:
                    // Handled above
                    break
                case .bulletList:
                    html += "<p\(styleAttr)>• \(escapedText)</p>\n"
                case .numberedList:
                    html += "<p\(styleAttr)>\(numberedListIndex). \(escapedText)</p>\n"
                    numberedListIndex += 1
                case .checkbox:
                    html += "<p\(styleAttr)>☐ \(escapedText)</p>\n"
                case .checkboxChecked:
                    let checkedStyles = inlineStyles + ["text-decoration: line-through", "color: \(secondaryColor)"]
                    html += "<p style=\"\(checkedStyles.joined(separator: "; "))\">☑ \(escapedText)</p>\n"
                case .body, .unknown:
                    html += "<p\(styleAttr)>\(escapedText)</p>\n"
                }
            }

            // Move character position past this line + newline
            charPosition += lineCharCount + 1
        }

        // Flush any remaining code block
        flushCodeBlock()

        html += "</body></html>"
        return html
    }

    private func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}

/// Decodes note content from gzipped protobuf format
public class NoteDecoder {

    public init() {}

    /// Decode note content from raw ZDATA blob (plain text only)
    public func decode(_ data: Data) throws -> String {
        let styled = try decodeStyled(data)
        return styled.text
    }

    /// Decode note content with styling information
    public func decodeStyled(_ data: Data) throws -> StyledNoteContent {
        // Step 1: Decompress gzip
        let decompressed = try decompress(data)

        // Step 2: Parse protobuf to extract text and styles
        return try extractStyledContent(from: decompressed)
    }

    /// Debug: dump attribute runs for a note
    public func debugDumpStyles(_ data: Data) -> String {
        guard let content = try? decodeStyled(data) else {
            return "Failed to decode"
        }

        var output = "Text length: \(content.text.count) chars, \(content.text.utf8.count) bytes\n"
        output += "Attribute runs: \(content.attributeRuns.count)\n\n"

        var byteOffset = 0
        let lines = content.text.components(separatedBy: "\n")

        for (i, run) in content.attributeRuns.enumerated() {
            output += "Run \(i): length=\(run.length), style=\(run.styleType) (raw: \(run.styleType.rawValue))\n"
            output += "  Byte range: \(byteOffset)..<\(byteOffset + run.length)\n"

            // Show what text this covers
            let textData = content.text.data(using: .utf8)!
            if byteOffset < textData.count {
                let endByte = min(byteOffset + run.length, textData.count)
                let rangeData = textData.subdata(in: byteOffset..<endByte)
                if let text = String(data: rangeData, encoding: .utf8) {
                    let preview = text.prefix(50).replacingOccurrences(of: "\n", with: "\\n")
                    output += "  Text: \"\(preview)\(text.count > 50 ? "..." : "")\"\n"
                }
            }
            byteOffset += run.length
            output += "\n"
        }

        return output
    }

    // MARK: - Gzip Decompression

    private func decompress(_ data: Data) throws -> Data {
        // Check for gzip magic number (1f 8b)
        guard data.count >= 2,
              data[0] == 0x1f,
              data[1] == 0x8b else {
            // Not gzipped, return as-is
            return data
        }

        // Use zlib decompression (gzip is zlib with header)
        var decompressed = Data()
        let bufferSize = 65536
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        let result = data.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) -> Data? in
            guard let sourceAddress = sourcePtr.baseAddress else { return nil }

            let filter = try? OutputFilter(.decompress, using: .zlib) { (data: Data?) in
                if let data = data {
                    decompressed.append(data)
                }
            }

            guard let filter = filter else { return nil }

            var offset = 0
            let sourceCount = data.count

            // Skip gzip header (10 bytes minimum)
            offset = 10

            // Check for extra fields
            let flags = data[3]
            if flags & 0x04 != 0 { // FEXTRA
                let extraLen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
                offset += 2 + extraLen
            }
            if flags & 0x08 != 0 { // FNAME
                while offset < sourceCount && data[offset] != 0 { offset += 1 }
                offset += 1
            }
            if flags & 0x10 != 0 { // FCOMMENT
                while offset < sourceCount && data[offset] != 0 { offset += 1 }
                offset += 1
            }
            if flags & 0x02 != 0 { // FHCRC
                offset += 2
            }

            // Decompress the deflate stream
            let compressedData = data.subdata(in: offset..<(sourceCount - 8))

            do {
                try filter.write(compressedData)
                try filter.finalize()
            } catch {
                return nil
            }

            return decompressed
        }

        if let result = result, !result.isEmpty {
            return result
        }

        // Fallback: try raw inflate
        return try inflateRaw(data)
    }

    private func inflateRaw(_ data: Data) throws -> Data {
        // Skip gzip header and try raw inflate
        var skipBytes = 10
        if data.count > 3 {
            let flags = data[3]
            if flags & 0x04 != 0, data.count > skipBytes + 2 {
                let extraLen = Int(data[skipBytes]) | (Int(data[skipBytes + 1]) << 8)
                skipBytes += 2 + extraLen
            }
            if flags & 0x08 != 0 {
                while skipBytes < data.count && data[skipBytes] != 0 { skipBytes += 1 }
                skipBytes += 1
            }
            if flags & 0x10 != 0 {
                while skipBytes < data.count && data[skipBytes] != 0 { skipBytes += 1 }
                skipBytes += 1
            }
            if flags & 0x02 != 0 { skipBytes += 2 }
        }

        guard skipBytes < data.count - 8 else {
            throw NotesError.decodingFailed("Invalid gzip data")
        }

        let compressedData = data.subdata(in: skipBytes..<(data.count - 8))

        let destinationBufferSize = compressedData.count * 10
        var destinationBuffer = [UInt8](repeating: 0, count: destinationBufferSize)

        let decompressedSize = compressedData.withUnsafeBytes { sourcePtr in
            return compression_decode_buffer(
                &destinationBuffer,
                destinationBufferSize,
                sourcePtr.bindMemory(to: UInt8.self).baseAddress!,
                compressedData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else {
            throw NotesError.decodingFailed("Decompression failed")
        }

        return Data(destinationBuffer.prefix(decompressedSize))
    }

    // MARK: - Protobuf Parsing

    /// Parse protobuf to extract text and attribute runs
    private func extractStyledContent(from data: Data) throws -> StyledNoteContent {
        var offset = 0

        // Parse NoteStoreProto, looking for field 2 (document)
        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
            offset = newOffset

            if fieldNumber == 2 && wireType == 2 { // document (length-delimited)
                let (documentData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                offset = nextOffset

                // Parse Document, looking for field 3 (note)
                if let content = try parseDocumentStyled(documentData) {
                    return content
                }
            } else {
                offset = try skipField(wireType: wireType, from: data, at: offset)
            }
        }

        throw NotesError.decodingFailed("Could not find note content in protobuf")
    }

    private func parseDocumentStyled(_ data: Data) throws -> StyledNoteContent? {
        var offset = 0

        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
            offset = newOffset

            if fieldNumber == 3 && wireType == 2 { // note (length-delimited)
                let (noteData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                offset = nextOffset

                // Parse Note for text and attribute_runs
                return try parseNoteStyled(noteData)
            } else {
                offset = try skipField(wireType: wireType, from: data, at: offset)
            }
        }

        return nil
    }

    private func parseNoteStyled(_ data: Data) throws -> StyledNoteContent? {
        var offset = 0
        var noteText: String?
        var attributeRuns: [AttributeRun] = []

        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
            offset = newOffset

            if fieldNumber == 2 && wireType == 2 { // note_text (string)
                let (stringData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                noteText = String(data: stringData, encoding: .utf8)
                offset = nextOffset
            } else if fieldNumber == 5 && wireType == 2 { // attribute_run (repeated)
                let (runData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                if let run = try parseAttributeRun(runData) {
                    attributeRuns.append(run)
                }
                offset = nextOffset
            } else {
                offset = try skipField(wireType: wireType, from: data, at: offset)
            }
        }

        guard let text = noteText else { return nil }

        // If no attribute runs found, create a default body run
        if attributeRuns.isEmpty {
            attributeRuns = [AttributeRun(length: text.count, styleType: .body)]
        }

        return StyledNoteContent(text: text, attributeRuns: attributeRuns, tables: [], tableReferences: [])
    }

    /// Extract table references from note data (separate pass for when tables are needed)
    public func extractTableReferences(from data: Data) -> [TableReference] {
        var tableReferences: [TableReference] = []
        var currentPosition = 0

        // Decompress if needed
        guard let decompressed = try? decompress(data) else { return [] }

        // Navigate to the note content
        var offset = 0
        while offset < decompressed.count {
            guard let (fieldNumber, wireType, newOffset) = try? readTag(from: decompressed, at: offset),
                  newOffset > offset else { break }
            offset = newOffset

            if fieldNumber == 2 && wireType == 2 { // document
                guard let (docData, nextOffset) = try? readLengthDelimited(from: decompressed, at: offset),
                      nextOffset > offset else { break }
                tableReferences = extractTableRefsFromDocument(docData)
                break
            } else {
                offset = (try? skipField(wireType: wireType, from: decompressed, at: offset)) ?? decompressed.count
            }
        }

        return tableReferences
    }

    private func extractTableRefsFromDocument(_ data: Data) -> [TableReference] {
        var offset = 0
        while offset < data.count {
            guard let (fieldNumber, wireType, newOffset) = try? readTag(from: data, at: offset),
                  newOffset > offset else { break }
            offset = newOffset

            if fieldNumber == 3 && wireType == 2 { // note
                guard let (noteData, _) = try? readLengthDelimited(from: data, at: offset) else { break }
                return extractTableRefsFromNote(noteData)
            } else {
                offset = (try? skipField(wireType: wireType, from: data, at: offset)) ?? data.count
            }
        }
        return []
    }

    private func extractTableRefsFromNote(_ data: Data) -> [TableReference] {
        var tableReferences: [TableReference] = []
        var currentPosition = 0
        var offset = 0

        while offset < data.count {
            guard let (fieldNumber, wireType, newOffset) = try? readTag(from: data, at: offset),
                  newOffset > offset else { break }
            offset = newOffset

            if fieldNumber == 5 && wireType == 2 { // attribute_run
                guard let (runData, nextOffset) = try? readLengthDelimited(from: data, at: offset),
                      nextOffset > offset else { break }

                // Parse run for length and table ref
                var runOffset = 0
                var length = 0
                var tableUUID: String?
                var tableType: String?

                while runOffset < runData.count {
                    guard let (fn, wt, newOff) = try? readTag(from: runData, at: runOffset),
                          newOff > runOffset else { break }
                    runOffset = newOff

                    if fn == 1 && wt == 0 { // length
                        guard let (val, next) = try? readVarint(from: runData, at: runOffset),
                              next > runOffset else { break }
                        length = Int(val)
                        runOffset = next
                    } else if fn == 12 && wt == 2 { // embedded object ref
                        guard let (refData, next) = try? readLengthDelimited(from: runData, at: runOffset),
                              next > runOffset else { break }
                        if let ref = parseEmbeddedObjectRef(refData) {
                            tableUUID = ref.uuid
                            tableType = ref.type
                        }
                        runOffset = next
                    } else {
                        runOffset = (try? skipField(wireType: wt, from: runData, at: runOffset)) ?? runData.count
                    }
                }

                if let uuid = tableUUID, let type = tableType, type == "com.apple.notes.table" {
                    tableReferences.append(TableReference(uuid: uuid, type: type, position: currentPosition))
                }
                currentPosition += length
                offset = nextOffset
            } else {
                offset = (try? skipField(wireType: wireType, from: data, at: offset)) ?? data.count
            }
        }

        return tableReferences
    }

    /// Parse a CRDT table from ZMERGEABLEDATA1
    public func parseCRDTTable(_ data: Data, position: Int = 0) -> NoteTable? {
        // Decompress if gzipped (starts with 1f 8b)
        let decompressed: Data
        if data.count >= 2 && data[0] == 0x1f && data[1] == 0x8b {
            guard let d = try? decompress(data) else { return nil }
            decompressed = d
        } else {
            decompressed = data
        }

        var cellTexts: [String] = []
        extractField10Texts(from: decompressed, into: &cellTexts, depth: 0)

        guard !cellTexts.isEmpty else { return nil }

        // Determine column count heuristically
        let count = cellTexts.count
        let columnCount: Int
        if count % 2 == 0 && count <= 20 {
            columnCount = 2
        } else if count % 3 == 0 && count <= 30 {
            columnCount = 3
        } else if count % 4 == 0 {
            columnCount = 4
        } else {
            columnCount = 2
        }

        var rows: [[TableCell]] = []
        for startIdx in stride(from: 0, to: cellTexts.count, by: columnCount) {
            let endIdx = min(startIdx + columnCount, cellTexts.count)
            let rowCells = (startIdx..<endIdx).map { TableCell(text: cellTexts[$0]) }
            rows.append(rowCells)
        }

        return NoteTable(rows: rows, position: position)
    }

    /// Extract text from Field 10 messages (CRDT cell content)
    private func extractField10Texts(from data: Data, into texts: inout [String], depth: Int) {
        guard depth < 15, texts.count < 500 else { return }

        var offset = 0
        while offset < data.count {
            guard let (fieldNumber, wireType, newOffset) = try? readTag(from: data, at: offset),
                  newOffset > offset else { break }
            offset = newOffset

            if wireType == 2 {
                guard let (fieldData, nextOffset) = try? readLengthDelimited(from: data, at: offset),
                      nextOffset > offset else { break }

                if fieldNumber == 10 {
                    // Extract Field 2 text from this cell
                    if let text = extractField2Text(from: fieldData) {
                        let cleaned = text.replacingOccurrences(of: "\u{FFFC}", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            texts.append(cleaned)
                        }
                    }
                } else if fieldData.count > 2 {
                    extractField10Texts(from: fieldData, into: &texts, depth: depth + 1)
                }
                offset = nextOffset
            } else if wireType == 0 {
                guard let (_, nextOffset) = try? readVarint(from: data, at: offset),
                      nextOffset > offset else { break }
                offset = nextOffset
            } else {
                let nextOffset = (try? skipField(wireType: wireType, from: data, at: offset)) ?? data.count
                guard nextOffset > offset else { break }
                offset = nextOffset
            }
        }
    }

    /// Extract text from Field 2 within a cell
    private func extractField2Text(from data: Data) -> String? {
        var offset = 0
        while offset < data.count {
            guard let (fieldNumber, wireType, newOffset) = try? readTag(from: data, at: offset),
                  newOffset > offset else { break }
            offset = newOffset

            if fieldNumber == 2 && wireType == 2 {
                guard let (stringData, _) = try? readLengthDelimited(from: data, at: offset) else { return nil }
                return String(data: stringData, encoding: .utf8)
            } else if wireType == 2 {
                guard let (_, nextOffset) = try? readLengthDelimited(from: data, at: offset),
                      nextOffset > offset else { break }
                offset = nextOffset
            } else if wireType == 0 {
                guard let (_, nextOffset) = try? readVarint(from: data, at: offset),
                      nextOffset > offset else { break }
                offset = nextOffset
            } else {
                let nextOffset = (try? skipField(wireType: wireType, from: data, at: offset)) ?? data.count
                guard nextOffset > offset else { break }
                offset = nextOffset
            }
        }
        return nil
    }

    /// Parse a table from embedded object data
    private func parseTable(_ data: Data) throws -> NoteTable? {
        var offset = 0
        var rows: [[TableCell]] = []
        var position = 0

        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
            offset = newOffset

            if fieldNumber == 1 && wireType == 0 { // position in text
                let (value, nextOffset) = try readVarint(from: data, at: offset)
                position = Int(value)
                offset = nextOffset
            } else if fieldNumber == 2 && wireType == 2 { // table data
                let (tableData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                rows = try parseTableRows(tableData)
                offset = nextOffset
            } else {
                offset = try skipField(wireType: wireType, from: data, at: offset)
            }
        }

        guard !rows.isEmpty else { return nil }
        return NoteTable(rows: rows, position: position)
    }

    /// Parse table rows
    private func parseTableRows(_ data: Data) throws -> [[TableCell]] {
        var offset = 0
        var rows: [[TableCell]] = []

        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
            offset = newOffset

            if wireType == 2 { // row data (length-delimited)
                let (rowData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                let cells = try parseTableCells(rowData)
                if !cells.isEmpty {
                    rows.append(cells)
                }
                offset = nextOffset
            } else {
                offset = try skipField(wireType: wireType, from: data, at: offset)
            }
        }

        return rows
    }

    /// Parse cells in a table row
    private func parseTableCells(_ data: Data) throws -> [TableCell] {
        var offset = 0
        var cells: [TableCell] = []

        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
            offset = newOffset

            if wireType == 2 { // cell data
                let (cellData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                // Try to extract text from cell
                if let text = String(data: cellData, encoding: .utf8) {
                    cells.append(TableCell(text: text))
                } else if let text = try? extractCellText(cellData) {
                    cells.append(TableCell(text: text))
                }
                offset = nextOffset
            } else {
                offset = try skipField(wireType: wireType, from: data, at: offset)
            }
        }

        return cells
    }

    /// Extract text from a cell's protobuf structure
    private func extractCellText(_ data: Data) throws -> String? {
        var offset = 0

        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
            offset = newOffset

            if wireType == 2 { // string field
                let (stringData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                if let text = String(data: stringData, encoding: .utf8), !text.isEmpty {
                    return text
                }
                offset = nextOffset
            } else {
                offset = try skipField(wireType: wireType, from: data, at: offset)
            }
        }

        return nil
    }

    private func parseAttributeRun(_ data: Data) throws -> AttributeRun? {
        var offset = 0
        var length: Int = 0
        var styleType: NoteStyleType = .body
        var fontWeight: Int? = nil
        var fontSize: Float? = nil
        var fontName: String? = nil

        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
            offset = newOffset

            if fieldNumber == 1 && wireType == 0 { // length (varint)
                let (value, nextOffset) = try readVarint(from: data, at: offset)
                length = Int(value)
                offset = nextOffset
            } else if fieldNumber == 2 && wireType == 2 { // paragraph_style (length-delimited)
                let (styleData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                styleType = try parseParagraphStyle(styleData)
                offset = nextOffset
            } else if fieldNumber == 3 && wireType == 2 { // font info (length-delimited)
                let (fontData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                let fontInfo = parseFontInfo(fontData)
                fontSize = fontInfo.size
                fontName = fontInfo.name
                offset = nextOffset
            } else if fieldNumber == 5 && wireType == 0 { // font_weight (varint)
                let (value, nextOffset) = try readVarint(from: data, at: offset)
                fontWeight = Int(value)
                offset = nextOffset
            } else {
                offset = try skipField(wireType: wireType, from: data, at: offset)
            }
        }

        return AttributeRun(length: length, styleType: styleType, fontWeight: fontWeight, fontSize: fontSize, fontName: fontName)
    }

    /// Parse attribute run and extract any embedded table reference (field 12)
    /// Returns nil for run if parsing fails completely
    private func parseAttributeRunWithTable(_ data: Data, currentPosition: Int) -> (run: AttributeRun?, tableReference: TableReference?) {
        var offset = 0
        var length: Int = 0
        var styleType: NoteStyleType = .body
        var fontWeight: Int? = nil
        var fontSize: Float? = nil
        var fontName: String? = nil
        var tableUUID: String?
        var tableType: String?

        do {
            while offset < data.count {
                let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
                offset = newOffset

                if fieldNumber == 1 && wireType == 0 { // length (varint)
                    let (value, nextOffset) = try readVarint(from: data, at: offset)
                    length = Int(value)
                    offset = nextOffset
                } else if fieldNumber == 2 && wireType == 2 { // paragraph_style
                    let (styleData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                    styleType = (try? parseParagraphStyle(styleData)) ?? .body
                    offset = nextOffset
                } else if fieldNumber == 3 && wireType == 2 { // font info
                    let (fontData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                    let fontInfo = parseFontInfo(fontData)
                    fontSize = fontInfo.size
                    fontName = fontInfo.name
                    offset = nextOffset
                } else if fieldNumber == 5 && wireType == 0 { // font_weight
                    let (value, nextOffset) = try readVarint(from: data, at: offset)
                    fontWeight = Int(value)
                    offset = nextOffset
                } else if fieldNumber == 12 && wireType == 2 { // embedded object reference
                    let (refData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                    if let ref = parseEmbeddedObjectRef(refData) {
                        tableUUID = ref.uuid
                        tableType = ref.type
                    }
                    offset = nextOffset
                } else {
                    offset = try skipField(wireType: wireType, from: data, at: offset)
                }
            }
        } catch {
            // Parsing failed, return what we have
        }

        let run = AttributeRun(length: length, styleType: styleType, fontWeight: fontWeight, fontSize: fontSize, fontName: fontName)
        var tableRef: TableReference? = nil
        if let uuid = tableUUID, let type = tableType, type == "com.apple.notes.table" {
            tableRef = TableReference(uuid: uuid, type: type, position: currentPosition)
        }

        return (run, tableRef)
    }

    /// Parse font info from field 3 of attribute run
    /// Can contain: f2 = size (float32), f3 = flag, or be a string for font name
    private func parseFontInfo(_ data: Data) -> (size: Float?, name: String?) {
        // First check if this is a font name string (starts with \n followed by name)
        if let str = String(data: data, encoding: .utf8),
           str.hasPrefix("\n") || str.contains("-") {
            // Font name string like "\nSkia-Regular"
            let fontName = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return (nil, fontName.isEmpty ? nil : fontName)
        }

        // Otherwise parse as nested message with size
        var offset = 0
        var fontSize: Float? = nil

        do {
            while offset < data.count {
                let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
                offset = newOffset

                if fieldNumber == 2 && wireType == 5 { // f2 as 32-bit float (wire type 5)
                    guard offset + 4 <= data.count else { break }
                    let floatData = data.subdata(in: offset..<offset+4)
                    fontSize = floatData.withUnsafeBytes { $0.load(as: Float.self) }
                    offset += 4
                } else if wireType == 0 { // varint
                    let (_, nextOffset) = try readVarint(from: data, at: offset)
                    offset = nextOffset
                } else if wireType == 2 { // length-delimited
                    let (_, nextOffset) = try readLengthDelimited(from: data, at: offset)
                    offset = nextOffset
                } else if wireType == 5 { // 32-bit
                    offset += 4
                } else if wireType == 1 { // 64-bit
                    offset += 8
                } else {
                    break
                }
            }
        } catch {
            // Ignore parsing errors
        }

        return (fontSize, nil)
    }

    /// Parse embedded object reference (field 12 contents)
    private func parseEmbeddedObjectRef(_ data: Data) -> (uuid: String?, type: String?)? {
        var offset = 0
        var uuid: String?
        var type: String?

        do {
            while offset < data.count {
                let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
                offset = newOffset

                if fieldNumber == 1 && wireType == 2 { // UUID string
                    let (stringData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                    uuid = String(data: stringData, encoding: .utf8)
                    offset = nextOffset
                } else if fieldNumber == 2 && wireType == 2 { // type string
                    let (stringData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                    type = String(data: stringData, encoding: .utf8)
                    offset = nextOffset
                } else {
                    offset = try skipField(wireType: wireType, from: data, at: offset)
                }
            }
        } catch {
            return nil
        }

        return (uuid, type)
    }

    private func parseParagraphStyle(_ data: Data) throws -> NoteStyleType {
        var offset = 0

        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
            offset = newOffset

            if fieldNumber == 1 && wireType == 0 { // style_type (varint)
                let (value, _) = try readVarint(from: data, at: offset)
                return NoteStyleType(rawValue: Int(value)) ?? .body
            } else {
                offset = try skipField(wireType: wireType, from: data, at: offset)
            }
        }

        return .body
    }

    // MARK: - Protobuf Primitives

    private func readTag(from data: Data, at offset: Int) throws -> (fieldNumber: Int, wireType: Int, newOffset: Int) {
        let (value, newOffset) = try readVarint(from: data, at: offset)
        let fieldNumber = Int(value >> 3)
        let wireType = Int(value & 0x7)
        return (fieldNumber, wireType, newOffset)
    }

    private func readVarint(from data: Data, at offset: Int) throws -> (UInt64, Int) {
        var result: UInt64 = 0
        var shift = 0
        var currentOffset = offset

        while currentOffset < data.count {
            let byte = data[currentOffset]
            currentOffset += 1

            result |= UInt64(byte & 0x7F) << shift

            if byte & 0x80 == 0 {
                return (result, currentOffset)
            }

            shift += 7
            if shift >= 64 {
                throw NotesError.decodingFailed("Varint too long")
            }
        }

        throw NotesError.decodingFailed("Unexpected end of data reading varint")
    }

    private func readLengthDelimited(from data: Data, at offset: Int) throws -> (Data, Int) {
        let (length, newOffset) = try readVarint(from: data, at: offset)
        let endOffset = newOffset + Int(length)

        guard endOffset <= data.count else {
            throw NotesError.decodingFailed("Length-delimited field extends beyond data")
        }

        let fieldData = data.subdata(in: newOffset..<endOffset)
        return (fieldData, endOffset)
    }

    private func skipField(wireType: Int, from data: Data, at offset: Int) throws -> Int {
        switch wireType {
        case 0: // Varint
            let (_, newOffset) = try readVarint(from: data, at: offset)
            return newOffset
        case 1: // 64-bit
            return offset + 8
        case 2: // Length-delimited
            let (_, newOffset) = try readLengthDelimited(from: data, at: offset)
            return newOffset
        case 5: // 32-bit
            return offset + 4
        default:
            throw NotesError.decodingFailed("Unknown wire type: \(wireType)")
        }
    }
}
