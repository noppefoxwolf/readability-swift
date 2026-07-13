enum MarkdownImageRules {
    static func image(alt: String, source: String, title: String) -> String {
        guard !source.isEmpty else { return "" }
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        return title.isEmpty ? "![\(alt)](\(source))" : "![\(alt)](\(source) \"\(escapedTitle)\")"
    }

    static func figure(alt: String, source: String, caption: String?) -> String {
        guard !source.isEmpty else { return "" }
        let value = caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? caption! : alt
        return "\n\n![\(value)](\(source))\n\n"
    }
}
