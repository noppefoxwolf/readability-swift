import SwiftSoup

enum ElementMath {
    static func standardize(_ html: String) -> String {
        // SwiftSoup has no common Element root for parseFragment's returned
        // nodes. A document body supplies the traversal root used by scraper's
        // Html::parse_fragment; outerHtml() then matches ElementRef::html().
        guard let document = try? SwiftSoup.parse(html), let body = document.body() else { return html }
        var replacements: [(String, String)] = []
        for selector in ["mjx-container", "span.MathJax", "span.katex"] {
            for element in (try? body.select(selector)) ?? SwiftSoup.Elements() {
                guard let latex = extractLatex(element), let original = try? element.outerHtml() else { continue }
                let className = ((try? element.attr("class")) ?? "").lowercased()
                let displayValue = ((try? element.attr("display")) ?? "").lowercased()
                let id = ((try? element.attr("id")) ?? "").lowercased()
                let display = displayValue == "block" || className.contains("display") || id.contains("display") ? "block" : "inline"
                replacements.append((original, "<math data-latex=\"\(escape(latex))\" display=\"\(display)\"></math>"))
            }
        }
        var result = html
        for (original, replacement) in replacements where !original.isEmpty {
            if let range = result.range(of: original) { result.replaceSubrange(range, with: replacement) }
        }
        return result
    }

    static func standardizeMath(_ html: String) -> String { standardize(html) }

    private static func extractLatex(_ element: Element) -> String? {
        for attribute in ["data-latex", "alt"] {
            let value = (try? element.attr(attribute)) ?? ""
            if !value.isEmpty { return value }
        }
        if let annotation = try? element.select("annotation[encoding=\"application/x-tex\"]").first() {
            let value = DOMUtils.textContent(annotation).trimmed()
            if !value.isEmpty { return value }
        }
        if let script = try? element.select("script[type=\"math/tex\"]").first() {
            let value = DOMUtils.textContent(script).trimmed()
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func escape(_ value: String) -> String {
        value.replacing("&", with: "&amp;").replacing("\"", with: "&quot;").replacing("<", with: "&lt;").replacing(">", with: "&gt;")
    }
}
