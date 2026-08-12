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

    private static func removingPresentationAttributes(from html: String) -> String {
        let patterns = [
            #"(?i)\s+style\s*=\s*"[^"]*""#,
            #"(?i)\s+style\s*=\s*'[^']*'"#,
            #"(?i)\s+align\s*=\s*["'][^"']*["']"#,
            #"(?i)\s+bgcolor\s*=\s*["'][^"']*["']"#,
            #"(?i)\s+valign\s*=\s*["'][^"']*["']"#,
        ]
        return patterns.reduce(html) { result, pattern in
            result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
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
        let result = NSMutableString(string: html)
        let openingNeedle = "<\(tag)"
        let closingNeedle = "</\(tag)>"
        var searchLocation = 0

        while searchLocation < result.length {
            let searchRange = NSRange(location: searchLocation, length: result.length - searchLocation)
            let openingRange = result.range(of: openingNeedle, options: .caseInsensitive, range: searchRange)
            guard openingRange.location != NSNotFound else { break }
            let boundaryLocation = NSMaxRange(openingRange)
            guard boundaryLocation == result.length || !isRegexWordCodeUnit(result.character(at: boundaryLocation)) else {
                searchLocation = boundaryLocation
                continue
            }
            let openingEnd = result.range(
                of: ">",
                range: NSRange(location: boundaryLocation, length: result.length - boundaryLocation)
            )
            guard openingEnd.location != NSNotFound else { break }
            let openingTagRange = NSRange(
                location: openingRange.location,
                length: NSMaxRange(openingEnd) - openingRange.location
            )
            let openingTag = result.substring(with: openingTagRange).lowercased()
            let attributePrefix = "\(attribute.lowercased())=\""
            guard let attributeRange = openingTag.range(of: attributePrefix) else {
                searchLocation = boundaryLocation
                continue
            }
            let valueStart = attributeRange.upperBound
            guard let valueEnd = openingTag[valueStart...].firstIndex(of: "\"") else {
                searchLocation = boundaryLocation
                continue
            }
            guard openingTag[valueStart..<valueEnd].contains(keyword.lowercased()) else {
                searchLocation = boundaryLocation
                continue
            }
            let contentLocation = NSMaxRange(openingEnd)
            let closingRange = result.range(
                of: closingNeedle,
                options: .caseInsensitive,
                range: NSRange(location: contentLocation, length: result.length - contentLocation)
            )
            guard closingRange.location != NSNotFound else { break }
            result.deleteCharacters(
                in: NSRange(
                    location: openingRange.location,
                    length: NSMaxRange(closingRange) - openingRange.location
                )
            )
            searchLocation = openingRange.location
        }
        return String(result)
    }

    private static func isRegexWordCodeUnit(_ codeUnit: unichar) -> Bool {
        codeUnit == 95 || UnicodeScalar(codeUnit).map(CharacterSet.alphanumerics.contains) == true
    }

    private static func removingElements(
        from html: String,
        tag: String,
        removesOpeningTagWithoutClosingTag: Bool
    ) -> String {
        let result = NSMutableString(string: html)
        let openingNeedle = "<\(tag)"
        let closingNeedle = "</\(tag)>"
        var searchLocation = 0

        while searchLocation < result.length {
            let searchRange = NSRange(location: searchLocation, length: result.length - searchLocation)
            let openingRange = result.range(of: openingNeedle, options: .caseInsensitive, range: searchRange)
            guard openingRange.location != NSNotFound else { break }
            let boundaryLocation = NSMaxRange(openingRange)
            guard boundaryLocation == result.length || !isRegexWordCodeUnit(result.character(at: boundaryLocation)) else {
                searchLocation = boundaryLocation
                continue
            }
            let openingEnd = result.range(
                of: ">",
                range: NSRange(location: boundaryLocation, length: result.length - boundaryLocation)
            )
            guard openingEnd.location != NSNotFound else { break }
            let contentLocation = NSMaxRange(openingEnd)
            let closingRange = result.range(
                of: closingNeedle,
                options: .caseInsensitive,
                range: NSRange(location: contentLocation, length: result.length - contentLocation)
            )
            if closingRange.location != NSNotFound {
                result.deleteCharacters(
                    in: NSRange(
                        location: openingRange.location,
                        length: NSMaxRange(closingRange) - openingRange.location
                    )
                )
                searchLocation = openingRange.location
            } else if removesOpeningTagWithoutClosingTag {
                result.deleteCharacters(
                    in: NSRange(
                        location: openingRange.location,
                        length: NSMaxRange(openingEnd) - openingRange.location
                    )
                )
                searchLocation = openingRange.location
            } else {
                searchLocation = contentLocation
            }
        }
        return String(result)
    }

    private static func removingEmptyParagraphs(from html: String) -> String {
        var result = html
        for _ in 0..<5 {
            let cleaned = removingEmptyParagraphPass(from: result)
            if cleaned == result { break }
            result = cleaned
        }
        return result.replacingOccurrences(
            of: #"(?i)(</(?:p|div|h[1-6])>)\s*(?:<br\s*/?>[\s\n]*)+\s*(<(?:p|div|h[1-6]))"#,
            with: "$1\n$2",
            options: .regularExpression
        )
    }

    private static func removingEmptyParagraphPass(from html: String) -> String {
        let result = NSMutableString(string: html)
        var searchLocation = 0
        while searchLocation < result.length {
            let openingRange = result.range(
                of: "<p",
                options: .caseInsensitive,
                range: NSRange(location: searchLocation, length: result.length - searchLocation)
            )
            guard openingRange.location != NSNotFound else { break }
            let boundaryLocation = NSMaxRange(openingRange)
            guard boundaryLocation == result.length || !isRegexWordCodeUnit(result.character(at: boundaryLocation)) else {
                searchLocation = boundaryLocation
                continue
            }
            let openingEnd = result.range(
                of: ">",
                range: NSRange(location: boundaryLocation, length: result.length - boundaryLocation)
            )
            guard openingEnd.location != NSNotFound else { break }
            let contentLocation = NSMaxRange(openingEnd)
            let closingRange = result.range(
                of: "</p>",
                options: .caseInsensitive,
                range: NSRange(location: contentLocation, length: result.length - contentLocation)
            )
            guard closingRange.location != NSNotFound else { break }
            let content = result.substring(
                with: NSRange(location: contentLocation, length: closingRange.location - contentLocation)
            )
            if paragraphContentIsEmpty(content) {
                result.deleteCharacters(
                    in: NSRange(
                        location: openingRange.location,
                        length: NSMaxRange(closingRange) - openingRange.location
                    )
                )
                searchLocation = openingRange.location
            } else {
                searchLocation = NSMaxRange(closingRange)
            }
        }
        return String(result)
    }

    private static func paragraphContentIsEmpty(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || removingBreakTags(from: trimmed).isEmpty { return true }
        guard trimmed.range(of: "<span", options: [.anchored, .caseInsensitive]) != nil,
              let openingEnd = trimmed.firstIndex(of: ">"),
              let closingRange = trimmed.range(of: "</span>", options: [.backwards, .caseInsensitive]),
              closingRange.upperBound == trimmed.endIndex else { return false }
        let spanContent = String(trimmed[trimmed.index(after: openingEnd)..<closingRange.lowerBound])
        return removingBreakTags(from: spanContent).isEmpty
    }

    private static func removingBreakTags(from content: String) -> String {
        content
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
