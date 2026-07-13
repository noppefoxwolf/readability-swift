enum MarkdownListRules {
    static func unordered(_ inner: String, options: MarkdownOptions, state: MarkdownConversionState) -> String {
        "\(String(repeating: "  ", count: max(state.listDepth - 1, 0)))\(options.bulletCharacter) \(inner.trimmingCharacters(in: .whitespacesAndNewlines))\n"
    }

    static func ordered(_ inner: String, counter: Int, state: MarkdownConversionState) -> String {
        "\(String(repeating: "  ", count: max(state.listDepth - 1, 0)))\(counter). \(inner.trimmingCharacters(in: .whitespacesAndNewlines))\n"
    }

    static func task(_ inner: String, checked: Bool, options: MarkdownOptions, state: MarkdownConversionState) -> String {
        "\(String(repeating: "  ", count: max(state.listDepth - 1, 0)))\(options.bulletCharacter) \(checked ? "[x]" : "[ ]") \(inner.trimmingCharacters(in: .whitespacesAndNewlines))\n"
    }
}
