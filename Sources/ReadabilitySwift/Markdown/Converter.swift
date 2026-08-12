import SwiftSoup

enum MarkdownConverter {
    static func htmlToMarkdown(_ html: String, options: MarkdownOptions, title: String? = nil) throws -> String {
        let standardized = try Elements.standardizeAll(html, title: title)
        // readabilityrs traverses scraper's synthetic fragment root. SwiftSoup
        // parseFragment returns a node array rather than a common Element, so a
        // document body is used as the equivalent conversion root.
        let document = try SwiftSoup.parse(standardized)
        document.outputSettings().prettyPrint(pretty: false)
        guard let body = document.body() else { return "" }
        var state = MarkdownConversionState()
        let rendered = try renderChildren(of: body, options: options, state: &state)
        var output = normalizeOutput(rendered)
        if options.linkStyle == .reference, !state.linkReferences.isEmpty {
            output += "\n\n" + state.linkReferences.map { "[\($0.0)]: \($0.1)" }.joined(separator: "\n")
        }
        if !state.footnotes.isEmpty {
            output += MarkdownFootnoteRules.definitions(state.footnotes)
        }
        return output.trimmed()
    }

    private static func renderChildren(of element: Element, options: MarkdownOptions, state: inout MarkdownConversionState) throws -> String {
        try element.getChildNodes().map { try render($0, options: options, state: &state) }.joined()
    }

