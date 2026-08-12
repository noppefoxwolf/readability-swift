import SwiftSoup

enum ContentExtractor {
    private struct Attempt {
        let content: String
        let textLength: Int
    }

    static func grabArticle(_ document: Document, options: ReadabilityOptions) -> ReadabilityResult<String?> {
        let allElements = (try? document.select("*")) ?? SwiftSoup.Elements()
        if options.maxElemsToParse > 0 && allElements.count > options.maxElemsToParse {
            return .failure(.maxElementsExceeded(options.maxElemsToParse))
        }

        var attempts: [Attempt] = []
        var flags: ParseFlags = [.stripUnlikelies, .weightClasses, .cleanConditionally]
        for attempt in 0..<4 {
            guard let content = tryExtractWithFlags(document, options: options, flags: flags) else {
                updateFlags(&flags, attempt: attempt)
                continue
            }
            let textLength = DOMUtils.elementTextLength(content)
            if textLength >= options.charThreshold { return .success(content) }
            attempts.append(Attempt(content: content, textLength: textLength))
            updateFlags(&flags, attempt: attempt)
        }
        return .success(attempts.max(by: { $0.textLength < $1.textLength })?.content)
    }

    private static func tryExtractWithFlags(_ document: Document, options: ReadabilityOptions, flags: ParseFlags) -> String? {
        let candidates = findCandidates(document, flags: flags)
        guard !candidates.isEmpty else { return nil }
        var scores = scoreCandidates(candidates, options: options, flags: flags)
        applyLinkDensityPenalty(scores: &scores)
        guard let best = findBestCandidate(scores: scores, options: options) else {
            return nil
        }
        return extractArticleContent(best: best, scores: scores, sanitizeContent: options.sanitizeContent)
    }

    private static func findCandidates(_ document: Document, flags: ParseFlags) -> [Element] {
        var result: [Element] = []
        let selectors = ["p"] + Constants.defaultTagsToScore.map { $0.lowercased() }
        for selector in selectors {
            for element in (try? document.select(selector)) ?? SwiftSoup.Elements() {
                // Rust str::len() counts UTF-8 bytes, whereas Swift
                // String.count counts extended grapheme clusters. Compatibility
                // thresholds must therefore use utf8.count.
                guard DOMUtils.isProbablyVisible(element), DOMUtils.getInnerText(element, normalizeSpaces: false).utf8.count >= 25 else { continue }
                if flags.contains(.stripUnlikelies) {
                    let match = DOMUtils.classAndID(element)
                    if matches(match, Constants.unlikelyCandidates) && !matches(match, Constants.okMaybeItsACandidate) { continue }
                }
                result.append(element)
            }
        }
        return result
    }

    private static func scoreCandidates(_ candidates: [Element], options: ReadabilityOptions, flags: ParseFlags) -> [ObjectIdentifier: (element: Element, score: Double)] {
        // readabilityrs keys this table by ego_tree::NodeId. SwiftSoup exposes
        // reference-typed nodes but no stable public node ID, so ObjectIdentifier
        // is the equivalent only for the lifetime of this parsed Document.
        var scores: [ObjectIdentifier: (element: Element, score: Double)] = [:]
        for candidate in candidates {
            let contentScore = Scoring.calculateContentScore(candidate, linkDensityModifier: options.linkDensityModifier)
            guard contentScore > 0 else { continue }
            addScore(candidate, amount: contentScore, to: &scores, flags: flags)
            for (level, ancestor) in DOMUtils.ancestors(candidate).enumerated() {
                let divisor = level == 0 ? 1.0 : (level == 1 ? 2.0 : Double(level * 3))
                addScore(ancestor, amount: contentScore / divisor, to: &scores, flags: flags)
            }
        }
        return scores
    }

    private static func addScore(_ element: Element, amount: Double, to scores: inout [ObjectIdentifier: (element: Element, score: Double)], flags: ParseFlags) {
        let identifier = ObjectIdentifier(element)
        if let current = scores[identifier] {
            scores[identifier] = (current.element, current.score + amount)
        } else {
            scores[identifier] = (element, Scoring.initializeNodeScore(element, flags: flags) + amount)
        }
    }

    private static func applyLinkDensityPenalty(scores: inout [ObjectIdentifier: (element: Element, score: Double)]) {
        for identifier in scores.keys {
            guard let current = scores[identifier] else { continue }
            scores[identifier] = (current.element, current.score * max(0, 1 - DOMUtils.linkDensity(current.element)))
        }
    }

