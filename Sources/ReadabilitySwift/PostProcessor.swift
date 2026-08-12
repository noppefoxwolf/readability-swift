import SwiftSoup

enum PostProcessor {
    static func prepArticle(
        _ html: String,
        cleanStyles: Bool,
        cleanWhitespace: Bool,
        keepClasses: Bool = false,
        classesToPreserve: [String] = ["page"]
    ) -> String {
        var result = cleanStyles ? removingPresentationAttributes(from: html) : html
        result = removingUnwantedElements(from: result)
        result = removingShareElements(from: result)
        result = removingNavigationElements(from: result)
        if cleanWhitespace {
            result = removingEmptyParagraphs(from: result)
            // A whole-string replacement would also collapse significant code
            // whitespace. readabilityrs protects these serialized spans with a
            // byte scanner; Preformatted is its String.Index-based Swift port.
            result = Preformatted.mapOutside(result) { fragment in
                SwiftRegex.replacing(
                    in: SwiftRegex.replacing(in: fragment, pattern: "\\n{3,}", with: "\n\n"),
                    pattern: "[ ]{2,}",
                    with: " "
                )
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

    private static func removingPresentationAttributes(from html: String) -> String {
        let patterns = [
            #"(?i)\s+style\s*=\s*"[^"]*""#,
            #"(?i)\s+style\s*=\s*'[^']*'"#,
            #"(?i)\s+align\s*=\s*["'][^"']*["']"#,
            #"(?i)\s+bgcolor\s*=\s*["'][^"']*["']"#,
            #"(?i)\s+valign\s*=\s*["'][^"']*["']"#,
        ]
        return patterns.reduce(html) { result, pattern in
            SwiftRegex.replacing(in: result, pattern: pattern, with: "")
        }
    }

    private static func removingUnwantedElements(from html: String) -> String {
        var result = html
        for tag in ["form", "fieldset", "footer", "aside", "object", "iframe", "textarea", "select", "button"] {
            result = removingElements(from: result, tag: tag, removesOpeningTagWithoutClosingTag: false)
        }
        for tag in ["embed", "input", "link"] {
            result = removingElements(from: result, tag: tag, removesOpeningTagWithoutClosingTag: true)
        }
        return result
    }

    private static func removingShareElements(from html: String) -> String {
        removingWrappers(
            from: html,
            tags: ["div", "span", "aside", "section"],
            keywords: ["share", "social", "sharedaddy"]
        )
    }

    private static func removingNavigationElements(from html: String) -> String {
        let withoutNav = removingElements(
            from: html,
            tag: "nav",
            removesOpeningTagWithoutClosingTag: false
        )
        return removingWrappers(
            from: withoutNav,
            tags: ["div", "section", "ul", "ol"],
            keywords: ["nav", "navbar", "menu", "breadcrumbs"]
        )
    }

    private static func removingWrappers(from html: String, tags: [String], keywords: [String]) -> String {
        var result = html
        // This deliberately follows readabilityrs's serialized-HTML regexes.
        // A DOM removal would delete an entire nested wrapper, while the Rust
        // implementation stops at the first matching closing tag.
        for tag in tags {
            for keyword in keywords {
                for attribute in ["class", "id"] {
                    result = removingWrapper(
                        from: result,
                        tag: tag,
                        attribute: attribute,
                        containing: keyword
                    )
                }
            }
        }
        return result
    }

    private static func removingWrapper(
        from html: String,
        tag: String,
        attribute: String,
        containing keyword: String
    ) -> String {
        var result = html
        let openingNeedle = "<\(tag)"
        let closingNeedle = "</\(tag)>"
        var searchStart = result.startIndex

        while searchStart < result.endIndex {
            guard let openingRange = result.firstRange(
                of: openingNeedle,
                caseInsensitive: true,
                in: searchStart..<result.endIndex
            ) else { break }
            let boundary = openingRange.upperBound
            guard boundary == result.endIndex || !isRegexWordCharacter(result[boundary]) else {
                searchStart = boundary
                continue
            }
            guard let openingEnd = result.firstRange(of: ">", in: boundary..<result.endIndex) else { break }
            let openingTag = result[openingRange.lowerBound..<openingEnd.upperBound].lowercased()
            let attributePrefix = "\(attribute.lowercased())=\""
            guard let attributeRange = openingTag.firstRange(of: attributePrefix) else {
                searchStart = boundary
                continue
            }
            let valueStart = attributeRange.upperBound
            guard let valueEnd = openingTag[valueStart...].firstIndex(of: "\"") else {
                searchStart = boundary
                continue
            }
            guard openingTag[valueStart..<valueEnd].contains(keyword.lowercased()) else {
                searchStart = boundary
                continue
            }
            guard let closingRange = result.firstRange(
                of: closingNeedle,
                caseInsensitive: true,
                in: openingEnd.upperBound..<result.endIndex
            ) else { break }
            result.removeSubrange(openingRange.lowerBound..<closingRange.upperBound)
            searchStart = result.startIndex
        }
        return result
    }

    private static func isRegexWordCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    private static func removingElements(
        from html: String,
        tag: String,
        removesOpeningTagWithoutClosingTag: Bool
    ) -> String {
        var result = html
        let openingNeedle = "<\(tag)"
        let closingNeedle = "</\(tag)>"
        var searchStart = result.startIndex

        while searchStart < result.endIndex {
            guard let openingRange = result.firstRange(
                of: openingNeedle,
                caseInsensitive: true,
                in: searchStart..<result.endIndex
            ) else { break }
            let boundary = openingRange.upperBound
            guard boundary == result.endIndex || !isRegexWordCharacter(result[boundary]) else {
                searchStart = boundary
                continue
            }
            guard let openingEnd = result.firstRange(of: ">", in: boundary..<result.endIndex) else { break }
            if let closingRange = result.firstRange(
                of: closingNeedle,
                caseInsensitive: true,
                in: openingEnd.upperBound..<result.endIndex
            ) {
                result.removeSubrange(openingRange.lowerBound..<closingRange.upperBound)
                searchStart = result.startIndex
            } else if removesOpeningTagWithoutClosingTag {
                result.removeSubrange(openingRange.lowerBound..<openingEnd.upperBound)
                searchStart = result.startIndex
            } else {
                searchStart = openingEnd.upperBound
            }
        }
        return result
    }

    private static func removingEmptyParagraphs(from html: String) -> String {
        var result = html
        for _ in 0..<5 {
            let cleaned = removingEmptyParagraphPass(from: result)
            if cleaned == result { break }
            result = cleaned
        }
        return SwiftRegex.replacing(
            in: result,
            pattern: #"(</(?:p|div|h[1-6])>)\s*(?:<br\s*/?>[\s\n]*)+\s*(<(?:p|div|h[1-6]))"#,
            with: "$1\n$2",
            caseInsensitive: true
        )
    }

    private static func removingEmptyParagraphPass(from html: String) -> String {
        var result = html
        var searchStart = result.startIndex
        while searchStart < result.endIndex {
            guard let openingRange = result.firstRange(
                of: "<p",
                caseInsensitive: true,
                in: searchStart..<result.endIndex
            ) else { break }
            let boundary = openingRange.upperBound
            guard boundary == result.endIndex || !isRegexWordCharacter(result[boundary]) else {
                searchStart = boundary
                continue
            }
            guard let openingEnd = result.firstRange(of: ">", in: boundary..<result.endIndex),
                  let closingRange = result.firstRange(
                    of: "</p>",
                    caseInsensitive: true,
                    in: openingEnd.upperBound..<result.endIndex
                  ) else { break }
            let content = String(result[openingEnd.upperBound..<closingRange.lowerBound])
            if paragraphContentIsEmpty(content) {
                result.removeSubrange(openingRange.lowerBound..<closingRange.upperBound)
                searchStart = result.startIndex
            } else {
                searchStart = closingRange.upperBound
            }
        }
        return result
    }

    private static func paragraphContentIsEmpty(_ content: String) -> Bool {
        let trimmed = content.trimmed()
        if trimmed.isEmpty || removingBreakTags(from: trimmed).isEmpty { return true }
        guard trimmed.firstRange(of: "<span", caseInsensitive: true)?.lowerBound == trimmed.startIndex,
              let openingEnd = trimmed.firstIndex(of: ">"),
              let closingRange = trimmed.lastRange(of: "</span>", caseInsensitive: true),
              closingRange.upperBound == trimmed.endIndex else { return false }
        let spanContent = String(trimmed[trimmed.index(after: openingEnd)..<closingRange.lowerBound])
        return removingBreakTags(from: spanContent).isEmpty
    }

    private static func removingBreakTags(from content: String) -> String {
        SwiftRegex.replacing(in: content, pattern: #"<br\s*/?>"#, with: "", caseInsensitive: true)
            .trimmed()
    }
}
