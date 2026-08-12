import SwiftSoup

enum MarkdownConverter {
    static func htmlToMarkdown(_ html: String, options: MarkdownOptions, title: String? = nil) -> String {
        let standardized = Elements.standardizeAll(html, title: title)
        // readabilityrs traverses scraper's synthetic fragment root. SwiftSoup
        // parseFragment returns a node array rather than a common Element, so a
        // document body is used as the equivalent conversion root.
        guard let document = try? SwiftSoup.parse(standardized) else {
            return SwiftRegex.replacing(in: standardized, pattern: "(?is)<[^>]+>", with: "")
        }
        document.outputSettings().prettyPrint(pretty: false)
        guard let body = document.body() else { return "" }
        var state = MarkdownConversionState()
        let rendered = renderChildren(of: body, options: options, state: &state)
        var output = normalizeOutput(rendered)
        if options.linkStyle == .reference, !state.linkReferences.isEmpty {
            output += "\n\n" + state.linkReferences.map { "[\($0.0)]: \($0.1)" }.joined(separator: "\n")
        }
        if !state.footnotes.isEmpty {
            output += MarkdownFootnoteRules.definitions(state.footnotes)
        }
        return output.trimmed()
    }

    private static func renderChildren(of element: Element, options: MarkdownOptions, state: inout MarkdownConversionState) -> String {
        element.getChildNodes().map { render($0, options: options, state: &state) }.joined()
    }

