public enum Markdown {
    public static func convert(html: String, options: MarkdownOptions = .init()) -> String {
        MarkdownConverter.htmlToMarkdown(html, options: options)
    }
}
