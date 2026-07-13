enum MarkdownCodeRules {
    static func codeBlock(_ code: String, language: String, options: MarkdownOptions) -> String {
        let fence = code.contains("```") && options.codeFence == "`" ? "~~~~" : String(repeating: String(options.codeFence), count: 3)
        return "\n\n\(fence)\(language)\n\(code)\n\(fence)\n\n"
    }
}