    private static func findBestCandidate(scores: [ObjectIdentifier: (element: Element, score: Double)], options: ReadabilityOptions) -> Element? {
        let sorted = scores.values.sorted { $0.score > $1.score }
        let top = sorted.prefix(options.nbTopCandidates)
        guard let highest = top.first else { return nil }
        var best = highest.element
        if let viable = top.first(where: { isViableBestCandidate($0.element, score: $0.score) }) {
            best = viable.element
        }
        var bestScore = scores[ObjectIdentifier(best)]?.score ?? 0
        if let promoted = promoteSharedTopCandidateParent(best, bestScore: bestScore, topCandidates: Array(top)) {
            best = promoted
            bestScore = scores[ObjectIdentifier(best)]?.score ?? bestScore
        }
        if let promoted = promoteNearTieAncestor(best, bestScore: bestScore, scores: scores) {
            best = promoted
            bestScore = scores[ObjectIdentifier(best)]?.score ?? bestScore
        }
        if let promoted = promoteHighScoringParent(best, bestScore: bestScore, scores: scores) {
            best = promoted
            bestScore = scores[ObjectIdentifier(best)]?.score ?? bestScore
        }
        if let promoted = promoteSingleChildParent(best) {
            best = promoted
        }
        if let promoted = promoteDenseWrapperChild(best, scores: scores, sortedScores: sorted) {
            best = promoted
            bestScore = scores[ObjectIdentifier(best)]?.score ?? bestScore
        }
        if let promoted = promoteSemanticDescendant(best, bestScore: bestScore, sortedScores: sorted) {
            best = promoted
        }
        return best
    }

    private static func promoteNearTieAncestor(
        _ element: Element,
        bestScore: Double,
        scores: [ObjectIdentifier: (element: Element, score: Double)]
    ) -> Element? {
        guard bestScore > 0 else { return nil }
        var current = element.parent()
        while let ancestor = current, !["BODY", "HTML"].contains(ancestor.tagName().uppercased()) {
            if let score = scores[ObjectIdentifier(ancestor)]?.score,
               score >= bestScore * 0.97,
               score <= bestScore * 1.03,
               DOMUtils.linkDensity(ancestor) <= 0.33 {
                // scraper/html5ever and SwiftSoup can attach malformed-HTML
                // text nodes to adjacent containers differently. That slightly
                // changes link-density scores and can reverse two near-equal
                // nested candidates. readabilityrs then keeps the broader
                // ancestor, so preserve it when the score difference is noise-
                // sized in either direction and it still looks content-dense.
                return ancestor
            }
            current = ancestor.parent()
        }
        return nil
    }

    private static func promoteSharedTopCandidateParent(
        _ element: Element,
        bestScore: Double,
        topCandidates: [(element: Element, score: Double)]
    ) -> Element? {
        guard bestScore > 0 else { return nil }
        let ancestorLists = topCandidates.dropFirst().filter { $0.score >= bestScore * 0.75 }.map {
            Set(DOMUtils.ancestors($0.element, limit: 0).map(ObjectIdentifier.init))
        }
        guard ancestorLists.count >= 3 else { return nil }

        var current = element.parent()
        // readabilityrs stops at BODY but deliberately still evaluates HTML.
        // Yahoo's modal fixture relies on the HTML class marker to descend
        // from a page-wide top score back into the semantic article body.
        while let parent = current, parent.tagName().uppercased() != "BODY" {
            let id = ObjectIdentifier(parent)
            if ancestorLists.filter({ $0.contains(id) }).count >= 3 { return parent }
            current = parent.parent()
        }
        return nil
    }

    private static func promoteSingleChildParent(_ element: Element) -> Element? {
        var current = element
        var promoted: Element?
        while let parent = current.parent(), parent.tagName().uppercased() != "BODY" {
            // scraper's document node cannot be wrapped as ElementRef. SwiftSoup
            // exposes the same node as a pseudo-element named #root, which must
            // not become an article candidate.
            guard parent.tagName() != "#root" else { break }
            guard parent.children().count == 1 else { break }
            promoted = parent
            current = parent
        }
        return promoted
    }

    private static func promoteHighScoringParent(
        _ element: Element,
        bestScore: Double,
        scores: [ObjectIdentifier: (element: Element, score: Double)]
    ) -> Element? {
        var current = element
        var lastScore = bestScore
        let threshold = bestScore / 3
        while let parent = current.parent(), !["BODY", "HTML"].contains(parent.tagName().uppercased()) {
            let tag = parent.tagName().uppercased()
            let role = ((try? parent.attr("role")) ?? "").lowercased()
            guard ["ARTICLE", "SECTION", "MAIN"].contains(tag) || role == "main" else {
                current = parent
                continue
            }
            let score = scores[ObjectIdentifier(parent)]?.score ?? 0
            if score < threshold { break }
            if DOMUtils.linkDensity(parent) <= 0.33 && score > lastScore { return parent }
            lastScore = score
            current = parent
        }
        return nil
    }

