import Foundation
import SwiftSoup

enum PostProcessor {
    static func prepArticle(
        _ html: String,
        cleanStyles: Bool,
        cleanWhitespace: Bool,
        keepClasses: Bool = false,
        classesToPreserve: [String] = ["page"]
    ) -> String {
        guard let document = try? DOMUtils.parse(html), let body = document.body() else { return html }
        if cleanStyles {
            for element in (try? body.select("*")) ?? SwiftSoup.Elements() {
                _ = try? element.removeAttr("style")
                _ = try? element.removeAttr("align")
                _ = try? element.removeAttr("bgcolor")
                _ = try? element.removeAttr("border")
                _ = try? element.removeAttr("background")
                _ = try? element.removeAttr("cellpadding")
                _ = try? element.removeAttr("cellspacing")
                _ = try? element.removeAttr("frame")
                _ = try? element.removeAttr("hspace")
                _ = try? element.removeAttr("rules")
                _ = try? element.removeAttr("valign")
                _ = try? element.removeAttr("vspace")
            }
        }
        if cleanWhitespace {
            for element in (try? body.select("p,div,section")) ?? SwiftSoup.Elements() {
                let text = DOMUtils.normalizeWhitespace(DOMUtils.textContent(element))
                if text.isEmpty && ((try? element.select("img,video,pre,table")) ?? SwiftSoup.Elements()).isEmpty() { try? element.remove() }
            }
        }
        removeUnwantedElements(from: body)
        removeShareElements(from: body)
        removeNavigationElements(from: body)
        if cleanWhitespace { removeEmptyParagraphs(from: body) }
        var result = (try? body.html()) ?? html
        if cleanWhitespace {
            result = Preformatted.mapOutside(result) { fragment in
                fragment
                    .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
                    .replacingOccurrences(of: "[ ]{2,}", with: " ", options: .regularExpression)
            }
        }
        return result
    }

    static func removeTitleFromContent(_ html: String, title: String) -> String {
        guard let document = try? DOMUtils.parse(html), let body = document.body() else { return html }
        let normalizedTitle = DOMUtils.normalizeWhitespace(title).lowercased()
        guard !normalizedTitle.isEmpty else { return html }
        for element in (try? body.select("h1,h2")) ?? SwiftSoup.Elements() where DOMUtils.normalizeWhitespace(DOMUtils.textContent(element)).lowercased() == normalizedTitle {
            try? element.remove()
        }
        for element in (try? body.select("h1,h2")) ?? SwiftSoup.Elements() {
            let candidate = DOMUtils.normalizeWhitespace(DOMUtils.textContent(element)).lowercased()
            guard !candidate.isEmpty else { continue }
            let ratio = Double(min(candidate.count, normalizedTitle.count)) / Double(max(candidate.count, normalizedTitle.count))
            if ratio > 0.8 && (candidate.contains(normalizedTitle) || normalizedTitle.contains(candidate)) { try? element.remove() }
        }
        for header in (try? body.select("header")) ?? SwiftSoup.Elements() where DOMUtils.normalizeWhitespace(DOMUtils.textContent(header)).isEmpty {
            try? header.remove()
        }
        return (try? body.html()) ?? html
    }

    private static func removeUnwantedElements(from root: Element) {
        for selector in ["script", "style", "form", "fieldset", "input", "button", "textarea", "select", "iframe", "object", "embed", "link", "footer", "aside"] {
            for element in (try? root.select(selector)) ?? SwiftSoup.Elements() { try? element.remove() }
        }
    }

    private static func removeShareElements(from root: Element) {
        for tag in ["div", "span", "aside", "section"] {
            for element in (try? root.select(tag)) ?? SwiftSoup.Elements() {
                let marker = DOMUtils.classAndID(element).lowercased()
                let tokens = marker.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
                if tokens.contains("share") || tokens.contains("social") || tokens.contains("sharedaddy") {
                    try? element.remove()
                }
            }
        }
    }

    private static func removeNavigationElements(from root: Element) {
        for selector in ["nav", "[role=navigation]", "div[class*=nav],section[class*=nav],ul[class*=nav],ol[class*=nav]",
                         "div[class*=navbar],section[class*=navbar],ul[class*=navbar],ol[class*=navbar]",
                         "div[class*=menu],section[class*=menu],ul[class*=menu],ol[class*=menu]",
                         "div[class*=breadcrumbs],section[class*=breadcrumbs],ul[class*=breadcrumbs],ol[class*=breadcrumbs]",
                         "div[class*=sidebar],section[class*=sidebar],ul[class*=sidebar],ol[class*=sidebar]"] {
            for element in (try? root.select(selector)) ?? SwiftSoup.Elements() {
                guard shouldRemoveNavigationElement(element) else { continue }
                try? element.remove()
            }
        }
    }

    private static func shouldRemoveNavigationElement(_ element: Element) -> Bool {
        let textLength = DOMUtils.getInnerText(element, normalizeSpaces: false).utf8.count
        let paragraphCount = (try? element.select("p").count) ?? 0
        if textLength > 600 && paragraphCount > 0 { return false }
        return textLength < 400 || DOMUtils.linkDensity(element) > 0.55
    }

    private static func removeEmptyParagraphs(from root: Element) {
        for _ in 0..<5 {
            var removed = false
            for element in (try? root.select("p")) ?? SwiftSoup.Elements() {
                let text = DOMUtils.normalizeWhitespace(DOMUtils.textContent(element))
                let hasMedia = !((try? element.select("img,video,pre,table")) ?? SwiftSoup.Elements()).isEmpty()
                let hasOnlyBreaks = DOMUtils.textContent(element).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !hasMedia && (text.isEmpty || hasOnlyBreaks) {
                    try? element.remove()
                    removed = true
                }
            }
            if !removed { break }
        }
        for br in (try? root.select("br")) ?? SwiftSoup.Elements() {
            let previousTag = (try? br.previousElementSibling()?.tagName().lowercased()) ?? ""
            let nextTag = (try? br.nextElementSibling()?.tagName().lowercased()) ?? ""
            let blockTags = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6"]
            if blockTags.contains(previousTag) && blockTags.contains(nextTag) { try? br.remove() }
        }
    }
}
