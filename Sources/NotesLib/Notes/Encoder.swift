import Foundation
import Compression

/// Encodes note content to gzipped protobuf format for Apple Notes
public class NoteEncoder {

    public init() {}

    /// Encode note text to ZDATA blob format
    /// - Parameter text: The full note text (title + body separated by newlines)
    /// - Returns: Gzip-compressed protobuf data ready for ZICNOTEDATA.ZDATA
    public func encode(_ text: String) throws -> Data {
        // Step 1: Build protobuf structure
        let protobuf = try buildProtobuf(text: text)

        // Step 2: Gzip compress
        return try compress(protobuf)
    }

    // MARK: - Protobuf Building

    /// Build the NoteStoreProto structure
    /// Schema: NoteStoreProto { field_1: 0, document(2) { field_1: 0, version(2): 0, note(3) { note_text(2), attribute_run(5)[] } } }
    private func buildProtobuf(text: String) throws -> Data {
        // Build Note message
        let noteMessage = buildNoteMessage(text: text)

        // Build Document message (wraps Note)
        let documentMessage = buildDocumentMessage(note: noteMessage)

        // Build NoteStoreProto (outer wrapper)
        let noteStoreProto = buildNoteStoreProto(document: documentMessage)

        return noteStoreProto
    }

    /// Build NoteStoreProto wrapper
    /// Fields: field_1 (varint 0), document (field 2, length-delimited)
    private func buildNoteStoreProto(document: Data) -> Data {
        var data = Data()

        // Field 1: varint 0 (tag = 0x08, value = 0x00)
        data.append(contentsOf: encodeTag(fieldNumber: 1, wireType: 0))
        data.append(contentsOf: encodeVarint(0))

        // Field 2: document (length-delimited)
        data.append(contentsOf: encodeTag(fieldNumber: 2, wireType: 2))
        data.append(contentsOf: encodeVarint(UInt64(document.count)))
        data.append(document)

        return data
    }

    /// Build Document message
    /// Fields: field_1 (varint 0), version (field 2, varint 0), note (field 3, length-delimited)
    private func buildDocumentMessage(note: Data) -> Data {
        var data = Data()

        // Field 1: varint 0
        data.append(contentsOf: encodeTag(fieldNumber: 1, wireType: 0))
        data.append(contentsOf: encodeVarint(0))

        // Field 2: version = 0
        data.append(contentsOf: encodeTag(fieldNumber: 2, wireType: 0))
        data.append(contentsOf: encodeVarint(0))

        // Field 3: note (length-delimited)
        data.append(contentsOf: encodeTag(fieldNumber: 3, wireType: 2))
        data.append(contentsOf: encodeVarint(UInt64(note.count)))
        data.append(note)

        return data
    }

    /// Build Note message
    /// Fields: note_text (field 2, string), attribute_run (field 5, repeated)
    private func buildNoteMessage(text: String) -> Data {
        var data = Data()

        // Process markdown: get clean text and style info
        let (cleanText, styleRuns) = processMarkdownForProtobuf(text)

        // Field 2: note_text (string)
        let textData = cleanText.data(using: .utf8) ?? Data()
        data.append(contentsOf: encodeTag(fieldNumber: 2, wireType: 2))
        data.append(contentsOf: encodeVarint(UInt64(textData.count)))
        data.append(textData)

        // Field 5: attribute_run (repeated)
        for run in styleRuns {
            data.append(contentsOf: encodeTag(fieldNumber: 5, wireType: 2))
            data.append(contentsOf: encodeVarint(UInt64(run.count)))
            data.append(run)
        }

        return data
    }

    /// Process markdown text: strip syntax and return clean text + attribute runs
    /// Returns: (cleanText, attributeRuns)
    private func processMarkdownForProtobuf(_ text: String) -> (String, [Data]) {
        var cleanLines: [String] = []
        var runs: [Data] = []

        let lines = text.components(separatedBy: "\n")

        if lines.isEmpty {
            return ("", [buildAttributeRun(length: 0, paragraphStyle: nil)])
        }

        var inCodeBlock = false

        for (index, line) in lines.enumerated() {
            var cleanLine = line
            var styleType: NoteStyleType = .body

            // Check for code block markers
            if line.hasPrefix("```") {
                inCodeBlock = !inCodeBlock
                cleanLine = "" // Remove ``` marker line
                styleType = .monospaced
            } else if inCodeBlock {
                styleType = .monospaced
                // Keep line as-is for code
            }
            // First line is always title - Notes.app applies title styling automatically
            // We use body (0) since the first line is treated specially by Notes.app
            else if index == 0 {
                styleType = .body  // Notes.app renders first line as title regardless of style_type
                // Strip # prefix if present
                if line.hasPrefix("# ") {
                    cleanLine = String(line.dropFirst(2))
                }
            }
            // Markdown headers - map to Apple Notes heading styles
            else if line.hasPrefix("#### ") {
                styleType = .subheading2  // style_type=3
                cleanLine = String(line.dropFirst(5))
            } else if line.hasPrefix("### ") {
                styleType = .subheading    // style_type=2
                cleanLine = String(line.dropFirst(4))
            } else if line.hasPrefix("## ") {
                styleType = .heading       // style_type=1 (⇧⌘H)
                cleanLine = String(line.dropFirst(3))
            } else if line.hasPrefix("# ") {
                styleType = .heading       // style_type=1 (non-first-line # becomes heading)
                cleanLine = String(line.dropFirst(2))
            }
            // Checkbox items
            else if line.hasPrefix("- [ ] ") {
                styleType = .checkbox
                cleanLine = String(line.dropFirst(6))
            } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                styleType = .checkboxChecked
                cleanLine = String(line.dropFirst(6))
            }
            // Bullet points - convert to regular text (Notes has its own bullet handling)
            else if line.hasPrefix("- ") {
                cleanLine = String(line.dropFirst(2))
            } else if line.hasPrefix("* ") {
                cleanLine = String(line.dropFirst(2))
            }

            cleanLines.append(cleanLine)

            // Calculate length including newline (except for last line)
            let isLastLine = index == lines.count - 1
            let lineLength = cleanLine.utf8.count
            let totalLength = isLastLine ? lineLength : lineLength + 1

            if totalLength > 0 || cleanLine.isEmpty {
                runs.append(buildAttributeRun(
                    length: max(totalLength, isLastLine ? 0 : 1),
                    paragraphStyle: buildParagraphStyle(styleType: styleType.rawValue)
                ))
            }
        }

