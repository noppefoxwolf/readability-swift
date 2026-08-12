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

    static func escapeLinkText(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            if "\\[]".contains(character) { result.append("\\") }
            result.append(character)
        }
    }

    static func escapeURLDestination(_ value: String) -> String {
        // Rust iterates Unicode scalar values (char). Iterate scalars here as
        // well instead of Swift Characters so controls cannot hide inside a
        // grapheme cluster before the destination is emitted.
        let stripped = String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        guard stripped.contains(where: { " ()<>".contains($0) }) else { return stripped }
        let inner = stripped
            .replacingOccurrences(of: "<", with: "%3C")
            .replacingOccurrences(of: ">", with: "%3E")
        return "<\(inner)>"
    }

    static func escapeTitle(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            if character == "\n" || character == "\r" { return }
            if character == "\\" || character == "\"" { result.append("\\") }
            result.append(character)
        }
    }
}
