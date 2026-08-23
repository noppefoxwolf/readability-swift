import SwiftSoup
import Synchronization

enum PostProcessor {
    private static let presentationAttributesRegex = Mutex(
        #/(?i)\s+(?:style\s*=\s*(?:"[^"]*"|'[^']*')|(?:align|bgcolor|valign)\s*=\s*["'][^"']*["'])/#
    )

    private static let unwantedElementRegexes = Mutex([
        #/(?is)<form\b[^>]*?>.*?</form>/#,
        #/(?is)<fieldset\b[^>]*?>.*?</fieldset>/#,
        #/(?is)<footer\b[^>]*?>.*?</footer>/#,
        #/(?is)<aside\b[^>]*?>.*?</aside>/#,
        #/(?is)<object\b[^>]*?>.*?</object>/#,
        #/(?is)<embed\b[^>]*?>.*?</embed>|<embed\b[^>]*?/?>/#,
        #/(?is)<iframe\b[^>]*?>.*?</iframe>/#,
        #/(?is)<input\b[^>]*?>.*?</input>|<input\b[^>]*?/?>/#,
        #/(?is)<textarea\b[^>]*?>.*?</textarea>/#,
        #/(?is)<select\b[^>]*?>.*?</select>/#,
        #/(?is)<button\b[^>]*?>.*?</button>/#,
        #/(?is)<link\b[^>]*?>.*?</link>|<link\b[^>]*?/?>/#,
    ])

