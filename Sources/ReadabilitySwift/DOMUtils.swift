import SwiftSoup

enum DOMUtils {
    static func parse(_ html: String, baseURI: String? = nil) throws -> Document {
        do {
            let document = try SwiftSoup.parse(html, baseURI ?? "")
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

    static func attribute(_ name: String, of element: Element) -> String {
        do {
            return try element.attr(name)
        } catch {
            assertionFailure("Invalid static HTML attribute name '\(name)': \(error)")
            return ""
        }
    }

    static func classAndID(_ element: Element) -> String {
        let className = attribute("class", of: element)
        let id = attribute("id", of: element)
        return "\(className) \(id)".trimmed()
    }

    static func linkDensity(_ element: Element) throws -> Double {
        let text = getInnerText(element, normalizeSpaces: false)
        guard !text.isEmpty else { return 0 }
        let links = try element.select("a")
        guard !links.isEmpty() else { return 0 }
        let linkText = try links.reduce(into: 0.0) { total, link in
            let href = try link.attr("href")
            // readabilityrs discounts hash-only anchors because they are
            // usually in-page navigation rather than article links.
            total += Double(getInnerText(link, normalizeSpaces: false).utf8.count) * (href.hasPrefix("#") && href.count > 1 ? 0.3 : 1.0)
        }
        return linkText / Double(text.utf8.count)
    }

    static func descendants(_ element: Element) throws -> [Element] {
        Array(try element.select("*"))
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
            if !isLocallyVisible(node) { return false }
            current = node.parent()
        }
        return true
    }

    // A serializer which has already checked an ancestor only needs this local
    // check for each child. Walking every ancestor again is O(n * depth).
    static func isLocallyVisible(_ element: Element) -> Bool {
        if element.hasAttr("hidden") { return false }
        let ariaHidden = attribute("aria-hidden", of: element).lowercased()
        let isFallbackImage = classAndID(element).lowercased().contains("fallback-image")
        if ariaHidden == "true" && !isFallbackImage { return false }
        let style = attribute("style", of: element).lowercased()
        return !style.contains("display:none") && !style.contains("display: none")
            && !style.contains("visibility:hidden") && !style.contains("visibility: hidden")
    }

    static func articleDirection(_ document: Document) throws -> String? {
        guard let html = try document.select("html").first else { return nil }
        let value = try html.attr("dir").trimmed().lowercased()
        return ["ltr", "rtl", "auto"].contains(value) ? value : nil
    }

    static func normalizeWhitespace(_ value: String) -> String {
        value.collapsingRepeatedWhitespace()
    }

    static func elementTextLength(_ html: String) throws -> Int {
        let document = try parse(html)
        guard let body = document.body() else { return 0 }
        return getInnerText(body, normalizeSpaces: false).utf8.count
    }

    private static func rawText(from element: Element) -> String {
        element.getChildNodes().reduce(into: "") { result, node in
            if let text = node as? TextNode { result += text.getWholeText() }
            else if let child = node as? Element { result += rawText(from: child) }
        }
    }
}
