import Foundation
import SwiftSoup

enum ElementFootnotes {
    private struct Definition {
        let container: String
        let content: String
    }

    static func standardize(_ html: String) -> String {
        // scraper's fragment root and ElementRef::html() do not map directly to
        // SwiftSoup. Parse into a body shell and use outerHtml() wherever the
        // Rust implementation serializes the selected container itself.
        guard let document = try? SwiftSoup.parse(html), let body = document.body() else { return html }
        var references: [String] = []
        for sup in (try? body.select("sup")) ?? SwiftSoup.Elements() {
            guard let anchor = try? sup.select("a").first() else { continue }
            let href = (try? anchor.attr("href")) ?? ""
            if href.lowercased().contains("#fn") || href.lowercased().contains("#footnote"), let original = try? sup.outerHtml() {
                references.append(original)
            }
        }
        for anchor in (try? body.select("a.footnote-ref, a.footnote-anchor")) ?? SwiftSoup.Elements() {
            guard !DOMUtils.ancestors(anchor, limit: 0).contains(where: { $0.tagName().lowercased() == "sup" }),
                  let original = try? anchor.outerHtml(), !references.contains(original) else { continue }
            references.append(original)
        }

        var definitions: [Definition] = []
        for selector in ["div.footnotes", "section.footnotes", "div.footnotes-footer", "section[role=doc-endnotes]", "ol.footnote-list"] {
            for container in (try? body.select(selector)) ?? SwiftSoup.Elements() {
                guard let containerHTML = try? container.outerHtml() else { continue }
                for item in (try? container.select("li")) ?? SwiftSoup.Elements() {
                    let content = extractContent(item)
                    if !content.isEmpty { definitions.append(Definition(container: containerHTML, content: content)) }
                }
                if !definitions.isEmpty { break }
            }
            if !definitions.isEmpty { break }
        }
        if definitions.isEmpty {
            for item in (try? body.select("div.footnote[data-component-name]")) ?? SwiftSoup.Elements() {
                let content = DOMUtils.normalizeWhitespace(DOMUtils.textContent(item))
                if let container = try? item.outerHtml(), !content.isEmpty { definitions.append(Definition(container: container, content: content)) }
            }
        }
        guard !references.isEmpty || !definitions.isEmpty else { return html }

        var result = html
        for (index, original) in references.enumerated() {
            let number = index + 1
            let canonical = "<sup id=\"fnref:\(number)\"><a href=\"#fn:\(number)\">\(number)</a></sup>"
            result = result.replacingOccurrences(of: original, with: canonical)
        }
        for definition in definitions { result = result.replacingOccurrences(of: definition.container, with: "") }
        if !definitions.isEmpty {
            let items = definitions.enumerated().map { index, definition in
                "<li class=\"footnote\" id=\"fn:\(index + 1)\"><p>\(definition.content)</p><a href=\"#fnref:\(index + 1)\" class=\"footnote-backref\">↩</a></li>"
            }.joined()
            result += "<div id=\"footnotes\"><ol>\(items)</ol></div>"
        }
        return result
    }

    static func standardizeFootnotes(_ html: String) -> String { standardize(html) }

    private static func extractContent(_ item: Element) -> String {
        var content = ""
        for node in item.getChildNodes() {
            if let child = node as? Element {
                let className = ((try? child.attr("class")) ?? "").lowercased()
                if child.tagName().lowercased() == "a" && (className.contains("backref") || className.contains("footnote-back")) { continue }
                content += DOMUtils.textContent(child)
            } else if let text = node as? TextNode {
                content += text.getWholeText()
            }
        }
        return DOMUtils.normalizeWhitespace(content).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