    private static func render(_ node: Node, options: MarkdownOptions, state: inout MarkdownConversionState) -> String {
        if let text = node as? TextNode {
            // Element.text() would normalize this before the converter can
            // distinguish normal flow from a code block. scraper exposes raw
            // Node::Text, whose SwiftSoup counterpart is getWholeText().
            return state.inCodeBlock ? text.getWholeText() : MarkdownTextRules.escape(SwiftRegex.replacing(in: text.getWholeText(), pattern: "\\s+", with: " "))
        }
        guard let element = node as? Element else { return "" }
        let tag = element.tagName().lowercased()
        if ["script", "style", "template", "noscript"].contains(tag) { return "" }
        if tag == "pre" {
            let code = rawText(element)
                .replacing("\r\n", with: "\n")
                .replacing("\r", with: "\n")
            let language = languageForCodeBlock(element)
            return MarkdownCodeRules.codeBlock(code.trimmed(), language: language, options: options)
        }
        if tag == "code" { return MarkdownTextRules.inlineCode(rawText(element)) }
        if tag == "br" { return state.inHeading ? " " : "  \n" }
        if tag == "img" {
            let src = (try? element.attr("src")) ?? ""
            let alt = (try? element.attr("alt")) ?? ""
            let title = (try? element.attr("title")) ?? ""
            return MarkdownImageRules.image(alt: alt, source: src, title: title, options: options)
        }
        if tag == "math" {
            let latex = (try? element.attr("data-latex")) ?? renderChildren(of: element, options: options, state: &state)
            let display = ((try? element.attr("display")) ?? "").lowercased()
            return MarkdownMathRules.math(latex: latex, display: display)
        }
        if tag == "video" || tag == "audio" {
            let directSource = (try? element.attr("src")) ?? ""
            let nestedSource = (try? element.select("source[src]").first()?.attr("src")) ?? ""
            let source = directSource.isEmpty ? nestedSource : directSource
            let label = tag == "video" ? "Video" : "Audio"
            let media = MarkdownMediaRules.media(label: label, source: source, options: options)
            return media.isEmpty ? renderChildren(of: element, options: options, state: &state) : "\n\n\(media)\n\n"
        }
        if tag == "iframe" {
            let source = (try? element.attr("src")) ?? ""
            guard !source.isEmpty else { return "" }
            return "\n\n\(MarkdownMediaRules.iframe(source, options: options))\n\n"
        }
        if tag == "input" {
            let type = ((try? element.attr("type")) ?? "").lowercased()
            if type == "checkbox" { return element.hasAttr("checked") ? "[x] " : "[ ] " }
            return ""
        }
        if tag == "a" {
            if state.inLink { return renderChildren(of: element, options: options, state: &state) }
            let href = (try? element.attr("href")) ?? ""
            if href.lowercased().hasPrefix("#fn:") || href.lowercased().hasPrefix("#fn-") || href.lowercased().hasPrefix("#footnote") {
                let reference = ((try? element.text()) ?? "").trimmed()
                let id = reference.isEmpty ? href.split(separator: ":").last.map(String.init) ?? "1" : reference
                return MarkdownFootnoteRules.reference(id)
            }
            state.inLink = true
            let value = renderChildren(of: element, options: options, state: &state)
            state.inLink = false
            let title = (try? element.attr("title")) ?? ""
            return MarkdownLinkRules.link(inner: value, href: href, title: title, options: options, state: &state)
        }
        if tag == "strong" || tag == "b" {
            let value = renderChildren(of: element, options: options, state: &state).trimmed()
            return value.isEmpty ? "" : options.strongDelimiter + value + options.strongDelimiter
        }
        if tag == "em" || tag == "i" {
            let value = renderChildren(of: element, options: options, state: &state).trimmed()
            return value.isEmpty ? "" : String(options.emphasisDelimiter) + value + String(options.emphasisDelimiter)
        }
        if tag == "del" || tag == "s" || tag == "strike" {
            let value = renderChildren(of: element, options: options, state: &state).trimmed()
            return value.isEmpty ? "" : "~~\(value)~~"
        }
        if tag == "mark" {
            let value = renderChildren(of: element, options: options, state: &state).trimmed()
            return value.isEmpty ? "" : "==\(value)=="
        }
        if tag == "sup" {
            let id = ((try? element.attr("id")) ?? "").lowercased()
            if id.hasPrefix("fnref:") || id.hasPrefix("fnref-") {
                let number = id.replacing("fnref:", with: "").replacing("fnref-", with: "")
                return "[^\(number)]"
            }
            let value = renderChildren(of: element, options: options, state: &state).trimmed()
            return value.isEmpty ? "" : "^\(value)^"
        }
        if tag == "sub" {
            let value = renderChildren(of: element, options: options, state: &state).trimmed()
            return value.isEmpty ? "" : "~\(value)~"
        }
        if tag == "hr" { return "\n\n---\n\n" }
        if tag == "figure" {
            if let image = try? element.select("img").first() {
                let source = (try? image.attr("src")) ?? ""
                let alt = (try? image.attr("alt")) ?? ""
                let caption = (try? element.select("figcaption").first()?.text()) ?? ""
                if !source.isEmpty { return MarkdownImageRules.figure(alt: alt, source: source, caption: caption, options: options) }
            }
            return renderChildren(of: element, options: options, state: &state)
        }
        if tag == "ul" || tag == "ol" { return renderList(element, ordered: tag == "ol", options: options, state: &state) }
        if tag == "table" { return renderTable(element, options: options, state: &state) }
        if tag == "li" { return renderChildren(of: element, options: options, state: &state) }
        if tag == "blockquote" {
            state.blockquoteDepth += 1
            let inner = renderChildren(of: element, options: options, state: &state)
            let depth = state.blockquoteDepth
            state.blockquoteDepth -= 1
            return MarkdownBlockquoteRules.render(inner, depth: depth, callout: try? element.attr("data-callout"))
        }

        let inner: String
        if tag.first == "h", Int(tag.dropFirst()).map({ (1...6).contains($0) }) == true {
            state.inHeading = true
            inner = renderChildren(of: element, options: options, state: &state)
            state.inHeading = false
        } else {
            inner = renderChildren(of: element, options: options, state: &state)
        }
        if let level = Int(tag.dropFirst()), tag.first == "h", (1...6).contains(level) {
            return MarkdownHeadingRules.heading(level: level, inner: inner, options: options)
        }
        if tag == "div" {
            let id = ((try? element.attr("id")) ?? "").lowercased()
            let className = ((try? element.attr("class")) ?? "").lowercased()
            if id == "footnotes" || className.split(separator: " ").contains("footnotes") {
                collectFootnotes(from: element, state: &state)
                return ""
            }
        }
        if tag == "details" {
            // scraper ElementRef::html() serializes the selected element;
            // SwiftSoup Element.html() serializes only its children.
            return "\n\n\((try? element.outerHtml()) ?? "")\n\n"
        }
        if tag == "dt" { return "\n\n**\(inner.trimmed())**\n" }
        if tag == "dd" { return ": \(inner.trimmed())\n" }
        if ["p", "div", "section", "article", "main", "tr", "td", "th"].contains(tag) {
            let value = inner.trimmed()
            if value.isEmpty { return "" }
            return state.inListItem || state.inTable ? "\(value)\n" : "\n\n\(inner)\n\n"
        }
        return inner
    }

    private static func rawText(_ element: Element) -> String {
        element.getChildNodes().reduce(into: "") { result, node in
            if let text = node as? TextNode { result += text.getWholeText() }
            else if let child = node as? Element { result += rawText(child) }
        }
    }

    private static func renderList(_ element: Element, ordered: Bool, options: MarkdownOptions, state: inout MarkdownConversionState) -> String {
        state.listDepth += 1
        if ordered { state.orderedListCounters.append(0) }
        let items = element.children().filter { $0.tagName().lowercased() == "li" }
        let output = items.map { renderListItem($0, ordered: ordered, options: options, state: &state) }.joined()
        if ordered { state.orderedListCounters.removeLast() }
        state.listDepth -= 1
        return state.listDepth == 0 ? "\n\n\(output.trimmed())\n" : "\n\(output)"
    }

