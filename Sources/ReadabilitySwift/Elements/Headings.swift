enum ElementHeadings {
    static func standardize(_ html: String, title: String?) -> String {
        var result = html
        if let title, !title.isEmpty {
            let normalizedTitle = normalize(title)
            let pattern = "(?is)<h1\\b[^>]*>(.*?)</h1>"
            if let match = SwiftRegex.firstMatch(in: result, pattern: pattern),
               match.captures.indices.contains(1),
               let inner = match.captures[1],
               normalize(String(inner)) == normalizedTitle {
                result.removeSubrange(match.range)
            }
        }
        result = SwiftRegex.replacing(in: result, pattern: "(?i)<h1\\b[^>]*>", with: "<h2>")
        result = SwiftRegex.replacing(in: result, pattern: "(?i)</h1>", with: "</h2>")
        result = SwiftRegex.replacing(in: result, pattern: "(?is)(<h[1-6]\\b[^>]*>)\\s*<a\\b[^>]*href=[\"']#[^\"']*[\"'][^>]*>([#¶§🔗\\s]*)</a>", with: "$1")
        return result
    }

    private static func normalize(_ value: String) -> String {
        SwiftRegex.replacing(in: SwiftRegex.replacing(in: value, pattern: "<[^>]+>", with: ""), pattern: "\\s+", with: " ")
            .trimmed { $0.isWhitespace || $0.isPunctuation }
            .lowercased()
    }
}
