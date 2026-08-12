import SwiftSoup

enum DOMUtils {
    static func parse(_ html: String) throws -> Document {
        do {
            let document = try SwiftSoup.parse(html)
            // SwiftSoup pretty-prints by default and can therefore introduce
            // text-node whitespace that scraper/html5ever does not synthesize.
            // Extraction scores and Markdown goldens observe that whitespace.
            document.outputSettings().prettyPrint(pretty: false)
            return document
        }
        catch { throw ReadabilityError.parsingFailed(error.localizedDescription) }
    }

    static func textContent(_ element: Element) -> String {
        // SwiftSoup's Element.text() normalizes whitespace and inserts spacing
        // around some elements. readabilityrs collects scraper Text nodes
        // verbatim, so walk TextNode.getWholeText() instead.
        rawText(from: element)
    }

    static func getInnerText(_ element: Element, normalizeSpaces: Bool = true) -> String {
        let value = textContent(element).trimmed()
        return normalizeSpaces ? normalizeWhitespace(value) : value
    }

    static func ownText(_ element: Element) -> String {
        element.ownText()
    }

    static func classAndID(_ element: Element) -> String {
        let className = (try? element.attr("class")) ?? ""
        let id = (try? element.attr("id")) ?? ""
        return "\(className) \(id)".trimmed()
    }

    static func linkDensity(_ element: Element) -> Double {
        let text = getInnerText(element, normalizeSpaces: false)
        guard !text.isEmpty, let links = try? element.select("a"), !links.isEmpty() else { return 0 }
        let linkText = links.reduce(into: 0.0) { total, link in
            let href = (try? link.attr("href")) ?? ""
            // readabilityrs discounts hash-only anchors because they are
            // usually in-page navigation rather than article links.
            total += Double(getInnerText(link, normalizeSpaces: false).utf8.count) * (href.hasPrefix("#") && href.count > 1 ? 0.3 : 1.0)
        }
        return linkText / Double(text.utf8.count)
    }

    static func descendants(_ element: Element) -> [Element] {
        Array((try? element.select("*")) ?? SwiftSoup.Elements())
    }

    static func ancestors(_ element: Element, limit: Int = 5) -> [Element] {
        var result: [Element] = []
        var current = element.parent()
        while let parent = current, limit == 0 || result.count < limit {
            result.append(parent)
            current = parent.parent()
        }
        return result
    }

    static func isPhrasingContent(_ element: Element) -> Bool {
        let tag = element.tagName().uppercased()
        if Constants.phrasingElems.contains(tag) { return true }
        if ["A", "DEL", "INS"].contains(tag) {
            return element.getChildNodes().compactMap { $0 as? Element }.allSatisfy(isPhrasingContent)
        }
        return false
    }

    static func hasChildBlockElement(_ element: Element) -> Bool {
        return element.getChildNodes().compactMap { $0 as? Element }.contains { !isPhrasingContent($0) }
    }

    static func isProbablyVisible(_ element: Element) -> Bool {
        var current: Element? = element
        while let node = current {
            if node.hasAttr("hidden") { return false }
            let ariaHidden = ((try? node.attr("aria-hidden")) ?? "").lowercased()
            if ariaHidden == "true" && !classAndID(node).lowercased().contains("fallback-image") { return false }
            let style = ((try? node.attr("style")) ?? "").lowercased()
            if style.contains("display:none") || style.contains("display: none") || style.contains("visibility:hidden") || style.contains("visibility: hidden") { return false }
            current = node.parent()
        }
        return true
    }

    static func articleDirection(_ document: Document) -> String? {
        guard let html = (try? document.select("html"))?.first else { return nil }
        let value = ((try? html.attr("dir")) ?? "").trimmed().lowercased()
        return ["ltr", "rtl", "auto"].contains(value) ? value : nil
    }

    static func normalizeWhitespace(_ value: String) -> String {
        value.collapsingRepeatedWhitespace()
    }

    static func elementTextLength(_ html: String) -> Int {
        guard let document = try? parse(html), let body = document.body() else { return 0 }
        return getInnerText(body, normalizeSpaces: false).utf8.count
    }

    private static func rawText(from element: Element) -> String {
        element.getChildNodes().reduce(into: "") { result, node in
            if let text = node as? TextNode { result += text.getWholeText() }
            else if let child = node as? Element { result += rawText(from: child) }
        }
    }
}
