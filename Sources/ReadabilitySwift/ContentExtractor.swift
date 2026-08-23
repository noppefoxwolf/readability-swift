import SwiftSoup

enum ContentExtractor {
    private struct Attempt {
        let content: String
        let textLength: Int
    }

    private struct CandidateScore {
        let element: Element
        var score: Double
    }

    private struct SerializationPolicy {
        let resolvesRelativeURLs: Bool
        let sanitizesContent: Bool
    }

    private typealias CandidateScores = [ObjectIdentifier: CandidateScore]

    static func grabArticle(
        _ document: Document,
        options: ReadabilityOptions,
        resolvesRelativeURLs: Bool = false
    ) throws -> String? {
        let allElements = try document.select("*")
        if options.maximumElementCount > 0 && allElements.count > options.maximumElementCount {
            throw ReadabilityError.maxElementsExceeded(options.maximumElementCount)
        }

        var attempts: [Attempt] = []
        var flags: ParseFlags = [.stripUnlikelies, .weightClasses]
        for attempt in 0..<3 {
            guard let content = try tryExtractWithFlags(
                document,
                options: options,
                flags: flags,
                resolvesRelativeURLs: resolvesRelativeURLs
            ) else {
                updateFlags(&flags, attempt: attempt)
                continue
            }
            let textLength = try DOMUtils.elementTextLength(content)
            if textLength >= options.characterThreshold { return content }
            attempts.append(Attempt(content: content, textLength: textLength))
            updateFlags(&flags, attempt: attempt)
        }
        return attempts.max(by: { $0.textLength < $1.textLength })?.content
    }

    private static func tryExtractWithFlags(
        _ document: Document,
        options: ReadabilityOptions,
        flags: ParseFlags,
        resolvesRelativeURLs: Bool
    ) throws -> String? {
        let candidates = try findCandidates(document, flags: flags)
        guard !candidates.isEmpty else { return nil }
        var scores = try scoreCandidates(candidates, options: options, flags: flags)
        try applyLinkDensityPenalty(scores: &scores)
        guard let best = try findBestCandidate(scores: scores, options: options) else {
            return nil
        }
        return try extractArticleContent(
            best: best,
            scores: scores,
            policy: SerializationPolicy(
                resolvesRelativeURLs: resolvesRelativeURLs,
                sanitizesContent: options.sanitizesContent
            )
        )
    }

    private static func findCandidates(_ document: Document, flags: ParseFlags) throws -> [Element] {
        var result: [Element] = []
        let selectors = ["p"] + Constants.defaultTagsToScore.map { $0.lowercased() }
        for selector in selectors {
            for element in try document.select(selector) {
                // Rust str::len() counts UTF-8 bytes, whereas Swift
                // String.count counts extended grapheme clusters. Compatibility
                // thresholds must therefore use utf8.count.
                guard DOMUtils.isProbablyVisible(element), DOMUtils.getInnerText(element, normalizeSpaces: false).utf8.count >= 25 else { continue }
                if flags.contains(.stripUnlikelies) {
                    let match = DOMUtils.classAndID(element)
                    if Constants.isUnlikelyCandidate(match) && !Constants.isMaybeCandidate(match) { continue }
                }
                result.append(element)
            }
        }
        return result
    }

    private static func scoreCandidates(_ candidates: [Element], options: ReadabilityOptions, flags: ParseFlags) throws -> CandidateScores {
        // readabilityrs keys this table by ego_tree::NodeId. SwiftSoup exposes
        // reference-typed nodes but no stable public node ID, so ObjectIdentifier
        // is the equivalent only for the lifetime of this parsed Document.
        var scores: CandidateScores = [:]
        for candidate in candidates {
            let contentScore = try Scoring.calculateContentScore(candidate, linkDensityModifier: options.linkDensityModifier)
            guard contentScore > 0 else { continue }
            addScore(candidate, amount: contentScore, to: &scores, flags: flags)
            for (level, ancestor) in DOMUtils.ancestors(candidate).enumerated() {
                let divisor = level == 0 ? 1.0 : (level == 1 ? 2.0 : Double(level * 3))
                addScore(ancestor, amount: contentScore / divisor, to: &scores, flags: flags)
            }
        }
        return scores
    }

