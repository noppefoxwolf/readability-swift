enum MarkdownFootnoteRules {
    static func reference(_ id: String) -> String { "[^\(id)]" }

    static func definitions(_ notes: [(String, String)]) -> String {
        guard !notes.isEmpty else { return "" }
        return "\n\n---\n\n" + notes.map { "[^\($0.0)]: \($0.1.trimmingCharacters(in: .whitespacesAndNewlines))" }.joined(separator: "\n")
    }
}
