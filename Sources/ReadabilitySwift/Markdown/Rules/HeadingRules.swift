enum MarkdownHeadingRules {
    static func heading(level: Int, inner: String, options: MarkdownOptions) -> String {
        let value = inner.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !value.isEmpty else { return "" }
        if options.headingStyle == .setext && level <= 2 {
            let marker = level == 1 ? "=" : "-"
            return "\n\n\(value)\n\(String(repeating: marker, count: max(value.count, 3)))\n\n"
        }
        return "\n\n\(String(repeating: "#", count: level)) \(value)\n\n"
    }
}
