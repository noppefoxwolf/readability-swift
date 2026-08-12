import SwiftSoup

enum Cleaner {
    static func prepDocument(_ html: String) -> String {
        var result = html
        result = result.replacing(#/(?is)<form\b[^>]*>.*?</form>/#, with: "")
        result = result.replacing(/<font\b/, with: "<span")
        result = result.replacing(/<\/font>/, with: "</span>")
        result = result.replacing(#/(?is)<noscript\b[^>]*>(.*?)</noscript>/#) { match in
            match.1.firstMatch(of: /<img\b/) == nil ? String(match.0) : String(match.1)
        }
        return result
    }

    static func removeUnsafeElements(from document: Document) throws {
        // readabilityrs removes these after parsing because a source regex cannot
        // recognize every HTML-valid closing tag spelling. SwiftSoup exposes a
        // mutable tree instead of scraper's NodeIds, so remove the selected nodes
        // directly while preserving the same preprocessing order.
        for element in try document.select("script,style,noscript,template") {
            try element.remove()
        }
    }

    static func cleanArticleContentLight(_ html: String) throws -> String {
        let document = try DOMUtils.parse(html)
        guard let body = document.body() else { return html }
        try removeNavigationSections(from: body)
        return try body.html()
    }

    static func cleanArticleContent(
        _ html: String,
        allowedVideoRegex: Regex<Substring>? = nil
    ) throws -> String {
        let value = try cleanArticleContentLight(html)
        let document = try DOMUtils.parse(value)
        guard let body = document.body() else { return value }
        try removeConditionally(from: body, allowedVideoRegex: allowedVideoRegex)
        return try body.html()
    }

    static func replaceBRS(_ html: String) -> String {
        let separator = #/(?i)(?:<br\s*/?>(?:\s|&nbsp;?)*){2,}/#
        guard html.firstMatch(of: separator) != nil else { return html }

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
            let parts = splitOnRegex(inner, separator: separator)
                .map { $0.trimmed() }
                .filter { !$0.isEmpty }
            if parts.count > 1 {
                return opening + parts.map { "<p>\($0)</p>" }.joined(separator: "\n") + closing
            }
        }

        return splitOnRegex(html, separator: separator)
            .map { $0.trimmed() }
            .filter { !$0.isEmpty }
            .map { "<p>\($0)</p>" }
            .joined(separator: "\n")
    }

    private static func splitOnRegex(_ value: String, separator: Regex<Substring>) -> [String] {
        value.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
    }

    private static func removeNavigationSections(from root: Element) throws {
        let selectors = [
            "nav", "[role=navigation]", ".navbar", ".breadcrumbs", ".sidebar",
            "div[class*=sidebar],section[class*=sidebar],ul[class*=sidebar],ol[class*=sidebar]",
            "div[id*=navbar],section[id*=navbar],ul[id*=navbar],ol[id*=navbar]",
            "div[id*=menu],section[id*=menu],ul[id*=menu],ol[id*=menu]",
            "div[id*=breadcrumbs],section[id*=breadcrumbs],ul[id*=breadcrumbs],ol[id*=breadcrumbs]",
            "div[id*=sidebar],section[id*=sidebar],ul[id*=sidebar],ol[id*=sidebar]"
        ]
        for selector in selectors {
            for element in try root.select(selector) {
                guard try shouldRemoveNavigationElement(element) else { continue }
                try element.remove()
            }
        }
    }

    private static func shouldRemoveNavigationElement(_ element: Element) throws -> Bool {
        let textLength = DOMUtils.getInnerText(element, normalizeSpaces: false).utf8.count
        let paragraphCount = try element.select("p").count
        if textLength > 600 && paragraphCount > 0 { return false }
        if textLength < 400 { return true }
        return try DOMUtils.linkDensity(element) > 0.55
    }

    private static func removeConditionally(
        from root: Element,
        allowedVideoRegex: Regex<Substring>?
    ) throws {
        // readabilityrs stores ego_tree NodeIds for data-table membership.
        // ObjectIdentifier is the SwiftSoup reference-identity equivalent; the
        // set must never be reused after reparsing the HTML into another tree.
        let dataTables = Set(try (try root.select("table"))
            .filter { try isDataTable($0) }
            .map(ObjectIdentifier.init))
        for tag in ["form", "fieldset", "table", "ul", "ol", "div", "section"] {
            let elements = try root.select(tag)
            // readabilityrs first collects every NodeId to detach for a tag,
            // then mutates the tree. Removing while evaluating would change a
            // later ancestor's text/count metrics in SwiftSoup.
            let removals = try elements.filter { element in
                if tag == "form" || tag == "fieldset" { return true }
                return try shouldRemove(
                        element,
                        tag: tag,
                        dataTables: dataTables,
                        allowedVideoRegex: allowedVideoRegex
                    )
            }
            for element in removals {
                try element.remove()
            }
        }
    }

