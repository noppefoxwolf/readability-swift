enum MarkdownLinkRules {
    static func link(inner: String, href: String, title: String, options: MarkdownOptions, state: inout MarkdownConversionState) -> String {
        let trimmed = inner.trimmed()
        guard !href.isEmpty else { return trimmed }
        if options.sanitizeURLs && Utils.isDangerousURL(href) { return trimmed }
        let text = trimmed.isEmpty ? href : trimmed
        let destination = MarkdownTextRules.escapeURLDestination(href)
        let titlePart = title.isEmpty ? "" : " \"\(MarkdownTextRules.escapeTitle(title))\""
        if options.linkStyle == .reference {
            let id = state.linkReferences.count + 1
            state.linkReferences.append((String(id), destination))
            return "[\(text)][\(id)]"
        }
        return "[\(text)](\(destination)\(titlePart))"
    }
}
