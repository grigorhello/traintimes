import Foundation

/// One record of a GTFS file, read by column name.
struct GTFSRecord {
    fileprivate let columns: [String: Int]
    fileprivate let fields: [String]

    /// The field in the named column; empty when the file has no such column or the record leaves it out.
    subscript(_ column: String) -> String {
        guard let index = columns[column], index < fields.count else { return "" }
        return fields[index]
    }
}

/// Reads GTFS CSV files (TT-130): a header row, then one record per line. Fields may be quoted, with "" for a quote
/// mark; a UTF-8 byte order mark, CRLF line ends and blank lines are skipped. A quoted field cannot span lines.
enum GTFSCSV {
    /// Calls `body` with each record. With `keeping`, a record is split only when its value in that column passes the
    /// test, so a large file (stop_times) skips the rows it does not need cheaply.
    static func forEach(
        in data: Data, keeping filter: (column: String, keep: (String) -> Bool)? = nil, _ body: (GTFSRecord) throws -> Void
    ) rethrows {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let end = base + raw.count
            var cursor = base
            if raw.count >= 3, base[0] == 0xEF, base[1] == 0xBB, base[2] == 0xBF { cursor += 3 }

            var columns: [String: Int]?
            var filterIndex: Int?
            while cursor < end {
                let newline = find(0x0A, from: cursor, to: end) ?? end
                var lineEnd = newline
                if lineEnd > cursor, lineEnd[-1] == 0x0D { lineEnd -= 1 }
                let line = UnsafeBufferPointer(start: cursor, count: lineEnd - cursor)
                cursor = newline < end ? newline + 1 : end
                guard !line.isEmpty else { continue }

                guard let header = columns else {
                    let names = fields(line).map { $0.trimmingCharacters(in: .whitespaces) }
                    let header = Dictionary(names.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
                    columns = header
                    filterIndex = filter.flatMap { header[$0.column] }
                    continue
                }
                if let filter, let filterIndex, !filter.keep(field(filterIndex, of: line)) { continue }
                try body(GTFSRecord(columns: header, fields: fields(line)))
            }
        }
    }

    /// One field of a line, without splitting the rest when the line has no quotes.
    private static func field(_ index: Int, of line: UnsafeBufferPointer<UInt8>) -> String {
        guard let base = line.baseAddress, find(0x22, from: base, to: base + line.count) == nil else {
            let all = fields(line)
            return index < all.count ? all[index] : ""
        }
        var start = base
        let end = base + line.count
        for _ in 0..<index {
            guard let comma = find(0x2C, from: start, to: end) else { return "" }
            start = comma + 1
        }
        let stop = find(0x2C, from: start, to: end) ?? end
        return String(decoding: UnsafeBufferPointer(start: start, count: stop - start), as: UTF8.self)
    }

    /// The first `byte` at or after `start`, before `end`.
    private static func find(_ byte: UInt8, from start: UnsafePointer<UInt8>, to end: UnsafePointer<UInt8>) -> UnsafePointer<UInt8>? {
        guard start < end, let found = memchr(start, Int32(byte), end - start) else { return nil }
        return UnsafePointer(found.assumingMemoryBound(to: UInt8.self))
    }

    private static func fields(_ line: UnsafeBufferPointer<UInt8>) -> [String] {
        guard let base = line.baseAddress else { return [] }
        let end = base + line.count
        var result: [String] = []
        // Fast path: no quotes, so fields are the runs between commas.
        if find(0x22, from: base, to: end) == nil {
            var start = base
            while true {
                let stop = find(0x2C, from: start, to: end) ?? end
                result.append(String(decoding: UnsafeBufferPointer(start: start, count: stop - start), as: UTF8.self))
                guard stop < end else { return result }
                start = stop + 1
            }
        }
        var field: [UInt8] = []
        var inQuotes = false
        var index = 0
        while index < line.count {
            let byte = line[index]
            if inQuotes {
                if byte == 0x22 {
                    if index + 1 < line.count, line[index + 1] == 0x22 {
                        field.append(0x22)
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(byte)
                }
            } else if byte == 0x22 {
                inQuotes = true
            } else if byte == 0x2C {
                result.append(String(decoding: field, as: UTF8.self))
                field.removeAll(keepingCapacity: true)
            } else {
                field.append(byte)
            }
            index += 1
        }
        result.append(String(decoding: field, as: UTF8.self))
        return result
    }
}
