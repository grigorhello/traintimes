import Compression
import Foundation

/// Reads the files in a ZIP archive: the central directory, then each entry stored or deflated. Enough for the GO GTFS
/// download (TT-130); no ZIP64, encryption or split archives.
struct ZipArchive: Sendable {
    enum ZipError: Error, Equatable {
        case notAZip
        case unsupported(String)
        case corrupt(String)
    }

    private struct Entry: Sendable {
        let method: Int
        let compressedSize: Int
        let size: Int
        let headerOffset: Int
    }

    private let bytes: [UInt8]
    /// Keyed by file name without its folder, so a feed zipped inside a folder reads the same.
    private let entries: [String: Entry]

    init(data: Data) throws {
        let bytes = [UInt8](data)
        // The end of central directory record: the last 22 bytes, before a comment of up to 64 KB.
        guard bytes.count >= 22 else { throw ZipError.notAZip }
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        var end = bytes.count - 22
        while end >= lowest, Self.u32(bytes, end) != 0x0605_4B50 { end -= 1 }
        guard end >= lowest else { throw ZipError.notAZip }

        var offset = Self.u32(bytes, end + 16)
        var entries: [String: Entry] = [:]
        for _ in 0..<Self.u16(bytes, end + 10) {
            guard offset + 46 <= bytes.count, Self.u32(bytes, offset) == 0x0201_4B50 else {
                throw ZipError.corrupt("central directory")
            }
            let nameLength = Self.u16(bytes, offset + 28)
            guard offset + 46 + nameLength <= bytes.count else { throw ZipError.corrupt("central directory") }
            let path = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            if !path.hasSuffix("/"), let name = path.split(separator: "/").last {
                entries[String(name)] = Entry(
                    method: Self.u16(bytes, offset + 10),
                    compressedSize: Self.u32(bytes, offset + 20),
                    size: Self.u32(bytes, offset + 24),
                    headerOffset: Self.u32(bytes, offset + 42)
                )
            }
            offset += 46 + nameLength + Self.u16(bytes, offset + 30) + Self.u16(bytes, offset + 32)
        }
        self.bytes = bytes
        self.entries = entries
    }

    /// The file's contents; nil when the archive has no file of that name.
    func data(named name: String) throws -> Data? {
        guard let entry = entries[name] else { return nil }
        guard entry.size != 0xFFFF_FFFF, entry.compressedSize != 0xFFFF_FFFF else { throw ZipError.unsupported("ZIP64") }
        let header = entry.headerOffset
        guard header + 30 <= bytes.count, Self.u32(bytes, header) == 0x0403_4B50 else { throw ZipError.corrupt(name) }
        let start = header + 30 + Self.u16(bytes, header + 26) + Self.u16(bytes, header + 28)
        guard start + entry.compressedSize <= bytes.count else { throw ZipError.corrupt(name) }

        switch entry.method {
        case 0:
            return Data(bytes[start..<(start + entry.compressedSize)])
        case 8:
            guard entry.size > 0 else { return Data() }
            var output = Data(count: entry.size)
            // COMPRESSION_ZLIB reads raw DEFLATE (RFC 1951), the ZIP entry format.
            let written = output.withUnsafeMutableBytes { out in
                bytes.withUnsafeBufferPointer { input in
                    compression_decode_buffer(
                        out.baseAddress!.assumingMemoryBound(to: UInt8.self), entry.size,
                        input.baseAddress! + start, entry.compressedSize,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            guard written == entry.size else { throw ZipError.corrupt(name) }
            return output
        default:
            throw ZipError.unsupported("compression method \(entry.method)")
        }
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> Int {
        u16(bytes, offset) | u16(bytes, offset + 2) << 16
    }
}
