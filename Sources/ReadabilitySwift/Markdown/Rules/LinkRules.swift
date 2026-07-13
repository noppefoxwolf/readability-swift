enum MarkdownLinkRules {
    static func link(inner: String, href: String, title: String, options: MarkdownOptions, state: inout MarkdownConversionState) -> String {
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !href.isEmpty else { return trimmed }
        let text = trimmed.isEmpty ? href : trimmed
        let titlePart = title.isEmpty ? "" : " \"\(title.replacingOccurrences(of: "\"", with: "\\\""))\""
        if options.linkStyle == .reference {
            let id = state.linkReferences.count + 1
            state.linkReferences.append((String(id), href))
            return "[\(text)][\(id)]"
        }
        return "[\(text)](\(href)\(titlePart))"
    }
}
