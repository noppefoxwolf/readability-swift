enum MarkdownMediaRules {
    static func iframe(_ source: String) -> String {
        guard !source.isEmpty else { return "" }
        let lower = source.lowercased()
        let label = lower.contains("youtube.com") || lower.contains("youtu.be") ? "Video" :
            (lower.contains("twitter.com") || lower.range(of: "x.com/[^/]+/status", options: .regularExpression) != nil ? "Tweet" : "Embed")
        return "[\(label)](\(source))"
    }

    static func media(label: String, source: String) -> String {
        source.isEmpty ? "" : "[\(label)](\(source))"
    }
}