    private static func promoteDenseWrapperChild(
        _ element: Element,
        scores: [ObjectIdentifier: (element: Element, score: Double)],
        sortedScores: [(element: Element, score: Double)]
    ) -> Element? {
        let tag = element.tagName().uppercased()
        guard !["ARTICLE", "SECTION", "MAIN"].contains(tag) else { return nil }
        let parentScore = scores[ObjectIdentifier(element)]?.score ?? 0
        let bestDensity = DOMUtils.linkDensity(element)
        let fallback = sortedScores.prefix(20)
            .compactMap { candidate -> (Element, Double)? in
                guard ObjectIdentifier(candidate.element) != ObjectIdentifier(element),
                      isDescendant(candidate.element, of: element) else { return nil }
                let textLength = DOMUtils.getInnerText(candidate.element, normalizeSpaces: false).utf8.count
                let density = DOMUtils.linkDensity(candidate.element)
                let candidateWeight = Scoring.getClassWeight(candidate.element, flags: [.weightClasses])
                let marker = DOMUtils.classAndID(candidate.element)
                let paragraphCount = (try? candidate.element.select("p").count) ?? 0
                guard textLength >= 160,
                      density < 0.35,
                      density < bestDensity - 0.15,
                      !(candidateWeight < 0 && !matches(marker, Constants.positive)),
                      paragraphCount > 0 || textLength >= 300 else { return nil }
                return (candidate.element, candidate.score)
            }.max(by: { $0.1 < $1.1 })
        guard let fallback, parentScore == 0 || fallback.1 >= parentScore * 0.45 else { return nil }
        return fallback.0
    }

    private static func promoteSemanticDescendant(
        _ element: Element,
        bestScore: Double,
        sortedScores: [(element: Element, score: Double)]
    ) -> Element? {
        guard bestScore > 0 else { return nil }
        let marker = DOMUtils.classAndID(element).lowercased()
        let layoutKeywords = ["content", "container", "main", "column", "outer", "inner", "wrapper"]
        guard layoutKeywords.contains(where: marker.contains) else { return nil }
        let positiveKeywords = ["article", "post", "entry", "body", "story", "text", "blog"]
        return sortedScores.prefix(40).compactMap { candidate -> (Element, Double)? in
            guard ObjectIdentifier(candidate.element) != ObjectIdentifier(element),
                  isDescendant(candidate.element, of: element),
                  DOMUtils.getInnerText(candidate.element, normalizeSpaces: false).utf8.count >= 200,
                  DOMUtils.linkDensity(candidate.element) <= 0.45 else { return nil }
            let itemprop = (try? candidate.element.attr("itemprop")) ?? ""
            let candidateMarker = "\(DOMUtils.classAndID(candidate.element)) \(itemprop)".lowercased()
            guard positiveKeywords.contains(where: candidateMarker.contains) || candidateMarker.contains("articlebody") else { return nil }
            guard candidate.score >= bestScore * 0.4 else { return nil }
            return (candidate.element, candidate.score)
        }.max(by: { $0.1 < $1.1 })?.0
    }

    private static func isDescendant(_ candidate: Element, of ancestor: Element) -> Bool {
        DOMUtils.ancestors(candidate, limit: 0).contains { ObjectIdentifier($0) == ObjectIdentifier(ancestor) }
    }

    private static func extractArticleContent(
        best: Element,
        scores: [ObjectIdentifier: (element: Element, score: Double)],
        sanitizeContent: Bool
    ) -> String? {
        guard let parent = best.parent() else { return Cleaner.replaceBRS(serializeElement(best, sanitizeContent: sanitizeContent)) }
        let bestScore = scores[ObjectIdentifier(best)]?.score ?? 0
        let threshold = max(bestScore * 0.2, 10)
        let bestClass = (try? best.attr("class")) ?? ""
        var output: [String] = []
        for sibling in parent.children() {
            guard DOMUtils.isProbablyVisible(sibling) else { continue }
            let isBest = ObjectIdentifier(sibling) == ObjectIdentifier(best)
            let siblingScore = scores[ObjectIdentifier(sibling)]?.score ?? 0
            let sameClass = !bestClass.isEmpty && (try? sibling.attr("class")) == bestClass
            let goodParagraph = isGoodSiblingParagraph(sibling)
            let keepBlock = shouldKeepBlockElement(sibling, bestScore: bestScore)
            if isBest || siblingScore + (sameClass ? bestScore * 0.2 : 0) >= threshold || goodParagraph || keepBlock {
                let html = serializeElement(sibling, sanitizeContent: sanitizeContent)
                if !html.trimmed().isEmpty {
                    output.append(Cleaner.replaceBRS(html))
                }
            }
        }
        return output.joined(separator: "\n")
    }