    private static func shouldRemove(
        _ element: Element,
        tag: String,
        dataTables: Set<ObjectIdentifier>,
        allowedVideoRegex: Regex<Substring>?
    ) throws -> Bool {
        let classID = DOMUtils.classAndID(element).lowercased()
        if ["comment", "disqus", "remark", "replies", "respond"].contains(where: classID.contains) { return true }

        let text = DOMUtils.getInnerText(element, normalizeSpaces: false)
        let trimmedText = text.trimmed()
        // readabilityrs's cleaner measures Rust String byte lengths and counts
        // every link at full weight here. This intentionally differs from the
        // extraction scorer, which discounts hash-only navigation links.
        let contentLength = trimmedText.utf8.count
        if contentLength > 600 { return false }

        let isListTag = tag == "ul" || tag == "ol"
        let isList: Bool
        if isListTag {
            isList = true
        } else {
            isList = try isMostlyList(element, contentLength: contentLength)
        }
        let tableIsData = dataTables.contains(ObjectIdentifier(element))
        if tag == "table" && tableIsData { return false }
        if DOMUtils.ancestors(element, limit: 0).contains(where: { dataTables.contains(ObjectIdentifier($0)) }) { return false }
        if DOMUtils.ancestors(element, limit: 0).contains(where: { $0.tagName().lowercased() == "code" }) { return false }
        if try DOMUtils.descendants(element).contains(where: { dataTables.contains(ObjectIdentifier($0)) }) { return false }

        let linkDensity = try cleanerLinkDensity(element, contentLength: contentLength)
        let weight = try cleanerClassWeight(element)
        if weight < 0 && (linkDensity > 0.25 || contentLength < 100) { return true }
        if trimmedText.filter({ $0 == "," }).count >= 10 { return false }

        let paragraphCount = try element.select("p").count
        let imageCount = try element.select("img").count
        let listCount = max(0, try element.select("li").count - 100)
        let inputCount = try element.select("input").count
        let headingDensity = try textDensity(element, selector: "h1,h2,h3,h4,h5,h6")
        let embeds = try element.select("object,embed,iframe")
        if embeds.contains(where: { nodeHasAllowedVideo($0, allowedVideoRegex: allowedVideoRegex) }) { return false }
        if matches(text, Constants.adWords) || matches(text, Constants.loadingWords) { return true }
        let textDensityValue = try textDensity(element, selector: "span,li,td,blockquote,dl,div,img,ol,p,pre,table,ul")
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

    private static func isMostlyList(_ element: Element, contentLength: Int) throws -> Bool {
        guard contentLength > 0 else { return false }
        let lists = try element.select("ul,ol")
        // readabilityrs uses untrimmed ElementRef::text() for descendant
        // lists, divided by the parent's trimmed content length. SwiftSoup's
        // text helpers discard formatting-only boundary nodes, so measure the
        // serialized list text here to retain the same whitespace signal.
        let listText = try lists
            .reduce(0) { try $0 + serializedCleanerText($1).utf8.count }
        return Double(listText) / Double(max(contentLength, 1)) > 0.9
    }

    private static func cleanerLinkDensity(_ element: Element, contentLength: Int) throws -> Double {
        guard contentLength > 0 else { return 1 }
        let linkLength = try (try element.select("a")).reduce(0) {
            try $0 + serializedCleanerText($1).utf8.count
        }
        return Double(linkLength) / Double(contentLength)
    }

    private static func serializedCleanerText(_ element: Element) throws -> String {
        let html = try element.html()
        let withoutMarkup = html.replacing(#/(?s)<!--.*?-->|<[^>]*>/#, with: "")
        return Utils.unescapeHTMLEntities(withoutMarkup)
    }

    private static func cleanerClassWeight(_ element: Element) throws -> Int {
        var weight = 0
        for attribute in ["class", "id"] {
            let value = try element.attr(attribute)
            if matches(value, Constants.negative) { weight -= 25 }
            if matches(value, Constants.positive) { weight += 25 }
        }
        return weight
    }

    private static func textDensity(_ element: Element, selector: String) throws -> Double {
        let total = DOMUtils.getInnerText(element, normalizeSpaces: false).utf8.count
        guard total > 0 else { return 0 }
        let childText = (try element.select(selector))
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
                return matches(value, Constants.videos)
                    || allowedVideoRegex.map { regex in value.firstMatch(of: regex) != nil } == true
            }) { return true }
        }
        guard element.tagName().lowercased() == "object" else { return false }
        let content = DOMUtils.textContent(element)
        return matches(content, Constants.videos)
            || allowedVideoRegex.map { content.firstMatch(of: $0) != nil } == true
    }

    private static func matches(_ value: String, _ regex: Regex<Substring>) -> Bool {
        value.firstMatch(of: regex) != nil
    }

    private static func isDataTable(_ element: Element) throws -> Bool {
        let hasHeader = !(try element.select("thead, th, caption, col, colgroup, tfoot")).isEmpty()
        let rows = try element.select("tr")
        let columns = rows.first.map { $0.children().count } ?? 0
        return hasHeader || (rows.count >= 2 && columns >= 2)
    }

}
