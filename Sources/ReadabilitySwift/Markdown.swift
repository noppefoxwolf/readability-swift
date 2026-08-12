public enum Markdown {
    public static func convert(_ html: String, options: MarkdownOptions = .init()) throws -> String {
        try MarkdownConverter.htmlToMarkdown(html, options: options)
    }
}
