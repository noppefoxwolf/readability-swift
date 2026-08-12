import SwiftSoup

enum Cleaner {
    static func prepDocument(_ html: String) -> String {
        var result = html
        result = SwiftRegex.replacing(in: result, pattern: "(?is)<form\\b[^>]*>.*?</form>", with: "")
        result = SwiftRegex.replacing(in: result, pattern: "<font\\b", with: "<span")
        result = SwiftRegex.replacing(in: result, pattern: "</font>", with: "</span>")
        result = SwiftRegex.replacingMatches(
            in: result,
            pattern: "(?is)<noscript\\b[^>]*>(.*?)</noscript>"
        ) { captures in
            guard captures.indices.contains(1), let content = captures[1],
                  SwiftRegex.contains(String(content), pattern: "<img\\b") else { return nil }
            return String(content)
        }
        return result
    }

    static func removeUnsafeElements(from document: Document) {
        // readabilityrs removes these after parsing because a source regex cannot
        // recognize every HTML-valid closing tag spelling. SwiftSoup exposes a
        // mutable tree instead of scraper's NodeIds, so remove the selected nodes
        // directly while preserving the same preprocessing order.
        for element in (try? document.select("script,style,noscript,template")) ?? SwiftSoup.Elements() {
            try? element.remove()
        }
    }

    static func cleanArticleContentLight(_ html: String) -> ReadabilityResult<String> {
        guard let document = try? DOMUtils.parse(html), let body = document.body() else { return .success(html) }
        removeNavigationSections(from: body)
        return .success((try? body.html()) ?? html)
    }

    static func cleanArticleContent(
        _ html: String,
        allowedVideoRegex: Regex<Substring>? = nil
    ) -> ReadabilityResult<String> {
        switch cleanArticleContentLight(html) {
        case let .failure(error): return .failure(error)
        case let .success(value):
            guard let document = try? DOMUtils.parse(value), let body = document.body() else { return .success(value) }
            removeConditionally(from: body, allowedVideoRegex: allowedVideoRegex)
            return .success((try? body.html()) ?? value)
        }
    }

    static func replaceBRS(_ html: String) -> String {
        let pattern = "(?i)(<br\\s*/?>(\\s|&nbsp;?)*){2,}"
        guard SwiftRegex.contains(html, pattern: pattern) else { return html }

        // readabilityrs turns consecutive breaks into paragraph nodes. When
        // the fragment has an outer element, keep that wrapper and replace
        // only its inner content so the returned HTML remains well formed.
        if let openEnd = html.firstIndex(of: ">"),
           let closeStart = html.lastRange(of: "</")?.lowerBound,
           closeStart > openEnd {
            let opening = String(html[...openEnd])
            let innerStart = html.index(after: openEnd)
            let inner = String(html[innerStart..<closeStart])
            let closing = String(html[closeStart...])
            let parts = splitOnRegex(inner, pattern: pattern)
                .map { $0.trimmed() }
                .filter { !$0.isEmpty }
            if parts.count > 1 {
                return opening + parts.map { "<p>\($0)</p>" }.joined(separator: "\n") + closing
            }
        }

        return splitOnRegex(html, pattern: pattern)
            .map { $0.trimmed() }
            .filter { !$0.isEmpty }
            .map { "<p>\($0)</p>" }
            .joined(separator: "\n")
    }

