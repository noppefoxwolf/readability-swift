import SwiftSoup

enum Scoring {
    static func getClassWeight(_ element: Element, flags: ParseFlags = [.weightClasses]) -> Int {
        guard flags.contains(.weightClasses) else { return 0 }
        var weight = 0
        for attribute in ["class", "id"] {
            let value = ((try? element.attr(attribute)) ?? "").lowercased()
            guard !value.isEmpty else { continue }
            if matches(value, Constants.regexps.negative) {
                weight -= 25
            } else if matches(value, Constants.regexps.positive) {
                weight += 25
            }
        }
        return weight
    }

    static func initializeNodeScore(_ element: Element, flags: ParseFlags) -> Double {
        var score: Double
        switch element.tagName().uppercased() {
        case "P": score = 5
        case "SECTION", "ARTICLE": score = 8
        case "DIV": score = DOMUtils.hasChildBlockElement(element) ? 2 : 5
        case "PRE", "TD", "BLOCKQUOTE": score = 3
        case "ADDRESS", "OL", "UL", "DL", "DD", "DT", "LI", "FORM": score = -3
        case "H1", "H2", "H3", "H4", "H5", "H6", "TH": score = -5
        default: score = 0
        }
        return score + Double(getClassWeight(element, flags: flags))
    }

    static func calculateContentScore(_ element: Element, linkDensityModifier: Double) -> Double {
        let text = DOMUtils.getInnerText(element, normalizeSpaces: false)
        guard text.utf8.count >= 25 else { return 0 }
        let commaCount = text.filter { ",،﹐､，；;⸲⹁⸴⹉⹌".contains($0) }.count
        var score = 1.0 + Double(commaCount)
        score += min(Double(text.utf8.count) / 100.0, 3.0)
        score *= 1.0 - DOMUtils.linkDensity(element) + linkDensityModifier
        return score
    }

    static func getContentScore(_ element: Element, linkDensityModifier: Double = 0) -> Double {
        initializeNodeScore(element, flags: [.weightClasses]) + calculateContentScore(element, linkDensityModifier: linkDensityModifier)
    }

    static func isValidByline(_ element: Element, matchString: String) -> Bool {
        let rel = ((try? element.attr("rel")) ?? "").lowercased()
        let itemprop = ((try? element.attr("itemprop")) ?? "").lowercased()
        let length = DOMUtils.getInnerText(element, normalizeSpaces: false).utf8.count
        return (rel == "author" || itemprop.contains("author") || matches(matchString, Constants.regexps.byline)) && length > 0 && length < 100
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        pattern.split(separator: "|").contains { value.range(of: String($0), options: [.caseInsensitive, .regularExpression]) != nil }
    }
}
