enum ElementHeadings {
    static func standardize(_ html: String, title: String?) -> String {
        var result = html
        if let title, !title.isEmpty {
            let normalizedTitle = normalize(title)
            if let match = result.firstMatch(of: #/(?is)<h1\b[^>]*>(.*?)</h1>/#),
               normalize(String(match.1)) == normalizedTitle {
                result.removeSubrange(match.range)
            }
        }
        result = result.replacing(/(?i)<h1\b[^>]*>/, with: "<h2>")
        result = result.replacing(/(?i)<\/h1>/, with: "</h2>")
        result = result.replacing(#/(?is)(<h[1-6]\b[^>]*>)\s*<a\b[^>]*href=["']#[^"']*["'][^>]*>(?:[#¶§🔗\s]*)</a>/#) { match in
            String(match.1)
        }
        return result
    }

    private static func normalize(_ value: String) -> String {
        value.replacing(/<[^>]+>/, with: "").replacing(/\s+/, with: " ")
            .trimmed { $0.isWhitespace || $0.isPunctuation }
            .lowercased()
    }
}
