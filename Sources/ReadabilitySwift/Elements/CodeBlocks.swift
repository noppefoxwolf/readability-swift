import Foundation
import SwiftSoup

enum ElementCodeBlocks {
    static func standardize(_ html: String) -> String {
        guard let document = try? SwiftSoup.parse(html), let body = document.body() else { return html }
        var replacements: [(String, String)] = []

        for figure in (try? body.select("figure[data-rehype-pretty-code-figure]")) ?? SwiftSoup.Elements() {
            if let pre = try? figure.select("pre").first() {
                let language = detectLanguage(pre)
                replacements.append(((try? figure.outerHtml()) ?? "", canonical(language: language, code: cleanCode(rawText(pre)))))
            }
        }

        for highlight in (try? body.select("div.highlight")) ?? SwiftSoup.Elements() {
            let language = detectLanguage(from: (try? highlight.attr("class")) ?? "") ?? ""
            if let pre = try? highlight.select("pre").first() {
                replacements.append(((try? highlight.outerHtml()) ?? "", canonical(language: language, code: cleanCode(rawText(pre)))))
            }
        }

        for table in (try? body.select("table.highlight-table, table.rouge-table, table.code-listing")) ?? SwiftSoup.Elements() {
            let cells = (try? table.select("td")) ?? SwiftSoup.Elements()
            guard let cell = cells.first(where: { ((try? $0.attr("class")) ?? "").contains("code") || ((try? $0.attr("class")) ?? "").contains("rouge-code") }) ?? cells.last else { continue }
            replacements.append(((try? table.outerHtml()) ?? "", canonical(language: detectLanguage(table), code: cleanCode(rawText(cell)))))
        }

        for shiki in (try? body.select("pre.shiki")) ?? SwiftSoup.Elements() {
            let language = detectLanguage(shiki)
            let lines = ((try? shiki.select("code span.line")) ?? SwiftSoup.Elements()).map(rawText)
            let code = lines.isEmpty ? rawText(shiki) : lines.joined(separator: "\n")
            replacements.append(((try? shiki.outerHtml()) ?? "", canonical(language: language, code: cleanCode(code))))
        }

        for pre in (try? body.select("pre")) ?? SwiftSoup.Elements() {
            let original = (try? pre.outerHtml()) ?? ""
            guard !replacements.contains(where: { $0.0.contains(original) }) else { continue }
            let language = detectLanguage(pre)
            replacements.append((original, canonical(language: language, code: cleanCode(rawText(pre)))))
        }

        var result = html
        for (original, replacement) in replacements where !original.isEmpty {
            guard let range = result.range(of: original) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    static func standardizeCodeBlocks(_ html: String) -> String { standardize(html) }

    private static func detectLanguage(_ element: Element) -> String {
        if let value = try? element.attr("data-lang"), !value.isEmpty { return ElementLanguages.normalizeLanguage(value) }
        if let value = try? element.attr("data-language"), !value.isEmpty { return ElementLanguages.normalizeLanguage(value) }
        if let language = detectLanguage(from: (try? element.attr("class")) ?? "") { return language }
        if let code = try? element.select("code").first() {
            if let language = detectLanguage(from: (try? code.attr("class")) ?? "") { return language }
            if let value = try? code.attr("data-lang"), !value.isEmpty { return ElementLanguages.normalizeLanguage(value) }
        }
        return ""
    }

    private static func detectLanguage(from classes: String) -> String? {
        for token in classes.split(whereSeparator: { $0.isWhitespace }) {
            let value = String(token)
            for prefix in ["language-", "lang-", "highlight-source-"] where value.lowercased().hasPrefix(prefix) {
                return ElementLanguages.normalizeLanguage(String(value.dropFirst(prefix.count)))
            }
        }
        if let match = classes.range(of: "(?i)brush:\\s*(\\w+)", options: .regularExpression) {
            let value = String(classes[match]).replacingOccurrences(of: "brush:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return ElementLanguages.normalizeLanguage(value) }
        }
        for token in classes.split(whereSeparator: { $0.isWhitespace }) where ElementLanguages.isKnownLanguage(String(token)) {
            return ElementLanguages.normalizeLanguage(String(token))
        }
        return nil
    }

    private static func rawText(_ element: Element) -> String {
        element.getChildNodes().reduce(into: "") { result, node in
            if let text = node as? TextNode { result += text.getWholeText() }
            else if let child = node as? Element { result += rawText(child) }
        }
    }

    private static func cleanCode(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "\t", with: "    ").replacingOccurrences(of: "\u{00a0}", with: " ")
        let lines = result.components(separatedBy: .newlines)
        let numbered = lines.count > 2 && lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(5).allSatisfy {
            $0.range(of: "^\\s*\\d+[\\s|]", options: .regularExpression) != nil
        }
        if numbered {
            result = lines.map { $0.replacingOccurrences(of: "^\\s*\\d+[\\s|]", with: "", options: .regularExpression) }.joined(separator: "\n")
        }
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func canonical(language: String, code: String) -> String {
        let escaped = code.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        guard !language.isEmpty else { return "<pre><code>\(escaped)</code></pre>" }
        return "<pre><code class=\"language-\(language)\" data-lang=\"\(language)\">\(escaped)</code></pre>"
    }
}