    private static func addScore(_ element: Element, amount: Double, to scores: inout CandidateScores, flags: ParseFlags) {
        let identifier = ObjectIdentifier(element)
        if let current = scores[identifier] {
            scores[identifier] = CandidateScore(element: current.element, score: current.score + amount)
        } else {
            scores[identifier] = CandidateScore(element: element, score: Scoring.initializeNodeScore(element, flags: flags) + amount)
        }
    }

    private static func applyLinkDensityPenalty(scores: inout CandidateScores) throws {
        for identifier in scores.keys {
            guard let current = scores[identifier] else { continue }
            let density = try DOMUtils.linkDensity(current.element)
            scores[identifier] = CandidateScore(element: current.element, score: current.score * max(0, 1 - density))
        }
    }

    private static func findBestCandidate(scores: CandidateScores, options: ReadabilityOptions) throws -> Element? {
        let sorted = scores.values.sorted { $0.score > $1.score }
        let top = sorted.prefix(options.topCandidateCount)
        guard let highest = top.first else { return nil }
        var best = highest.element
        if let viable = try top.first(where: { try isViableBestCandidate($0.element, score: $0.score) }) {
            best = viable.element
        }
        var bestScore = scores[ObjectIdentifier(best)]?.score ?? 0
        if let promoted = try promoteSharedTopCandidateParent(best, bestScore: bestScore, topCandidates: Array(top)) {
            best = promoted
            bestScore = scores[ObjectIdentifier(best)]?.score ?? bestScore
        }
        if let promoted = try promoteNearTieAncestor(best, bestScore: bestScore, scores: scores) {
            best = promoted
            bestScore = scores[ObjectIdentifier(best)]?.score ?? bestScore
        }
        if let promoted = try promoteHighScoringParent(best, bestScore: bestScore, scores: scores) {
            best = promoted
            bestScore = scores[ObjectIdentifier(best)]?.score ?? bestScore
        }
        if let promoted = promoteSingleChildParent(best) {
            best = promoted
        }
        if let promoted = try promoteDenseWrapperChild(best, scores: scores, sortedScores: sorted) {
            best = promoted
            bestScore = scores[ObjectIdentifier(best)]?.score ?? bestScore
        }
        if let promoted = try promoteSemanticDescendant(best, bestScore: bestScore, sortedScores: sorted) {
            best = promoted
        }
        return best
    }