    private static func renderListItem(_ element: Element, ordered: Bool, options: MarkdownOptions, state: inout MarkdownConversionState) -> String {
        let previous = state.inListItem
        state.inListItem = true
        defer { state.inListItem = previous }

        if let checkbox = try? element.select("input[type=checkbox]").first() {
            let checked = checkbox.hasAttr("checked")
            let inner = renderChildrenSkippingCheckbox(of: element, options: options, state: &state)
            return MarkdownListRules.task(inner, checked: checked, options: options, state: state)
        }

        let inner = renderChildren(of: element, options: options, state: &state)
        guard !inner.trimmed().isEmpty else {
            if ordered, !state.orderedListCounters.isEmpty { state.orderedListCounters[state.orderedListCounters.count - 1] += 1 }
            return ""
        }
        if ordered {
            state.orderedListCounters[state.orderedListCounters.count - 1] += 1
            return MarkdownListRules.ordered(inner, counter: state.orderedListCounters.last ?? 1, state: state)
        }
        return MarkdownListRules.unordered(inner, options: options, state: state)
    }

    private static func renderChildrenSkippingCheckbox(of element: Element, options: MarkdownOptions, state: inout MarkdownConversionState) -> String {
        var skipped = false
        return element.getChildNodes().map { node -> String in
            if let child = node as? Element, !skipped,
               child.tagName().lowercased() == "input",
               ((try? child.attr("type")) ?? "").lowercased() == "checkbox" {
                skipped = true
                return ""
            }
            return render(node, options: options, state: &state)
        }.joined()
    }

    private static func collectFootnotes(from element: Element, state: inout MarkdownConversionState) {
        for item in (try? element.select("li.footnote, li[id^=fn]")) ?? SwiftSoup.Elements() {
            let rawID = ((try? item.attr("id")) ?? "")
                .replacing("fn:", with: "")
                .replacing("fn-", with: "")
            guard !rawID.isEmpty else { continue }
            let content = MarkdownTextRules.escapeLinkText(
                DOMUtils.normalizeWhitespace(DOMUtils.textContent(item).replacing("↩", with: ""))
            )
            if !content.isEmpty { state.footnotes.append((rawID, content)) }
        }
    }

    private static func languageForCodeBlock(_ element: Element) -> String {
        let elementClass = (try? element.attr("class")) ?? ""
        if let token = elementClass.split(whereSeparator: { $0.isWhitespace }).first(where: { $0.hasPrefix("language-") }) {
            return String(token.dropFirst(9))
        }
        guard let code = try? element.select("code").first() else { return "" }
        let dataLanguage = (try? code.attr("data-lang")) ?? ""
        if !dataLanguage.isEmpty { return dataLanguage }
        let codeClass = (try? code.attr("class")) ?? ""
        return codeClass.split(whereSeparator: { $0.isWhitespace }).first(where: { $0.hasPrefix("language-") }).map { String($0.dropFirst(9)) } ?? ""
    }

    private static func renderTable(_ element: Element, options: MarkdownOptions, state: inout MarkdownConversionState) -> String {
        if options.preserveComplexTables && MarkdownTableRules.isComplex(element) {
            return "\n\n\(complexTableHTML(element))\n\n"
        }
        if MarkdownTableRules.isLayout(element) { return renderChildren(of: element, options: options, state: &state) }
        let rows = element.children().filter { $0.tagName().lowercased() == "tr" || $0.tagName().lowercased() == "thead" || $0.tagName().lowercased() == "tbody" }
            .flatMap { row in row.tagName().lowercased() == "tr" ? [row] : row.children().filter { $0.tagName().lowercased() == "tr" } }
        let values = rows.map { row in
            row.children().filter { ["td", "th"].contains($0.tagName().lowercased()) }.map { renderChildren(of: $0, options: options, state: &state).trimmed() }
        }.filter { !$0.isEmpty }
        guard let first = values.first, !first.isEmpty else { return "" }
        let hasHeader = !((try? element.select("th")) ?? SwiftSoup.Elements()).isEmpty()
        if hasHeader {
            return MarkdownTableRules.simple(headers: first, rows: Array(values.dropFirst()))
        }
        return MarkdownTableRules.simple(headers: Array(repeating: "", count: first.count), rows: values)
    }

    private static func complexTableHTML(_ element: Element) -> String {
        let html = (try? element.outerHtml()) ?? ""
        // html5ever inserts an implicit tbody around direct tr children during
        // tree construction. SwiftSoup may retain direct rows, so add the
        // wrapper required by readabilityrs's raw complex-table output.
        guard html.firstRange(of: "<tbody", caseInsensitive: true) == nil,
              html.firstRange(of: "<tr", caseInsensitive: true) != nil,
              let openingEnd = html.firstIndex(of: ">"),
              let closingStart = html.lastRange(of: "</table>", caseInsensitive: true)?.lowerBound else {
            return html
        }
        let contentStart = html.index(after: openingEnd)
        return String(html[...openingEnd]) + "<tbody>" + html[contentStart..<closingStart] + "</tbody></table>"
    }

    private static func normalizeOutput(_ value: String) -> String {
        SwiftRegex.replacing(
            in: SwiftRegex.replacing(in: value, pattern: "[ \\t]+\\n", with: "\n"),
            pattern: "\\n{3,}",
            with: "\n\n"
        ).trimmed()
    }
}