    private static func render(_ node: Node, options: MarkdownOptions, state: inout MarkdownConversionState) throws -> String {
        if let text = node as? TextNode {
            // Element.text() would normalize this before the converter can
            // distinguish normal flow from a code block. scraper exposes raw
            // Node::Text, whose SwiftSoup counterpart is getWholeText().
            return state.inCodeBlock ? text.getWholeText() : MarkdownTextRules.escape(text.getWholeText().replacing(/\s+/, with: " "))
        }
        guard let element = node as? Element else { return "" }
        let tag = element.tagName().lowercased()
        if ["script", "style", "template", "noscript"].contains(tag) { return "" }
        if tag == "pre" {
            let code = DOMUtils.textContent(element)
                .replacing("\r\n", with: "\n")
                .replacing("\r", with: "\n")
            let language = try languageForCodeBlock(element)
            return MarkdownCodeRules.codeBlock(code.trimmed(), language: language, options: options)
        }
        if tag == "code" { return MarkdownTextRules.inlineCode(DOMUtils.textContent(element)) }
        if tag == "br" { return state.inHeading ? " " : "  \n" }
        if tag == "img" {
            let src = DOMUtils.attribute("src", of: element)
            let alt = DOMUtils.attribute("alt", of: element)
            let title = DOMUtils.attribute("title", of: element)
            return MarkdownImageRules.image(alt: alt, source: src, title: title, options: options)
        }
        if tag == "math" {
            let latexAttribute = DOMUtils.attribute("data-latex", of: element)
            let latex = latexAttribute.isEmpty ? try renderChildren(of: element, options: options, state: &state) : latexAttribute
            let display = DOMUtils.attribute("display", of: element).lowercased()
            return MarkdownMathRules.math(latex: latex, display: display)
        }
        if tag == "video" || tag == "audio" {
            let directSource = DOMUtils.attribute("src", of: element)
            let nestedSource = try element.select("source[src]").first().map { DOMUtils.attribute("src", of: $0) } ?? ""
            let source = directSource.isEmpty ? nestedSource : directSource
            let label = tag == "video" ? "Video" : "Audio"
            let media = MarkdownMediaRules.media(label: label, source: source, options: options)
            return media.isEmpty ? try renderChildren(of: element, options: options, state: &state) : "\n\n\(media)\n\n"
        }
        if tag == "iframe" {
            let source = DOMUtils.attribute("src", of: element)
            guard !source.isEmpty else { return "" }
            return "\n\n\(MarkdownMediaRules.iframe(source, options: options))\n\n"
        }
        if tag == "input" {
            let type = DOMUtils.attribute("type", of: element).lowercased()
            if type == "checkbox" { return element.hasAttr("checked") ? "[x] " : "[ ] " }
            return ""
        }
        if tag == "a" {
            if state.inLink { return try renderChildren(of: element, options: options, state: &state) }
            let href = DOMUtils.attribute("href", of: element)
            if href.lowercased().hasPrefix("#fn:") || href.lowercased().hasPrefix("#fn-") || href.lowercased().hasPrefix("#footnote") {
                let reference = DOMUtils.textContent(element).trimmed()
                let id = reference.isEmpty ? href.split(separator: ":").last.map(String.init) ?? "1" : reference
                return MarkdownFootnoteRules.reference(id)
            }
            state.inLink = true
            let value = try renderChildren(of: element, options: options, state: &state)
            state.inLink = false
            let title = DOMUtils.attribute("title", of: element)
            return MarkdownLinkRules.link(inner: value, href: href, title: title, options: options, state: &state)
        }
        if tag == "strong" || tag == "b" {
            let value = try renderChildren(of: element, options: options, state: &state).trimmed()
            return value.isEmpty ? "" : options.strongDelimiter + value + options.strongDelimiter
        }
        if tag == "em" || tag == "i" {
            let value = try renderChildren(of: element, options: options, state: &state).trimmed()
            return value.isEmpty ? "" : String(options.emphasisDelimiter) + value + String(options.emphasisDelimiter)
        }
        if tag == "del" || tag == "s" || tag == "strike" {
            let value = try renderChildren(of: element, options: options, state: &state).trimmed()
            return value.isEmpty ? "" : "~~\(value)~~"
        }
        if tag == "mark" {
            let value = try renderChildren(of: element, options: options, state: &state).trimmed()
            return value.isEmpty ? "" : "==\(value)=="
        }
        if tag == "sup" {
            let id = DOMUtils.attribute("id", of: element).lowercased()
            if id.hasPrefix("fnref:") || id.hasPrefix("fnref-") {
                let number = id.replacing("fnref:", with: "").replacing("fnref-", with: "")
                return "[^\(number)]"
            }
            let value = try renderChildren(of: element, options: options, state: &state).trimmed()
            return value.isEmpty ? "" : "^\(value)^"
        }
        if tag == "sub" {
            let value = try renderChildren(of: element, options: options, state: &state).trimmed()
            return value.isEmpty ? "" : "~\(value)~"
        }
        if tag == "hr" { return "\n\n---\n\n" }
        if tag == "figure" {
            if let image = try element.select("img").first() {
                let source = DOMUtils.attribute("src", of: image)
                let alt = DOMUtils.attribute("alt", of: image)
                let caption = try element.select("figcaption").first().map(DOMUtils.textContent) ?? ""
                if !source.isEmpty { return MarkdownImageRules.figure(alt: alt, source: source, caption: caption, options: options) }
            }
            return try renderChildren(of: element, options: options, state: &state)
        }
        if tag == "ul" || tag == "ol" { return try renderList(element, ordered: tag == "ol", options: options, state: &state) }
        if tag == "table" { return try renderTable(element, options: options, state: &state) }
        if tag == "li" { return try renderChildren(of: element, options: options, state: &state) }
        if tag == "blockquote" {
            state.blockquoteDepth += 1
            let inner = try renderChildren(of: element, options: options, state: &state)
            let depth = state.blockquoteDepth
            state.blockquoteDepth -= 1
            return MarkdownBlockquoteRules.render(inner, depth: depth, callout: DOMUtils.attribute("data-callout", of: element))
        }

        let inner: String
        if tag.first == "h", Int(tag.dropFirst()).map({ (1...6).contains($0) }) == true {
            state.inHeading = true
            inner = try renderChildren(of: element, options: options, state: &state)
            state.inHeading = false
        } else {
            inner = try renderChildren(of: element, options: options, state: &state)
        }
        if let level = Int(tag.dropFirst()), tag.first == "h", (1...6).contains(level) {
            return MarkdownHeadingRules.heading(level: level, inner: inner, options: options)
        }
        if tag == "div" {
            let id = DOMUtils.attribute("id", of: element).lowercased()
            let className = DOMUtils.attribute("class", of: element).lowercased()
            if id == "footnotes" || className.split(separator: " ").contains("footnotes") {
                try collectFootnotes(from: element, state: &state)
                return ""
            }
        }
        if tag == "details" {
            // scraper ElementRef::html() serializes the selected element;
            // SwiftSoup Element.html() serializes only its children.
            return "\n\n\(try element.outerHtml())\n\n"
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

    private static func renderList(_ element: Element, ordered: Bool, options: MarkdownOptions, state: inout MarkdownConversionState) throws -> String {
        state.listDepth += 1
        if ordered { state.orderedListCounters.append(0) }
        let items = element.children().filter { $0.tagName().lowercased() == "li" }
        let output = try items.map { try renderListItem($0, ordered: ordered, options: options, state: &state) }.joined()
        if ordered { state.orderedListCounters.removeLast() }
        state.listDepth -= 1
        return state.listDepth == 0 ? "\n\n\(output.trimmed())\n" : "\n\(output)"
    }

    private static func renderListItem(_ element: Element, ordered: Bool, options: MarkdownOptions, state: inout MarkdownConversionState) throws -> String {
        let previous = state.inListItem
        state.inListItem = true
        defer { state.inListItem = previous }

        if let checkbox = try element.select("input[type=checkbox]").first() {
            let checked = checkbox.hasAttr("checked")
            let inner = try renderChildrenSkippingCheckbox(of: element, options: options, state: &state)
            return MarkdownListRules.task(inner, checked: checked, options: options, state: state)
        }

        let inner = try renderChildren(of: element, options: options, state: &state)
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

    private static func renderChildrenSkippingCheckbox(of element: Element, options: MarkdownOptions, state: inout MarkdownConversionState) throws -> String {
        var skipped = false
        return try element.getChildNodes().map { node -> String in
            if let child = node as? Element, !skipped,
               child.tagName().lowercased() == "input",
               DOMUtils.attribute("type", of: child).lowercased() == "checkbox" {
                skipped = true
                return ""
            }
            return try render(node, options: options, state: &state)
        }.joined()
    }

    private static func collectFootnotes(from element: Element, state: inout MarkdownConversionState) throws {
        for item in try element.select("li.footnote, li[id^=fn]") {
            let rawID = DOMUtils.attribute("id", of: item)
                .replacing("fn:", with: "")
                .replacing("fn-", with: "")
            guard !rawID.isEmpty else { continue }
            let content = MarkdownTextRules.escapeLinkText(
                DOMUtils.normalizeWhitespace(DOMUtils.textContent(item).replacing("↩", with: ""))
            )
            if !content.isEmpty { state.footnotes.append((rawID, content)) }
        }
    }

    private static func languageForCodeBlock(_ element: Element) throws -> String {
        let elementClass = DOMUtils.attribute("class", of: element)
        if let token = elementClass.split(whereSeparator: { $0.isWhitespace }).first(where: { $0.hasPrefix("language-") }) {
            return String(token.dropFirst(9))
        }
        guard let code = try element.select("code").first() else { return "" }
        let dataLanguage = DOMUtils.attribute("data-lang", of: code)
        if !dataLanguage.isEmpty { return dataLanguage }
        let codeClass = DOMUtils.attribute("class", of: code)
        return codeClass.split(whereSeparator: { $0.isWhitespace }).first(where: { $0.hasPrefix("language-") }).map { String($0.dropFirst(9)) } ?? ""
    }

    private static func renderTable(_ element: Element, options: MarkdownOptions, state: inout MarkdownConversionState) throws -> String {
        let preservesComplexTable = options.preserveComplexTables ? try MarkdownTableRules.isComplex(element) : false
        if preservesComplexTable {
            return "\n\n\(try complexTableHTML(element))\n\n"
        }
        if try MarkdownTableRules.isLayout(element) { return try renderChildren(of: element, options: options, state: &state) }
        let rows = element.children().filter { $0.tagName().lowercased() == "tr" || $0.tagName().lowercased() == "thead" || $0.tagName().lowercased() == "tbody" }
            .flatMap { row in row.tagName().lowercased() == "tr" ? [row] : row.children().filter { $0.tagName().lowercased() == "tr" } }
        let values = try rows.map { row in
            try row.children().filter { ["td", "th"].contains($0.tagName().lowercased()) }.map { try renderChildren(of: $0, options: options, state: &state).trimmed() }
        }.filter { !$0.isEmpty }
        guard let first = values.first, !first.isEmpty else { return "" }
        let hasHeader = !(try element.select("th")).isEmpty()
        if hasHeader {
            return MarkdownTableRules.simple(headers: first, rows: Array(values.dropFirst()))
        }
        return MarkdownTableRules.simple(headers: Array(repeating: "", count: first.count), rows: values)
    }

    private static func complexTableHTML(_ element: Element) throws -> String {
        let html = try element.outerHtml()
        // html5ever inserts an implicit tbody around direct tr children during
        // tree construction. SwiftSoup may retain direct rows, so add the
        // wrapper required by readabilityrs's raw complex-table output.
        guard html.firstASCIICaseInsensitiveRange(of: "<tbody") == nil,
              html.firstASCIICaseInsensitiveRange(of: "<tr") != nil,
              let openingEnd = html.firstIndex(of: ">"),
              let closingStart = html.lastASCIICaseInsensitiveRange(of: "</table>")?.lowerBound else {
            return html
        }
        let contentStart = html.index(after: openingEnd)
        return String(html[...openingEnd]) + "<tbody>" + html[contentStart..<closingStart] + "</tbody></table>"
    }

    private static func normalizeOutput(_ value: String) -> String {
        value.replacing(/[ \t]+\n/, with: "\n")
            .replacing(/\n{3,}/, with: "\n\n")
            .trimmed()
    }
}