    private static func promoteNearTieAncestor(
        _ element: Element,
        bestScore: Double,
        scores: CandidateScores
    ) throws -> Element? {
        guard bestScore > 0 else { return nil }
        var current = element.parent()
        while let ancestor = current, !["BODY", "HTML"].contains(ancestor.tagName().uppercased()) {
            if let score = scores[ObjectIdentifier(ancestor)]?.score,
               score >= bestScore * 0.97,
               score <= bestScore * 1.03,
               try DOMUtils.linkDensity(ancestor) <= 0.33 {
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
        topCandidates: [CandidateScore]
    ) throws -> Element? {
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
        scores: CandidateScores
    ) throws -> Element? {
        var current = element
        var lastScore = bestScore
        let threshold = bestScore / 3
        while let parent = current.parent(), !["BODY", "HTML"].contains(parent.tagName().uppercased()) {
            let tag = parent.tagName().uppercased()
            let role = try parent.attr("role").lowercased()
            guard ["ARTICLE", "SECTION", "MAIN"].contains(tag) || role == "main" else {
                current = parent
                continue
            }
            let score = scores[ObjectIdentifier(parent)]?.score ?? 0
            if score < threshold { break }
            if try DOMUtils.linkDensity(parent) <= 0.33, score > lastScore { return parent }
            lastScore = score
            current = parent
        }
        return nil
    }

    private static func promoteDenseWrapperChild(
        _ element: Element,
        scores: CandidateScores,
        sortedScores: [CandidateScore]
    ) throws -> Element? {
        let tag = element.tagName().uppercased()
        guard !["ARTICLE", "SECTION", "MAIN"].contains(tag) else { return nil }
        let parentScore = scores[ObjectIdentifier(element)]?.score ?? 0
        let bestDensity = try DOMUtils.linkDensity(element)
        let fallback = try sortedScores.prefix(20)
            .compactMap { candidate -> (Element, Double)? in
                guard ObjectIdentifier(candidate.element) != ObjectIdentifier(element),
                      isDescendant(candidate.element, of: element) else { return nil }
                let textLength = DOMUtils.getInnerText(candidate.element, normalizeSpaces: false).utf8.count
                let density = try DOMUtils.linkDensity(candidate.element)
                let candidateWeight = Scoring.getClassWeight(candidate.element, flags: [.weightClasses])
                let marker = DOMUtils.classAndID(candidate.element)
                let paragraphCount = try candidate.element.select("p").count
                guard textLength >= 160,
                      density < 0.35,
                      density < bestDensity - 0.15,
                      !(candidateWeight < 0 && !Constants.isPositive(marker)),
                      paragraphCount > 0 || textLength >= 300 else { return nil }
                return (candidate.element, candidate.score)
            }.max(by: { $0.1 < $1.1 })
        guard let fallback, parentScore == 0 || fallback.1 >= parentScore * 0.45 else { return nil }
        return fallback.0
    }

    private static func promoteSemanticDescendant(
        _ element: Element,
        bestScore: Double,
        sortedScores: [CandidateScore]
    ) throws -> Element? {
        guard bestScore > 0 else { return nil }
        let marker = DOMUtils.classAndID(element).lowercased()
        let layoutKeywords = ["content", "container", "main", "column", "outer", "inner", "wrapper"]
        guard layoutKeywords.contains(where: marker.contains) else { return nil }
        let positiveKeywords = ["article", "post", "entry", "body", "story", "text", "blog"]
        return try sortedScores.prefix(40).compactMap { candidate -> (Element, Double)? in
            guard ObjectIdentifier(candidate.element) != ObjectIdentifier(element),
                  isDescendant(candidate.element, of: element),
                  DOMUtils.getInnerText(candidate.element, normalizeSpaces: false).utf8.count >= 200 else { return nil }
            guard try DOMUtils.linkDensity(candidate.element) <= 0.45 else { return nil }
            let itemprop = try candidate.element.attr("itemprop")
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
        scores: CandidateScores,
        policy: SerializationPolicy
    ) throws -> String? {
        guard let parent = best.parent() else { return Cleaner.replaceBRS(try serializeElement(best, policy: policy)) }
        let bestScore = scores[ObjectIdentifier(best)]?.score ?? 0
        let threshold = max(bestScore * 0.2, 10)
        let bestClass = try best.attr("class")
        var output: [String] = []
        for sibling in parent.children() {
            guard DOMUtils.isProbablyVisible(sibling) else { continue }
            let isBest = ObjectIdentifier(sibling) == ObjectIdentifier(best)
            let siblingScore = scores[ObjectIdentifier(sibling)]?.score ?? 0
            let siblingClass = try sibling.attr("class")
            let sameClass = !bestClass.isEmpty && siblingClass == bestClass
            let goodParagraph = try isGoodSiblingParagraph(sibling)
            let keepBlock = try shouldKeepBlockElement(sibling, bestScore: bestScore)
            if isBest || siblingScore + (sameClass ? bestScore * 0.2 : 0) >= threshold || goodParagraph || keepBlock {
                let html = try serializeElement(sibling, policy: policy)
                if !html.trimmed().isEmpty {
                    output.append(Cleaner.replaceBRS(html))
                }
            }
        }
        return output.joined(separator: "\n")
    }

    private static func isGoodSiblingParagraph(_ element: Element) throws -> Bool {
        guard element.tagName().uppercased() == "P" else { return false }
        let text = DOMUtils.getInnerText(element, normalizeSpaces: false)
        guard !text.isEmpty else { return false }
        let classID = DOMUtils.classAndID(element)
        if Constants.isUnlikelyCandidate(classID) && !Constants.isMaybeCandidate(classID) {
            return false
        }
        let density = try DOMUtils.linkDensity(element)
        if text.utf8.count > 80 && density < 0.25 { return true }
        return text.utf8.count <= 80 && density == 0 && text.firstMatch(of: /[.!?](?:\s|$)/) != nil
    }

    private static func shouldKeepBlockElement(_ element: Element, bestScore: Double) throws -> Bool {
        let tag = element.tagName().lowercased()
        guard ["div", "section", "article", "ul", "ol", "table"].contains(tag) else { return false }
        let weight = Scoring.getClassWeight(element, flags: [.weightClasses])
        let textLength = DOMUtils.getInnerText(element, normalizeSpaces: false).utf8.count
        let density = try DOMUtils.linkDensity(element)
        guard !(weight < -25 && bestScore < 100), textLength > 0, density <= 0.6 else { return false }
        if tag == "ul" || tag == "ol" {
            return try element.getElementsByTag("li").count >= 3 && textLength > 80 && density < 0.4
        }
        if tag == "table" {
            return try element.getElementsByTag("p").count >= 2 || (textLength > 200 && density < 0.45)
        }
        return textLength > 400 || (textLength > 140 && density < 0.35)
    }

    private static func isViableBestCandidate(_ element: Element, score: Double) throws -> Bool {
        let textLength = DOMUtils.getInnerText(element, normalizeSpaces: false).utf8.count
        if textLength < 150 && score < 50 { return false }
        let density = try DOMUtils.linkDensity(element)
        guard density <= 0.6 else { return false }
        let marker = DOMUtils.classAndID(element).lowercased()
        let navigationKeywords = ["nav", "navbar", "menu", "breadcrumbs", "sidebar", "widget"]
        return !(navigationKeywords.contains(where: marker.contains) && density > 0.3)
    }

    private static func serializeElement(_ element: Element, policy: SerializationPolicy) throws -> String {
        // Neither SwiftSoup serializer is a drop-in replacement for
        // readabilityrs's element_to_html: Element.html() emits only children,
        // while outerHtml() follows SwiftSoup's own void-tag and formatting
        // rules. Serialize explicitly to retain DIV-to-P and sanitizing parity.
        guard DOMUtils.isProbablyVisible(element) else { return "" }
        let originalTag = element.tagName().lowercased()
        if policy.sanitizesContent && ["script", "style", "iframe", "object", "embed", "form", "noscript", "template"].contains(originalTag) {
            return ""
        }
        let tag = shouldConvertDivToParagraph(element) ? "p" : originalTag
        var html = "<\(tag)"
        if let attributes = element.getAttributes() {
            for attribute in attributes.asList() {
                let name = attribute.getKey().lowercased()
                if policy.sanitizesContent {
                    if name.hasPrefix("on") { continue }
                    if ["href", "src", "xlink:href"].contains(name), Utils.isDangerousURL(attribute.getValue()) { continue }
                }
                let value: String
                if policy.resolvesRelativeURLs, ["href", "src", "poster"].contains(name) {
                    let absoluteURL = try element.absUrl(name)
                    value = absoluteURL.isEmpty ? attribute.getValue() : absoluteURL
                } else {
                    value = attribute.getValue()
                }
                let serializedAttribute = attribute.clone()
                serializedAttribute.setValue(value: Array(value.utf8))
                html += " \(serializedAttribute.html())"
            }
        }
        let voidElements = Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"])
        if voidElements.contains(tag) { return html + " />" }
        html += ">"
        for node in element.getChildNodes() {
            if let child = node as? Element {
                html += try serializeElement(child, policy: policy)
            } else if let text = node as? TextNode {
                html += Entities.escape(text.getWholeText())
            } else if let comment = node as? Comment, !policy.sanitizesContent {
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
        default: break
        }
    }

    private static func matches(_ value: String, _ regex: Regex<Substring>) -> Bool {
        value.firstMatch(of: regex) != nil
    }
}