    private static func splitOnRegex(_ value: String, pattern: String) -> [String] {
        SwiftRegex.split(value, pattern: pattern)
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

    private static func removeConditionally(
        from root: Element,
        allowedVideoRegex: Regex<Substring>?
    ) {
        // readabilityrs stores ego_tree NodeIds for data-table membership.
        // ObjectIdentifier is the SwiftSoup reference-identity equivalent; the
        // set must never be reused after reparsing the HTML into another tree.
        let dataTables = Set(((try? root.select("table")) ?? SwiftSoup.Elements())
            .filter(isDataTable)
            .map(ObjectIdentifier.init))
        for tag in ["form", "fieldset", "table", "ul", "ol", "div", "section"] {
            let elements = (try? root.select(tag)) ?? SwiftSoup.Elements()
            // readabilityrs first collects every NodeId to detach for a tag,
            // then mutates the tree. Removing while evaluating would change a
            // later ancestor's text/count metrics in SwiftSoup.
            let removals = elements.filter { element in
                tag == "form" || tag == "fieldset"
                    || shouldRemove(
                        element,
                        tag: tag,
                        dataTables: dataTables,
                        allowedVideoRegex: allowedVideoRegex
                    )
            }
            for element in removals {
                try? element.remove()
            }
        }
    }

    private static func shouldRemove(
        _ element: Element,
        tag: String,
        dataTables: Set<ObjectIdentifier>,
        allowedVideoRegex: Regex<Substring>?
    ) -> Bool {
        let classID = DOMUtils.classAndID(element).lowercased()
        if ["comment", "disqus", "remark", "replies", "respond"].contains(where: classID.contains) { return true }

        let text = DOMUtils.getInnerText(element, normalizeSpaces: false)
        let trimmedText = text.trimmed()
        // readabilityrs's cleaner measures Rust String byte lengths and counts
        // every link at full weight here. This intentionally differs from the
        // extraction scorer, which discounts hash-only navigation links.
        let contentLength = trimmedText.utf8.count
        if contentLength > 600 { return false }

        let isList = tag == "ul" || tag == "ol" || isMostlyList(element, contentLength: contentLength)
        let tableIsData = dataTables.contains(ObjectIdentifier(element))
        if tag == "table" && tableIsData { return false }
        if DOMUtils.ancestors(element, limit: 0).contains(where: { dataTables.contains(ObjectIdentifier($0)) }) { return false }
        if DOMUtils.ancestors(element, limit: 0).contains(where: { $0.tagName().lowercased() == "code" }) { return false }
        if DOMUtils.descendants(element).contains(where: { dataTables.contains(ObjectIdentifier($0)) }) { return false }

        let linkDensity = cleanerLinkDensity(element, contentLength: contentLength)
        let weight = cleanerClassWeight(element)
        if weight < 0 && (linkDensity > 0.25 || contentLength < 100) { return true }
        if trimmedText.filter({ $0 == "," }).count >= 10 { return false }

        let paragraphCount = (try? element.select("p").count) ?? 0
        let imageCount = (try? element.select("img").count) ?? 0
        let listCount = max(0, ((try? element.select("li").count) ?? 0) - 100)
        let inputCount = (try? element.select("input").count) ?? 0
        let headingDensity = textDensity(element, selector: "h1,h2,h3,h4,h5,h6")
        let embeds = (try? element.select("object,embed,iframe")) ?? SwiftSoup.Elements()
        if embeds.contains(where: { nodeHasAllowedVideo($0, allowedVideoRegex: allowedVideoRegex) }) { return false }
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
        if imageCount == 0 && textDensityValue == 0 {
            // SwiftSoup can foster invalid paragraph/media children outside a
            // positive content section, leaving only its heading text behind.
            // scraper keeps those children attached, so preserve the compact
            // heading wrapper that readabilityrs still sees as text-bearing.
            let isFosteredContentWrapper = weight >= 25 && contentLength >= 25 && headingDensity > 0
            if !isFosteredContentWrapper { shouldRemove = true }
        }

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
        let lists = (try? element.select("ul,ol")) ?? SwiftSoup.Elements()
        // readabilityrs uses untrimmed ElementRef::text() for descendant
        // lists, divided by the parent's trimmed content length. SwiftSoup's
        // text helpers discard formatting-only boundary nodes, so measure the
        // serialized list text here to retain the same whitespace signal.
        let listText = lists
            .reduce(0) { $0 + serializedCleanerText($1).utf8.count }
        return Double(listText) / Double(max(contentLength, 1)) > 0.9
    }

    private static func cleanerLinkDensity(_ element: Element, contentLength: Int) -> Double {
        guard contentLength > 0 else { return 1 }
        let linkLength = ((try? element.select("a")) ?? SwiftSoup.Elements()).reduce(0) {
            $0 + serializedCleanerText($1).utf8.count
        }
        return Double(linkLength) / Double(contentLength)
    }

    private static func serializedCleanerText(_ element: Element) -> String {
        guard let html = try? element.html() else { return DOMUtils.getInnerText(element, normalizeSpaces: false) }
        let withoutMarkup = SwiftRegex.replacing(
            in: html,
            pattern: "(?s)<!--.*?-->|<[^>]*>",
            with: ""
        )
        return Utils.unescapeHTMLEntities(withoutMarkup)
    }

    private static func cleanerClassWeight(_ element: Element) -> Int {
        var weight = 0
        for attribute in ["class", "id"] {
            let value = ((try? element.attr(attribute)) ?? "")
            if SwiftRegex.containsLiteralAlternative(value, pattern: Constants.regexps.negative, caseInsensitive: true) { weight -= 25 }
            if SwiftRegex.containsLiteralAlternative(value, pattern: Constants.regexps.positive, caseInsensitive: true) { weight += 25 }
        }
        return weight
    }

    private static func textDensity(_ element: Element, selector: String) -> Double {
        let total = DOMUtils.getInnerText(element, normalizeSpaces: false).utf8.count
        guard total > 0 else { return 0 }
        let childText = ((try? element.select(selector)) ?? SwiftSoup.Elements())
            .reduce(0) { $0 + DOMUtils.getInnerText($1, normalizeSpaces: false).utf8.count }
        return Double(childText) / Double(total)
    }

    private static func nodeHasAllowedVideo(
        _ element: Element,
        allowedVideoRegex: Regex<Substring>?
    ) -> Bool {
        if let attributes = element.getAttributes() {
            if attributes.asList().contains(where: { attribute in
                let value = attribute.getValue()
                return matches(value, Constants.regexps.videos)
                    || allowedVideoRegex.map { regex in value.firstMatch(of: regex) != nil } == true
            }) { return true }
        }
        guard element.tagName().lowercased() == "object" else { return false }
        let content = DOMUtils.textContent(element)
        return matches(content, Constants.regexps.videos)
            || allowedVideoRegex.map { content.firstMatch(of: $0) != nil } == true
    }

    private static func matchesWholeText(_ value: String, pattern: String) -> Bool {
        SwiftRegex.contains(value, pattern: pattern, caseInsensitive: true)
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        SwiftRegex.contains(value, pattern: pattern, caseInsensitive: true)
    }

    private static func isDataTable(_ element: Element) -> Bool {
        let hasHeader = !((try? element.select("thead, th, caption, col, colgroup, tfoot")) ?? SwiftSoup.Elements()).isEmpty()
        let rows = (try? element.select("tr")) ?? SwiftSoup.Elements()
        let columns = rows.first.map { $0.children().count } ?? 0
        return hasHeader || (rows.count >= 2 && columns >= 2)
    }

}
