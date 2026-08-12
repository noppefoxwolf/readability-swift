enum MarkdownImageRules {
    static func image(alt: String, source: String, title: String, options: MarkdownOptions) -> String {
        guard !source.isEmpty, !(options.sanitizeURLs && Utils.isDangerousURL(source)) else { return "" }
        let escapedAlt = MarkdownTextRules.escapeLinkText(alt)
        let escapedSource = MarkdownTextRules.escapeURLDestination(source)
        let escapedTitle = MarkdownTextRules.escapeTitle(title)
        return title.isEmpty ? "![\(escapedAlt)](\(escapedSource))" : "![\(escapedAlt)](\(escapedSource) \"\(escapedTitle)\")"
    }

    static func figure(alt: String, source: String, caption: String?, options: MarkdownOptions) -> String {
        guard !source.isEmpty, !(options.sanitizeURLs && Utils.isDangerousURL(source)) else { return "" }
        let value = caption?.trimmed().isEmpty == false ? caption! : alt
        return "\n\n![\(MarkdownTextRules.escapeLinkText(value))](\(MarkdownTextRules.escapeURLDestination(source)))\n\n"
    }
}
