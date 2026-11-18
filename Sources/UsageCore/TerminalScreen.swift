import Foundation

/// Replay cursor movement and erasure instead of concatenating terminal frames.
/// This prevents old percentages from surviving a CLI redraw.
public struct TerminalScreen {
    public static func render(_ data: Data, columns: Int = 180, rows: Int = 120) -> String {
        let width = max(20, min(columns, 300)), height = max(10, min(rows, 300))
        let blank = Array(repeating: Character(" "), count: width)
        var cells = Array(repeating: blank, count: height)
        var row = 0, column = 0, savedRow = 0, savedColumn = 0
        let chars = Array(String(decoding: data, as: UTF8.self))
        var i = 0
        func clampRow(_ value: Int) -> Int { max(0, min(height - 1, value)) }
        func clampColumn(_ value: Int) -> Int { max(0, min(width - 1, value)) }
        while i < chars.count {
            let c = chars[i]
            if c == "\u{1b}", i + 1 < chars.count {
                i += 1
                if chars[i] == "[" {
                    let start = i + 1
                    i += 1
                    while i < chars.count, !(chars[i].asciiValue.map { (64...126).contains($0) } ?? false) { i += 1 }
                    guard i < chars.count else { break }
                    let raw = String(chars[start..<i])
                    let values = raw.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
                    let first = max(1, values.first ?? 1)
                    switch chars[i] {
                    case "A": row = clampRow(row - first)
                    case "B": row = clampRow(row + first)
                    case "C": column = clampColumn(column + first)
                    case "D": column = clampColumn(column - first)
                    case "E": row = clampRow(row + first); column = 0
                    case "F": row = clampRow(row - first); column = 0
                    case "G", "`": column = clampColumn(first - 1)
                    case "d": row = clampRow(first - 1)
                    case "H", "f":
                        row = clampRow(first - 1)
                        column = clampColumn(max(1, values.count > 1 ? values[1] : 1) - 1)
                    case "K":
                        let mode = values.first ?? 0
                        let range = mode == 2 ? 0..<width : (mode == 1 ? 0..<min(width, column + 1) : column..<width)
                        for x in range { cells[row][x] = " " }
                    case "J":
                        let mode = values.first ?? 0
                        if mode == 2 || mode == 3 { cells = Array(repeating: blank, count: height) }
                        else if mode == 0 {
                            for x in column..<width { cells[row][x] = " " }
                            if row + 1 < height { for y in (row + 1)..<height { cells[y] = blank } }
                        } else if mode == 1 {
                            for y in 0..<row { cells[y] = blank }
                            for x in 0...column { cells[row][x] = " " }
                        }
                    case "s": if raw.isEmpty { savedRow = row; savedColumn = column }
                    case "u": if raw.isEmpty { row = savedRow; column = savedColumn }
                    default: break // colors, private modes, reports, cursor shape
                    }
                } else if chars[i] == "]" || chars[i] == "P" {
                    i += 1
                    while i < chars.count {
                        if chars[i] == "\u{7}" { break }
                        if chars[i] == "\u{1b}", i + 1 < chars.count, chars[i + 1] == "\\" { i += 1; break }
                        i += 1
                    }
                } else if chars[i] == "7" { savedRow = row; savedColumn = column }
                else if chars[i] == "8" { row = savedRow; column = savedColumn }
            } else if c == "\r\n" || c == "\n" || c == "\r" {
                // Swift treats CRLF as one Character.
                if c != "\r" {
                    row += 1
                    if row >= height { cells.removeFirst(); cells.append(blank); row = height - 1 }
                }
                if c != "\n" { column = 0 }
            } else if c == "\u{8}" { column = max(0, column - 1) }
            else if c == "\t" { column = clampColumn((column / 8 + 1) * 8) }
            else if c.unicodeScalars.first.map({ $0.value >= 32 && $0.value != 127 }) == true {
                cells[row][column] = c
                let scalar = c.unicodeScalars.first!.value
                let wide = (0x1F300...0x1FAFF).contains(scalar) || (0x4E00...0x9FFF).contains(scalar)
                if wide, column + 1 < width { cells[row][column + 1] = " " }
                column += wide ? 2 : 1
                if column >= width {
                    column = 0; row += 1
                    if row >= height { cells.removeFirst(); cells.append(blank); row = height - 1 }
                }
            }
            i += 1
        }
        return cells.map { String($0).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
