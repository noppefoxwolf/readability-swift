import SwiftSoup

enum ElementCodeBlocks {
    static func standardize(_ html: String) throws -> String {
        // readabilityrs parses a fragment and uses ElementRef::html() for the
        // selected element. SwiftSoup builds a document shell, and its html()
        // means inner HTML, so traverse body and capture outerHtml() instead.
        let document = try SwiftSoup.parse(html)
        guard let body = document.body() else { return html }
        var replacements: [(String, String)] = []

        for figure in try body.select("figure[data-rehype-pretty-code-figure]") {
            if let pre = try figure.select("pre").first() {
                let language = try detectLanguage(pre)
                replacements.append((try figure.outerHtml(), canonical(language: language, code: cleanCode(DOMUtils.textContent(pre)))))
            }
        }

        for highlight in try body.select("div.highlight") {
            let language = detectLanguage(from: DOMUtils.attribute("class", of: highlight)) ?? ""
            if let pre = try highlight.select("pre").first() {
                replacements.append((try highlight.outerHtml(), canonical(language: language, code: cleanCode(DOMUtils.textContent(pre)))))
            }
        }

        for table in try body.select("table.highlight-table, table.rouge-table, table.code-listing") {
            let cells = try table.select("td")
            guard let cell = cells.first(where: {
                let className = DOMUtils.attribute("class", of: $0)
                return className.contains("code") || className.contains("rouge-code")
            }) ?? cells.last else { continue }
            replacements.append((try table.outerHtml(), canonical(language: try detectLanguage(table), code: cleanCode(DOMUtils.textContent(cell)))))
        }

        for shiki in try body.select("pre.shiki") {
            let language = try detectLanguage(shiki)
            let lines = (try shiki.select("code span.line")).map(DOMUtils.textContent)
            let code = lines.isEmpty ? DOMUtils.textContent(shiki) : lines.joined(separator: "\n")
            replacements.append((try shiki.outerHtml(), canonical(language: language, code: cleanCode(code))))
        }

        for pre in try body.select("pre") {
            let original = try pre.outerHtml()
            guard !replacements.contains(where: { $0.0.contains(original) }) else { continue }
            let language = try detectLanguage(pre)
            replacements.append((original, canonical(language: language, code: cleanCode(DOMUtils.textContent(pre)))))
        }

        var result = html
        for (original, replacement) in replacements where !original.isEmpty {
            guard let range = result.range(of: original) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    static func standardizeCodeBlocks(_ html: String) throws -> String { try standardize(html) }

    private static func detectLanguage(_ element: Element) throws -> String {
        let dataLanguage = DOMUtils.attribute("data-lang", of: element)
        if !dataLanguage.isEmpty { return ElementLanguages.normalizeLanguage(dataLanguage) }
        let alternateDataLanguage = DOMUtils.attribute("data-language", of: element)
        if !alternateDataLanguage.isEmpty { return ElementLanguages.normalizeLanguage(alternateDataLanguage) }
        if let language = detectLanguage(from: DOMUtils.attribute("class", of: element)) { return language }
        if let code = try element.select("code").first() {
            if let language = detectLanguage(from: DOMUtils.attribute("class", of: code)) { return language }
            let codeLanguage = DOMUtils.attribute("data-lang", of: code)
            if !codeLanguage.isEmpty { return ElementLanguages.normalizeLanguage(codeLanguage) }
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
        if let match = classes.firstMatch(of: /(?i)brush:\s*(\w+)/) {
            let value = String(match.1)
            if !value.isEmpty { return ElementLanguages.normalizeLanguage(value) }
        }
        for token in classes.split(whereSeparator: { $0.isWhitespace }) where ElementLanguages.isKnownLanguage(String(token)) {
            return ElementLanguages.normalizeLanguage(String(token))
        }
        return nil
    }

    private static func cleanCode(_ value: String) -> String {
        var result = value.replacing("\t", with: "    ").replacing("\u{00a0}", with: " ")
        let lines = result.lines().map(String.init)
        let numbered = lines.count > 2 && lines.filter { !$0.trimmed().isEmpty }.prefix(5).allSatisfy {
            $0.firstMatch(of: /^\s*\d+[\s|]/) != nil
        }
        if numbered {
            result = lines.map { $0.replacing(/^\s*\d+[\s|]/, with: "") }.joined(separator: "\n")
        }
        result = result.replacing(/\n{3,}/, with: "\n\n")
        return result.trimmed()
    }

    private static func canonical(language: String, code: String) -> String {
        let escaped = code.replacing("&", with: "&amp;").replacing("<", with: "&lt;").replacing(">", with: "&gt;")
        guard !language.isEmpty else { return "<pre><code>\(escaped)</code></pre>" }
        return "<pre><code class=\"language-\(language)\" data-lang=\"\(language)\">\(escaped)</code></pre>"
    }
}
