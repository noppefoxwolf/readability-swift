enum MarkdownBlockquoteRules {
    static func render(_ inner: String, depth: Int, callout: String?) -> String {
        let prefix = String(repeating: "> ", count: max(depth, 1))
        var lines: [String] = []
        if let callout, !callout.isEmpty { lines.append("\(prefix)[!\(callout.uppercased())]") }
        let content = inner.trimmed()
        if content.isEmpty { return "\n\n>\n\n" }
        let normalized = content.replacing(/\n[ \t]*\n/, with: "\n\n")
            .replacing(/\n{3,}/, with: "\n\n")
        lines.append(contentsOf: normalized.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.trimmed().isEmpty ? prefix.trimmed() : prefix + line
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
        let value = line.trimmed()
        return !value.isEmpty && value.allSatisfy { $0 == ">" }
    }
}
