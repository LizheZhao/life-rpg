import Foundation

/// Minimal RFC 4180 reader: quoted fields, `""` escapes, commas/newlines inside quotes, CRLF.
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }   // skip blank lines
            row = []
        }

        while let c = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    let next = iterator.next()
                    if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": endField()
                case "\n", "\r\n", "\r": endRow()      // "\r\n" is a single Character in Swift
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    /// Rows keyed by header name. Short rows are padded with empty strings.
    static func records(_ text: String) -> (header: [String], rows: [[String: String]]) {
        var all = parse(text)
        guard !all.isEmpty else { return ([], []) }
        let header = all.removeFirst().map { $0.trimmingCharacters(in: .whitespaces) }
        let rows = all.map { cells in
            Dictionary(uniqueKeysWithValues: header.enumerated().map { i, name in
                (name, i < cells.count ? cells[i] : "")
            })
        }
        return (header, rows)
    }
}
