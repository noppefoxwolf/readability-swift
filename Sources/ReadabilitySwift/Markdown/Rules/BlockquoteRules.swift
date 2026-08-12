enum MarkdownBlockquoteRules {
    static func render(_ inner: String, depth: Int, callout: String?) -> String {
        let prefix = String(repeating: "> ", count: max(depth, 1))
        var lines: [String] = []
        if let callout, !callout.isEmpty { lines.append("\(prefix)[!\(callout.uppercased())]") }
        let content = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty { return "\n\n>\n\n" }
        let normalized = content
            .replacingOccurrences(of: "\\n[ \\t]*\\n", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        lines.append(contentsOf: normalized.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.trimmingCharacters(in: .whitespaces).isEmpty ? prefix.trimmingCharacters(in: .whitespaces) : prefix + line
        })
        var collapsed: [String] = []
        for line in lines {
            let emptyQuote = isEmptyQuote(line)
            if emptyQuote, collapsed.last.map(isEmptyQuote) == true { continue }
            collapsed.append(line)
        }
        return "\n\n\(collapsed.joined(separator: "\n"))\n\n"
    }

    private static func isEmptyQuote(_ line: String) -> Bool {
        let value = line.trimmingCharacters(in: .whitespaces)
        return !value.isEmpty && value.allSatisfy { $0 == ">" }
    }
}
