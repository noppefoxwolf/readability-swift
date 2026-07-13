import Foundation
import SwiftSoup

enum Cleaner {
    static func prepDocument(_ html: String) -> String {
        var result = html
        let patterns = [
            "(?is)<script\\b[^>]*>.*?</script>",
            "(?is)<style\\b[^>]*>.*?</style>",
            "(?is)<form\\b[^>]*>.*?</form>"
        ]
        for pattern in patterns { result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression) }
        result = result.replacingOccurrences(of: "<font\\b", with: "<span", options: .regularExpression)
        result = result.replacingOccurrences(of: "</font>", with: "</span>", options: .regularExpression)
        if let regex = try? NSRegularExpression(pattern: "(?is)<noscript\\b[^>]*>(.*?)</noscript>") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            for match in regex.matches(in: result, range: range).reversed() {
                guard let whole = Range(match.range, in: result), let inner = Range(match.range(at: 1), in: result) else { continue }
                let content = String(result[inner])
                if content.range(of: "<img\\b", options: [.regularExpression]) != nil {
                    result.replaceSubrange(whole, with: content)
                }
            }
        }
        return result
    }

    static func cleanArticleContentLight(_ html: String, baseURL: URL?) -> ReadabilityResult<String> {
        guard let document = try? DOMUtils.parse(html), let body = document.body() else { return .success(html) }
        removeNavigationSections(from: body)
        return .success((try? body.html()) ?? html)
    }

    static func cleanArticleContent(_ html: String, baseURL: URL?) -> ReadabilityResult<String> {
        switch cleanArticleContentLight(html, baseURL: baseURL) {
        case let .failure(error): return .failure(error)
        case let .success(value):
            guard let document = try? DOMUtils.parse(value), let body = document.body() else { return .success(value) }
            removeEmptyElements(from: body)
            removeConditionally(from: body)
            return .success((try? body.html()) ?? value)
        }
    }

    static func replaceBRS(_ html: String) -> String {
        let pattern = "(?i)(<br\\s*/?>(\\s|&nbsp;?)*){2,}"
        guard html.range(of: pattern, options: .regularExpression) != nil else { return html }

        // readabilityrs turns consecutive breaks into paragraph nodes. When
        // the fragment has an outer element, keep that wrapper and replace
        // only its inner content so the returned HTML remains well formed.
        if let openEnd = html.firstIndex(of: ">"),
           let closeStart = html.range(of: "</", options: .backwards)?.lowerBound,
           closeStart > openEnd {
            let opening = String(html[...openEnd])
            let innerStart = html.index(after: openEnd)
            let inner = String(html[innerStart..<closeStart])
            let closing = String(html[closeStart...])
            let parts = splitOnRegex(inner, pattern: pattern)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count > 1 {
                return opening + parts.map { "<p>\($0)</p>" }.joined(separator: "\n") + closing
            }
        }

        return splitOnRegex(html, pattern: pattern)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "<p>\($0)</p>" }
            .joined(separator: "\n")
    }

    private static func splitOnRegex(_ value: String, pattern: String) -> [String] {
        let marker = "\u{001F}"
        let replaced = value.replacingOccurrences(of: pattern, with: marker, options: .regularExpression)
        return replaced.components(separatedBy: marker)
    }

    private static func removeUnwantedElements(from root: Element) {
        for selector in ["script", "style", "noscript", "iframe", "object", "embed", "form", "input", "button", "textarea", "select", "link"] {
            for element in (try? root.select(selector)) ?? SwiftSoup.Elements() { try? element.remove() }
        }
    }

    private static func removeNavigationSections(from root: Element) {
        let selectors = [
            "nav", "[role=navigation]", ".navbar", ".breadcrumbs", ".sidebar",
            "div[class*=sidebar],section[class*=sidebar],ul[class*=sidebar],ol[class*=sidebar]",
            "div[id*=navbar],section[id*=navbar],ul[id*=navbar],ol[id*=navbar]",
            "div[id*=menu],section[id*=menu],ul[id*=menu],ol[id*=menu]",
            "div[id*=breadcrumbs],section[id*=breadcrumbs],ul[id*=breadcrumbs],ol[id*=breadcrumbs]",
            "div[id*=sidebar],section[id*=sidebar],ul[id*=sidebar],ol[id*=sidebar]"
        ]
        for selector in selectors {
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

    private static func removeEmptyElements(from root: Element) {
        for element in (try? root.select("p,div,section,span")) ?? SwiftSoup.Elements() {
            let text = DOMUtils.normalizeWhitespace(DOMUtils.textContent(element))
            let hasMedia = !((try? element.select("img,video,pre,table")) ?? SwiftSoup.Elements()).isEmpty()
            if text.isEmpty && !hasMedia { try? element.remove() }
        }
    }

    private static func removeConditionally(from root: Element) {
        for element in (try? root.select("form,fieldset")) ?? SwiftSoup.Elements() { try? element.remove() }
        let dataTables = Set(((try? root.select("table")) ?? SwiftSoup.Elements())
            .filter(isDataTable)
            .map(ObjectIdentifier.init))
        for tag in ["table", "ul", "ol", "div", "section"] {
            let elements = (try? root.select(tag)) ?? SwiftSoup.Elements()
            for element in elements where shouldRemove(element, tag: tag, dataTables: dataTables) {
                try? element.remove()
            }
        }
    }

    private static func shouldRemove(_ element: Element, tag: String, dataTables: Set<ObjectIdentifier>) -> Bool {
        let classID = DOMUtils.classAndID(element).lowercased()
        if ["comment", "disqus", "remark", "replies", "respond"].contains(where: classID.contains) { return true }

        let text = DOMUtils.getInnerText(element, normalizeSpaces: false)
        let contentLength = text.count
        if contentLength > 600 { return false }

        let isList = tag == "ul" || tag == "ol" || isMostlyList(element, contentLength: contentLength)
        let tableIsData = dataTables.contains(ObjectIdentifier(element))
        if tag == "table" && tableIsData { return false }
        if DOMUtils.ancestors(element, limit: 0).contains(where: { dataTables.contains(ObjectIdentifier($0)) }) { return false }
        if DOMUtils.ancestors(element, limit: 0).contains(where: { $0.tagName().lowercased() == "code" }) { return false }
        if DOMUtils.descendants(element).contains(where: { dataTables.contains(ObjectIdentifier($0)) }) { return false }

        let linkDensity = contentLength == 0 ? 1.0 : DOMUtils.linkDensity(element)
        let weight = cleanerClassWeight(element)
        if weight < 0 && (linkDensity > 0.25 || contentLength < 100) { return true }
        if text.filter({ ",،﹐､，；;⸲⹁⸴⹉⹌".contains($0) }).count >= 10 { return false }

        let paragraphCount = (try? element.select("p").count) ?? 0
        let imageCount = (try? element.select("img").count) ?? 0
        let listCount = max(0, ((try? element.select("li").count) ?? 0) - 100)
        let inputCount = (try? element.select("input").count) ?? 0
        let headingDensity = textDensity(element, selector: "h1,h2,h3,h4,h5,h6")
        let embeds = (try? element.select("object,embed,iframe")) ?? SwiftSoup.Elements()
        if embeds.contains(where: nodeHasAllowedVideo) { return false }
        if matchesWholeText(text, pattern: Constants.regexps.adWords) || matchesWholeText(text, pattern: Constants.regexps.loadingWords) { return true }
        let textDensityValue = textDensity(element, selector: "span,li,td,blockquote,dl,div,img,ol,p,pre,table,ul")
        let isFigureChild = DOMUtils.ancestors(element, limit: 0).contains { $0.tagName().lowercased() == "figure" }

        var shouldRemove = false
        if !isFigureChild && imageCount > 1 && paragraphCount > 0 && Double(paragraphCount) / Double(imageCount) < 0.5 { shouldRemove = true }
        if !isList && listCount > paragraphCount { shouldRemove = true }
        if inputCount > paragraphCount / 3 { shouldRemove = true }
        if !isList && !isFigureChild && headingDensity < 0.9 && contentLength < 25 && linkDensity > 0 { shouldRemove = true }
        if !isList && weight < 25 && linkDensity > 0.2 { shouldRemove = true }
        if weight >= 25 && linkDensity > 0.5 { shouldRemove = true }
        if (embeds.count == 1 && contentLength < 75) || embeds.count > 1 { shouldRemove = true }
        if imageCount == 0 && textDensityValue == 0 { shouldRemove = true }

        if isList && shouldRemove {
            let simpleChildren = element.getChildNodes().compactMap { $0 as? Element }.allSatisfy { child in
                child.getChildNodes().compactMap { $0 as? Element }.count <= 1
            }
            if simpleChildren && listCount > 0 && imageCount == listCount { shouldRemove = false }
        }
        return shouldRemove
    }

    private static func isMostlyList(_ element: Element, contentLength: Int) -> Bool {
        guard contentLength > 0 else { return false }
        let listText = ((try? element.select("ul,ol")) ?? SwiftSoup.Elements())
            .reduce(0) { $0 + DOMUtils.getInnerText($1, normalizeSpaces: false).count }
        return Double(listText) / Double(max(contentLength, 1)) > 0.9
    }

    private static func cleanerClassWeight(_ element: Element) -> Int {
        var weight = 0
        for attribute in ["class", "id"] {
            let value = ((try? element.attr(attribute)) ?? "")
            if matches(value, Constants.regexps.negative) { weight -= 25 }
            if matches(value, Constants.regexps.positive) { weight += 25 }
        }
        return weight
    }

    private static func textDensity(_ element: Element, selector: String) -> Double {
        let total = DOMUtils.getInnerText(element, normalizeSpaces: false).count
        guard total > 0 else { return 0 }
        let childText = ((try? element.select(selector)) ?? SwiftSoup.Elements())
            .reduce(0) { $0 + DOMUtils.getInnerText($1, normalizeSpaces: false).count }
        return Double(childText) / Double(total)
    }

    private static func nodeHasAllowedVideo(_ element: Element) -> Bool {
        if let attributes = element.getAttributes() {
            if attributes.asList().contains(where: { matches($0.getValue(), Constants.regexps.videos) }) { return true }
        }
        return element.tagName().lowercased() == "object" && matches(DOMUtils.textContent(element), Constants.regexps.videos)
    }

    private static func matchesWholeText(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isDataTable(_ element: Element) -> Bool {
        let hasHeader = !((try? element.select("thead, th, caption, col, colgroup, tfoot")) ?? SwiftSoup.Elements()).isEmpty()
        let rows = (try? element.select("tr")) ?? SwiftSoup.Elements()
        let columns = rows.first.map { $0.children().count } ?? 0
        return hasHeader || (rows.count >= 2 && columns >= 2)
    }

}
