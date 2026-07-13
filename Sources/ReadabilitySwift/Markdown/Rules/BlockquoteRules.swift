enum MarkdownBlockquoteRules {
    static func render(_ inner: String, depth: Int, callout: String?) -> String {
        let prefix = String(repeating: "> ", count: max(depth, 1))
        var lines: [String] = []
        if let callout, !callout.isEmpty { lines.append("\(prefix)[!\(callout.uppercased())]") }
        let content = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty { return "\n\n>\n\n" }
        lines.append(contentsOf: content.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.trimmingCharacters(in: .whitespaces).isEmpty ? prefix.trimmingCharacters(in: .whitespaces) : prefix + line
        })
        return "\n\n\(lines.joined(separator: "\n"))\n\n"
    }
}
