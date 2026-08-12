import SwiftSoup

enum ElementFootnotes {
    private struct Definition {
        let container: String
        let content: String
    }

    static func standardize(_ html: String) throws -> String {
        // scraper's fragment root and ElementRef::html() do not map directly to
        // SwiftSoup. Parse into a body shell and use outerHtml() wherever the
        // Rust implementation serializes the selected container itself.
        let document = try SwiftSoup.parse(html)
        guard let body = document.body() else { return html }
        var references: [String] = []
        for sup in try body.select("sup") {
            guard let anchor = try sup.select("a").first() else { continue }
            let href = DOMUtils.attribute("href", of: anchor)
            if href.lowercased().contains("#fn") || href.lowercased().contains("#footnote") {
                references.append(try sup.outerHtml())
            }
        }
        for anchor in try body.select("a.footnote-ref, a.footnote-anchor") {
            guard !DOMUtils.ancestors(anchor, limit: 0).contains(where: { $0.tagName().lowercased() == "sup" }),
                  !references.contains(try anchor.outerHtml()) else { continue }
            let original = try anchor.outerHtml()
            references.append(original)
        }

        var definitions: [Definition] = []
        for selector in ["div.footnotes", "section.footnotes", "div.footnotes-footer", "section[role=doc-endnotes]", "ol.footnote-list"] {
            for container in try body.select(selector) {
                let containerHTML = try container.outerHtml()
                for item in try container.select("li") {
                    let content = extractContent(item)
                    if !content.isEmpty { definitions.append(Definition(container: containerHTML, content: content)) }
                }
                if !definitions.isEmpty { break }
            }
            if !definitions.isEmpty { break }
        }
        if definitions.isEmpty {
            for item in try body.select("div.footnote[data-component-name]") {
                let content = DOMUtils.normalizeWhitespace(DOMUtils.textContent(item))
                if !content.isEmpty { definitions.append(Definition(container: try item.outerHtml(), content: content)) }
            }
        }
        guard !references.isEmpty || !definitions.isEmpty else { return html }

        var result = html
        for (index, original) in references.enumerated() {
            let number = index + 1
            let canonical = "<sup id=\"fnref:\(number)\"><a href=\"#fn:\(number)\">\(number)</a></sup>"
            result = result.replacing(original, with: canonical)
        }
        for definition in definitions { result = result.replacing(definition.container, with: "") }
        if !definitions.isEmpty {
            let items = definitions.enumerated().map { index, definition in
                "<li class=\"footnote\" id=\"fn:\(index + 1)\"><p>\(definition.content)</p><a href=\"#fnref:\(index + 1)\" class=\"footnote-backref\">↩</a></li>"
            }.joined()
            result += "<div id=\"footnotes\"><ol>\(items)</ol></div>"
        }
        return result
    }

    static func standardizeFootnotes(_ html: String) throws -> String { try standardize(html) }

    private static func extractContent(_ item: Element) -> String {
        var content = ""
        for node in item.getChildNodes() {
            if let child = node as? Element {
                let className = DOMUtils.attribute("class", of: child).lowercased()
                if child.tagName().lowercased() == "a" && (className.contains("backref") || className.contains("footnote-back")) { continue }
                content += DOMUtils.textContent(child)
            } else if let text = node as? TextNode {
                content += text.getWholeText()
            }
        }
        return DOMUtils.normalizeWhitespace(content).trimmed()
    }
}