    private static func isGoodSiblingParagraph(_ element: Element) -> Bool {
        guard element.tagName().uppercased() == "P" else { return false }
        let text = DOMUtils.getInnerText(element, normalizeSpaces: false)
        guard !text.isEmpty else { return false }
        let classID = DOMUtils.classAndID(element)
        if matches(classID, Constants.unlikelyCandidates) && !matches(classID, Constants.okMaybeItsACandidate) {
            return false
        }
        let density = DOMUtils.linkDensity(element)
        if text.utf8.count > 80 && density < 0.25 { return true }
        return text.utf8.count <= 80 && density == 0 && text.firstMatch(of: /[.!?](?:\s|$)/) != nil
    }

    private static func shouldKeepBlockElement(_ element: Element, bestScore: Double) -> Bool {
        let tag = element.tagName().lowercased()
        guard ["div", "section", "article", "ul", "ol", "table"].contains(tag) else { return false }
        let weight = Scoring.getClassWeight(element, flags: [.weightClasses])
        let textLength = DOMUtils.getInnerText(element, normalizeSpaces: false).utf8.count
        let density = DOMUtils.linkDensity(element)
        guard !(weight < -25 && bestScore < 100), textLength > 0, density <= 0.6 else { return false }
        if tag == "ul" || tag == "ol" {
            return ((try? element.getElementsByTag("li").count) ?? 0) >= 3 && textLength > 80 && density < 0.4
        }
        if tag == "table" {
            return ((try? element.getElementsByTag("p").count) ?? 0) >= 2 || (textLength > 200 && density < 0.45)
        }
        return textLength > 400 || (textLength > 140 && density < 0.35)
    }

    private static func isViableBestCandidate(_ element: Element, score: Double) -> Bool {
        let textLength = DOMUtils.getInnerText(element, normalizeSpaces: false).utf8.count
        if textLength < 150 && score < 50 { return false }
        let density = DOMUtils.linkDensity(element)
        guard density <= 0.6 else { return false }
        let marker = DOMUtils.classAndID(element).lowercased()
        let navigationKeywords = ["nav", "navbar", "menu", "breadcrumbs", "sidebar", "widget"]
        return !(navigationKeywords.contains(where: marker.contains) && density > 0.3)
    }

    private static func serializeElement(_ element: Element, sanitizeContent: Bool) -> String {
        // Neither SwiftSoup serializer is a drop-in replacement for
        // readabilityrs's element_to_html: Element.html() emits only children,
        // while outerHtml() follows SwiftSoup's own void-tag and formatting
        // rules. Serialize explicitly to retain DIV-to-P and sanitizing parity.
        guard DOMUtils.isProbablyVisible(element) else { return "" }
        let originalTag = element.tagName().lowercased()
        if sanitizeContent && ["script", "style", "iframe", "object", "embed", "form", "noscript", "template"].contains(originalTag) {
            return ""
        }
        let tag = shouldConvertDivToParagraph(element) ? "p" : originalTag
        var html = "<\(tag)"
        if let attributes = element.getAttributes() {
            for attribute in attributes.asList() {
                if sanitizeContent {
                    let name = attribute.getKey().lowercased()
                    if name.hasPrefix("on") { continue }
                    if ["href", "src", "xlink:href"].contains(name), Utils.isDangerousURL(attribute.getValue()) { continue }
                }
                html += " \(attribute.html())"
            }
        }
        let voidElements = Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"])
        if voidElements.contains(tag) { return html + " />" }
        html += ">"
        for node in element.getChildNodes() {
            if let child = node as? Element {
                html += serializeElement(child, sanitizeContent: sanitizeContent)
            } else if let text = node as? TextNode {
                html += Entities.escape(text.getWholeText())
            } else if let comment = node as? Comment, !sanitizeContent {
                html += "<!--\(comment.getData())-->"
            }
        }
        return html + "</\(tag)>"
    }

    private static func shouldConvertDivToParagraph(_ element: Element) -> Bool {
        guard element.tagName().uppercased() == "DIV" else { return false }
        let childTags = element.getChildNodes().compactMap { $0 as? Element }.map { $0.tagName().uppercased() }
        return !childTags.contains(where: Constants.divToPElems.contains)
    }

    private static func updateFlags(_ flags: inout ParseFlags, attempt: Int) {
        switch attempt {
        case 0: flags.remove(.stripUnlikelies)
        case 1: flags.remove(.weightClasses)
        case 2: flags.remove(.cleanConditionally)
        default: break
        }
    }

    private static func matches(_ value: String, _ regex: Regex<Substring>) -> Bool {
        value.firstMatch(of: regex) != nil
    }
}
