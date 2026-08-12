enum MarkdownListRules {
    static func unordered(_ inner: String, options: MarkdownOptions, state: MarkdownConversionState) -> String {
        "\(String(repeating: "  ", count: max(state.listDepth - 1, 0)))\(options.bulletCharacter) \(inner.trimmed())\n"
    }

    static func ordered(_ inner: String, counter: Int, state: MarkdownConversionState) -> String {
        "\(String(repeating: "  ", count: max(state.listDepth - 1, 0)))\(counter). \(inner.trimmed())\n"
    }

    static func task(_ inner: String, checked: Bool, options: MarkdownOptions, state: MarkdownConversionState) -> String {
        "\(String(repeating: "  ", count: max(state.listDepth - 1, 0)))\(options.bulletCharacter) \(checked ? "[x]" : "[ ]") \(inner.trimmed())\n"
    }
}