    private static let navigationElementRegex = Mutex(#/(?is)<nav\b[^>]*?>.*?</nav>/#)

    // Keep the regex order aligned with readabilityrs's wrapper removal matrix:
    // tag, keyword, then class before id. Lazy matching stops at the first
    // closing tag, rather than removing a complete nested DOM wrapper.
    private static let shareWrapperRegexes = Mutex([
        #/(?is)<div\b[^>]*?class="[^"]*?share[^"]*?"[^>]*?>.*?</div>/#,
        #/(?is)<div\b[^>]*?id="[^"]*?share[^"]*?"[^>]*?>.*?</div>/#,
        #/(?is)<div\b[^>]*?class="[^"]*?social[^"]*?"[^>]*?>.*?</div>/#,
        #/(?is)<div\b[^>]*?id="[^"]*?social[^"]*?"[^>]*?>.*?</div>/#,
        #/(?is)<div\b[^>]*?class="[^"]*?sharedaddy[^"]*?"[^>]*?>.*?</div>/#,
        #/(?is)<div\b[^>]*?id="[^"]*?sharedaddy[^"]*?"[^>]*?>.*?</div>/#,
        #/(?is)<span\b[^>]*?class="[^"]*?share[^"]*?"[^>]*?>.*?</span>/#,
        #/(?is)<span\b[^>]*?id="[^"]*?share[^"]*?"[^>]*?>.*?</span>/#,
        #/(?is)<span\b[^>]*?class="[^"]*?social[^"]*?"[^>]*?>.*?</span>/#,
        #/(?is)<span\b[^>]*?id="[^"]*?social[^"]*?"[^>]*?>.*?</span>/#,
        #/(?is)<span\b[^>]*?class="[^"]*?sharedaddy[^"]*?"[^>]*?>.*?</span>/#,
        #/(?is)<span\b[^>]*?id="[^"]*?sharedaddy[^"]*?"[^>]*?>.*?</span>/#,
        #/(?is)<aside\b[^>]*?class="[^"]*?share[^"]*?"[^>]*?>.*?</aside>/#,
        #/(?is)<aside\b[^>]*?id="[^"]*?share[^"]*?"[^>]*?>.*?</aside>/#,
        #/(?is)<aside\b[^>]*?class="[^"]*?social[^"]*?"[^>]*?>.*?</aside>/#,
        #/(?is)<aside\b[^>]*?id="[^"]*?social[^"]*?"[^>]*?>.*?</aside>/#,
        #/(?is)<aside\b[^>]*?class="[^"]*?sharedaddy[^"]*?"[^>]*?>.*?</aside>/#,
        #/(?is)<aside\b[^>]*?id="[^"]*?sharedaddy[^"]*?"[^>]*?>.*?</aside>/#,
        #/(?is)<section\b[^>]*?class="[^"]*?share[^"]*?"[^>]*?>.*?</section>/#,
        #/(?is)<section\b[^>]*?id="[^"]*?share[^"]*?"[^>]*?>.*?</section>/#,
        #/(?is)<section\b[^>]*?class="[^"]*?social[^"]*?"[^>]*?>.*?</section>/#,
        #/(?is)<section\b[^>]*?id="[^"]*?social[^"]*?"[^>]*?>.*?</section>/#,
        #/(?is)<section\b[^>]*?class="[^"]*?sharedaddy[^"]*?"[^>]*?>.*?</section>/#,
        #/(?is)<section\b[^>]*?id="[^"]*?sharedaddy[^"]*?"[^>]*?>.*?</section>/#,
    ])

    private static let navigationWrapperRegexes = Mutex([
        #/(?is)<div\b[^>]*?class="[^"]*?nav[^"]*?"[^>]*?>.*?</div>/#,
        #/(?is)<div\b[^>]*?id="[^"]*?nav[^"]*?"[^>]*?>.*?</div>/#,
        #/(?is)<div\b[^>]*?class="[^"]*?navbar[^"]*?"[^>]*?>.*?</div>/#,
        #/(?is)<div\b[^>]*?id="[^"]*?navbar[^"]*?"[^>]*?>.*?</div>/#,
        #/(?is)<div\b[^>]*?class="[^"]*?menu[^"]*?"[^>]*?>.*?</div>/#,
        #/(?is)<div\b[^>]*?id="[^"]*?menu[^"]*?"[^>]*?>.*?</div>/#,
        #/(?is)<div\b[^>]*?class="[^"]*?breadcrumbs[^"]*?"[^>]*?>.*?</div>/#,
        #/(?is)<div\b[^>]*?id="[^"]*?breadcrumbs[^"]*?"[^>]*?>.*?</div>/#,
        #/(?is)<section\b[^>]*?class="[^"]*?nav[^"]*?"[^>]*?>.*?</section>/#,
        #/(?is)<section\b[^>]*?id="[^"]*?nav[^"]*?"[^>]*?>.*?</section>/#,
        #/(?is)<section\b[^>]*?class="[^"]*?navbar[^"]*?"[^>]*?>.*?</section>/#,
        #/(?is)<section\b[^>]*?id="[^"]*?navbar[^"]*?"[^>]*?>.*?</section>/#,
        #/(?is)<section\b[^>]*?class="[^"]*?menu[^"]*?"[^>]*?>.*?</section>/#,
        #/(?is)<section\b[^>]*?id="[^"]*?menu[^"]*?"[^>]*?>.*?</section>/#,
        #/(?is)<section\b[^>]*?class="[^"]*?breadcrumbs[^"]*?"[^>]*?>.*?</section>/#,
        #/(?is)<section\b[^>]*?id="[^"]*?breadcrumbs[^"]*?"[^>]*?>.*?</section>/#,
        #/(?is)<ul\b[^>]*?class="[^"]*?nav[^"]*?"[^>]*?>.*?</ul>/#,
        #/(?is)<ul\b[^>]*?id="[^"]*?nav[^"]*?"[^>]*?>.*?</ul>/#,
        #/(?is)<ul\b[^>]*?class="[^"]*?navbar[^"]*?"[^>]*?>.*?</ul>/#,
        #/(?is)<ul\b[^>]*?id="[^"]*?navbar[^"]*?"[^>]*?>.*?</ul>/#,
        #/(?is)<ul\b[^>]*?class="[^"]*?menu[^"]*?"[^>]*?>.*?</ul>/#,
        #/(?is)<ul\b[^>]*?id="[^"]*?menu[^"]*?"[^>]*?>.*?</ul>/#,
        #/(?is)<ul\b[^>]*?class="[^"]*?breadcrumbs[^"]*?"[^>]*?>.*?</ul>/#,
        #/(?is)<ul\b[^>]*?id="[^"]*?breadcrumbs[^"]*?"[^>]*?>.*?</ul>/#,
        #/(?is)<ol\b[^>]*?class="[^"]*?nav[^"]*?"[^>]*?>.*?</ol>/#,
        #/(?is)<ol\b[^>]*?id="[^"]*?nav[^"]*?"[^>]*?>.*?</ol>/#,
        #/(?is)<ol\b[^>]*?class="[^"]*?navbar[^"]*?"[^>]*?>.*?</ol>/#,
        #/(?is)<ol\b[^>]*?id="[^"]*?navbar[^"]*?"[^>]*?>.*?</ol>/#,
        #/(?is)<ol\b[^>]*?class="[^"]*?menu[^"]*?"[^>]*?>.*?</ol>/#,
        #/(?is)<ol\b[^>]*?id="[^"]*?menu[^"]*?"[^>]*?>.*?</ol>/#,
        #/(?is)<ol\b[^>]*?class="[^"]*?breadcrumbs[^"]*?"[^>]*?>.*?</ol>/#,
        #/(?is)<ol\b[^>]*?id="[^"]*?breadcrumbs[^"]*?"[^>]*?>.*?</ol>/#,
    ])

    static func prepArticle(
        _ html: String,
        cleanStyles: Bool,
        cleanWhitespace: Bool
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
                fragment.replacing(/\n{3,}/, with: "\n\n").replacing(/[ ]{2,}/, with: " ")
            }
        }
        return result
    }

    static func applyClassPolicy(_ policy: HTMLClassPolicy, to html: String) throws -> String {
        guard policy != .keepAll else { return html }
        let document = try DOMUtils.parse(html)
        guard let body = document.body() else { return html }
        for element in try body.select("[class]") {
            let className = DOMUtils.attribute("class", of: element)
            if let retained = policy.retainedClasses(from: className) {
                try element.attr("class", retained)
            } else {
                try element.removeAttr("class")
            }
        }
        return try body.html()
    }

    static func removeTitleFromContent(_ html: String, title: String) throws -> String {
        let document = try DOMUtils.parse(html)
        guard let body = document.body() else { return html }
        let normalizedTitle = DOMUtils.normalizeWhitespace(title).lowercased()
        guard !normalizedTitle.isEmpty else { return html }
        for element in try body.select("h1,h2") where DOMUtils.normalizeWhitespace(DOMUtils.textContent(element)).lowercased() == normalizedTitle {
            try element.remove()
        }
        for element in try body.select("h1,h2") {
            let candidate = DOMUtils.normalizeWhitespace(DOMUtils.textContent(element)).lowercased()
            guard !candidate.isEmpty else { continue }
            let ratio = Double(min(candidate.count, normalizedTitle.count)) / Double(max(candidate.count, normalizedTitle.count))
            if ratio > 0.8 && (candidate.contains(normalizedTitle) || normalizedTitle.contains(candidate)) { try element.remove() }
        }
        for header in try body.select("header") where DOMUtils.normalizeWhitespace(DOMUtils.textContent(header)).isEmpty {
            try header.remove()
        }
        return try body.html()
    }

    private static func removingPresentationAttributes(from html: String) -> String {
        presentationAttributesRegex.withLock { regex in
            html.replacing(regex, with: "")
        }
    }

    private static func removingUnwantedElements(from html: String) -> String {
        unwantedElementRegexes.withLock { patterns in
            removingMatches(from: html, with: patterns)
        }
    }

    private static func removingShareElements(from html: String) -> String {
        shareWrapperRegexes.withLock { patterns in
            removingMatches(from: html, with: patterns)
        }
    }

    private static func removingNavigationElements(from html: String) -> String {
        let withoutNav = navigationElementRegex.withLock { html.replacing($0, with: "") }
        return navigationWrapperRegexes.withLock { patterns in
            removingMatches(from: withoutNav, with: patterns)
        }
    }

    private static func removingMatches(from html: String, with patterns: [Regex<Substring>]) -> String {
        patterns.reduce(html) { result, pattern in
            result.replacing(pattern, with: "")
        }
    }

    private static func isRegexWordCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    private static func removingEmptyParagraphs(from html: String) -> String {
        var result = html
        for _ in 0..<5 {
            let cleaned = removingEmptyParagraphPass(from: result)
            if cleaned == result { break }
            result = cleaned
        }
        return result.replacing(#/(?i)(</(?:p|div|h[1-6])>)\s*(?:<br\s*/?>[\s\n]*)+\s*(<(?:p|div|h[1-6]))/#) { match in
            "\(match.1)\n\(match.2)"
        }
    }

    private static func removingEmptyParagraphPass(from html: String) -> String {
        var result = html
        var searchStart = result.startIndex
        while searchStart < result.endIndex {
            guard let openingRange = result.firstASCIICaseInsensitiveRange(
                of: "<p",
                in: searchStart..<result.endIndex
            ) else { break }
            let boundary = openingRange.upperBound
            guard boundary == result.endIndex || !isRegexWordCharacter(result[boundary]) else {
                searchStart = boundary
                continue
            }
            guard let openingEnd = result.firstRange(of: ">", in: boundary..<result.endIndex),
                  let closingRange = result.firstASCIICaseInsensitiveRange(
                    of: "</p>",
                    in: openingEnd.upperBound..<result.endIndex
                  ) else { break }
            let content = String(result[openingEnd.upperBound..<closingRange.lowerBound])
            if paragraphContentIsEmpty(content) {
                let resumeOffset = utf8Offset(of: openingRange.lowerBound, in: result)
                result.removeSubrange(openingRange.lowerBound..<closingRange.upperBound)
                searchStart = index(in: result, atUTF8Offset: resumeOffset)
            } else {
                searchStart = closingRange.upperBound
            }
        }
        return result
    }

    private static func paragraphContentIsEmpty(_ content: String) -> Bool {
        let trimmed = content.trimmed()
        if trimmed.isEmpty || removingBreakTags(from: trimmed).isEmpty { return true }
        guard trimmed.firstASCIICaseInsensitiveRange(of: "<span")?.lowerBound == trimmed.startIndex,
              let openingEnd = trimmed.firstIndex(of: ">"),
              let closingRange = trimmed.lastASCIICaseInsensitiveRange(of: "</span>"),
              closingRange.upperBound == trimmed.endIndex else { return false }
        let spanContent = String(trimmed[trimmed.index(after: openingEnd)..<closingRange.lowerBound])
        return removingBreakTags(from: spanContent).isEmpty
    }

    private static func removingBreakTags(from content: String) -> String {
        content.replacing(#/(?i)<br\s*/?>/#, with: "")
            .trimmed()
    }

    private static func utf8Offset(of index: String.Index, in string: String) -> Int {
        guard let utf8Index = index.samePosition(in: string.utf8) else {
            return 0
        }
        return string.utf8.distance(from: string.utf8.startIndex, to: utf8Index)
    }

    private static func index(in string: String, atUTF8Offset offset: Int) -> String.Index {
        let utf8Index = string.utf8.index(string.utf8.startIndex, offsetBy: offset)
        guard let index = String.Index(utf8Index, within: string) else {
            return string.startIndex
        }
        return index
    }
}
