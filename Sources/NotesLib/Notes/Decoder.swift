import Foundation
import Compression

/// Decodes note content from gzipped protobuf format
public class NoteDecoder {

    public init() {}

    /// Decode note content from raw ZDATA blob
    public func decode(_ data: Data) throws -> String {
        // Step 1: Decompress gzip
        let decompressed = try decompress(data)

        // Step 2: Parse protobuf to extract text
        // The protobuf structure is:
        // NoteStoreProto { Document { Note { note_text (field 2) } } }
        // We'll do a simple parse to extract the text field
        return try extractNoteText(from: decompressed)
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

    /// Simple protobuf parser to extract note text
    /// Schema: NoteStoreProto.document(2).note(3).note_text(2)
    private func extractNoteText(from data: Data) throws -> String {
        var offset = 0

        // Parse NoteStoreProto, looking for field 2 (document)
        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
            offset = newOffset

            if fieldNumber == 2 && wireType == 2 { // document (length-delimited)
                let (documentData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                offset = nextOffset

                // Parse Document, looking for field 3 (note)
                if let noteText = try parseDocument(documentData) {
                    return noteText
                }
            } else {
                offset = try skipField(wireType: wireType, from: data, at: offset)
            }
        }

        throw NotesError.decodingFailed("Could not find note text in protobuf")
    }

    private func parseDocument(_ data: Data) throws -> String? {
        var offset = 0

        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
            offset = newOffset

            if fieldNumber == 3 && wireType == 2 { // note (length-delimited)
                let (noteData, nextOffset) = try readLengthDelimited(from: data, at: offset)
                offset = nextOffset

                // Parse Note, looking for field 2 (note_text)
                if let text = try parseNote(noteData) {
                    return text
                }
            } else {
                offset = try skipField(wireType: wireType, from: data, at: offset)
            }
        }

        return nil
    }

    private func parseNote(_ data: Data) throws -> String? {
        var offset = 0

        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = try readTag(from: data, at: offset)
            offset = newOffset

            if fieldNumber == 2 && wireType == 2 { // note_text (string)
                let (stringData, _) = try readLengthDelimited(from: data, at: offset)
                return String(data: stringData, encoding: .utf8)
            } else {
                offset = try skipField(wireType: wireType, from: data, at: offset)
            }
        }

        return nil
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