        // Filter out empty runs for empty ``` lines but keep the structure
        let cleanText = cleanLines.joined(separator: "\n")

        if runs.isEmpty {
            runs.append(buildAttributeRun(length: cleanText.utf8.count, paragraphStyle: nil))
        }

        return (cleanText, runs)
    }

    /// Style types for Notes.app protobuf encoding
    /// Note: These match the public NoteStyleType in Decoder.swift
    private enum NoteStyleType: Int {
        case body = 0
        case heading = 1       // Section header (⇧⌘H) - style_type=1
        case subheading = 2    // style_type=2
        case subheading2 = 3   // style_type=3
        case monospaced = 4
        case checkbox = 102    // Fixed: was 100, should be 102
        case checkboxChecked = 103  // Fixed: was 101, should be 103
    }

    /// Build a single AttributeRun
    /// Fields: length (field 1, varint), paragraph_style (field 2, optional)
    private func buildAttributeRun(length: Int, paragraphStyle: Data?) -> Data {
        var data = Data()

        // Field 1: length (varint)
        data.append(contentsOf: encodeTag(fieldNumber: 1, wireType: 0))
        data.append(contentsOf: encodeVarint(UInt64(length)))

        // Field 2: paragraph_style (optional, length-delimited)
        if let style = paragraphStyle {
            data.append(contentsOf: encodeTag(fieldNumber: 2, wireType: 2))
            data.append(contentsOf: encodeVarint(UInt64(style.count)))
            data.append(style)
        }

        return data
    }

    /// Build ParagraphStyle message
    /// Fields: style_type (field 1, varint), alignment (field 2, varint)
    private func buildParagraphStyle(styleType: Int, alignment: Int = 0) -> Data {
        var data = Data()

        // Field 1: style_type
        data.append(contentsOf: encodeTag(fieldNumber: 1, wireType: 0))
        data.append(contentsOf: encodeVarint(UInt64(styleType)))

        // Field 2: alignment (0 = left)
        data.append(contentsOf: encodeTag(fieldNumber: 2, wireType: 0))
        data.append(contentsOf: encodeVarint(UInt64(alignment)))

        return data
    }

    // MARK: - Protobuf Primitives

    /// Encode a field tag (field number + wire type)
    private func encodeTag(fieldNumber: Int, wireType: Int) -> [UInt8] {
        let tag = (fieldNumber << 3) | wireType
        return encodeVarint(UInt64(tag))
    }

    /// Encode a varint (variable-length integer)
    private func encodeVarint(_ value: UInt64) -> [UInt8] {
        var result: [UInt8] = []
        var v = value

        while v > 0x7F {
            result.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        result.append(UInt8(v))

        // Handle zero case
        if result.isEmpty {
            result.append(0)
        }

        return result
    }

    // MARK: - Gzip Compression

    /// Compress data using gzip format
    private func compress(_ data: Data) throws -> Data {
        // Use compression framework for deflate
        let compressedData = try deflate(data)

        // Build gzip container
        return buildGzipContainer(deflatedData: compressedData, originalSize: UInt32(data.count), crc: crc32(data))
    }

    /// Deflate data using zlib
    private func deflate(_ data: Data) throws -> Data {
        let destinationBufferSize = data.count + 1024 // Some extra space
        var destinationBuffer = [UInt8](repeating: 0, count: destinationBufferSize)

        let compressedSize = data.withUnsafeBytes { sourcePtr in
            return compression_encode_buffer(
                &destinationBuffer,
                destinationBufferSize,
                sourcePtr.bindMemory(to: UInt8.self).baseAddress!,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else {
            throw NotesError.encodingError
        }

        return Data(destinationBuffer.prefix(compressedSize))
    }

    /// Build gzip container with header and trailer
    private func buildGzipContainer(deflatedData: Data, originalSize: UInt32, crc: UInt32) -> Data {
        var result = Data()

        // Gzip header (10 bytes)
        result.append(contentsOf: [
            0x1f, 0x8b,  // Magic number
            0x08,        // Compression method (deflate)
            0x00,        // Flags (none)
            0x00, 0x00, 0x00, 0x00,  // Modification time (none)
            0x00,        // Extra flags
            0x13         // OS (0x13 = macOS)
        ])

        // Compressed data
        result.append(deflatedData)

        // Gzip trailer (8 bytes)
        // CRC32 (little-endian)
        result.append(contentsOf: [
            UInt8(crc & 0xFF),
            UInt8((crc >> 8) & 0xFF),
            UInt8((crc >> 16) & 0xFF),
            UInt8((crc >> 24) & 0xFF)
        ])

        // Original size (little-endian)
        result.append(contentsOf: [
            UInt8(originalSize & 0xFF),
            UInt8((originalSize >> 8) & 0xFF),
            UInt8((originalSize >> 16) & 0xFF),
            UInt8((originalSize >> 24) & 0xFF)
        ])

        return result
    }

    /// Calculate CRC32 checksum
    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF

        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }

        return crc ^ 0xFFFFFFFF
    }
}
