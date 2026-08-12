import SwiftSoup

enum MarkdownTableRules {
    static func isComplex(_ table: Element) throws -> Bool {
        try table.select("[colspan],[rowspan], table table").isEmpty() == false
    }

    static func isLayout(_ table: Element) throws -> Bool {
        guard try table.select("th").isEmpty() else { return false }
        for row in try table.select("tr") {
            if try row.select("td,th").count > 1 { return false }
        }
        return true
    }

    static func simple(headers: [String], rows: [[String]]) -> String {
        let columns = max(headers.count, rows.map(\.count).max() ?? 0)
        guard columns > 0 else { return "" }
        var widths = Array(repeating: 3, count: columns)
        for (index, value) in headers.enumerated() { widths[index] = max(widths[index], escaped(value).count) }
        for row in rows { for (index, value) in row.enumerated() where index < columns { widths[index] = max(widths[index], escaped(value).count) } }
        func row(_ values: [String]) -> String {
            "|" + (0..<columns).map { index in " \(escaped(index < values.count ? values[index] : ""))\(String(repeating: " ", count: widths[index] - escaped(index < values.count ? values[index] : "").count)) |" }.joined()
        }
        let separator = "|" + widths.map { "\(String(repeating: "-", count: $0 + 2))|" }.joined()
        return "\n\n\(row(headers))\n\(separator)\n\(rows.map(row).joined(separator: "\n"))\n"
    }

    private static func escaped(_ value: String) -> String { value.replacing("|", with: "\\|") }
}
