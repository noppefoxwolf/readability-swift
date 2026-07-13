import Foundation

enum MarkdownTextRules {
    static func escape(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            if "\\`*_~".contains(character) { result.append("\\") }
            result.append(character)
        }
    }

    static func inlineCode(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.contains("`") ? "`` \(trimmed) ``" : "`\(trimmed)`"
    }
}
