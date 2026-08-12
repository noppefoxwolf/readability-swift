import SwiftSoup

enum Scoring {
    static func getClassWeight(_ element: Element, flags: ParseFlags = [.weightClasses]) -> Int {
        guard flags.contains(.weightClasses) else { return 0 }
        var weight = 0
        for attribute in ["class", "id"] {
            let value = DOMUtils.attribute(attribute, of: element).lowercased()
            guard !value.isEmpty else { continue }
            if matches(value, Constants.negative) {
                weight -= 25
            } else if matches(value, Constants.positive) {
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

    static func calculateContentScore(_ element: Element, linkDensityModifier: Double) throws -> Double {
        let text = DOMUtils.getInnerText(element, normalizeSpaces: false)
        // readabilityrs scores Rust str::len() values, which are UTF-8 bytes.
        // String.count would change thresholds for non-ASCII articles.
        guard text.utf8.count >= 25 else { return 0 }
        let commaCount = text.filter { ",،﹐､，；;⸲⹁⸴⹉⹌".contains($0) }.count
        var score = 1.0 + Double(commaCount)
        score += min(Double(text.utf8.count) / 100.0, 3.0)
        score *= 1.0 - (try DOMUtils.linkDensity(element)) + linkDensityModifier
        return score
    }

    static func getContentScore(_ element: Element, linkDensityModifier: Double = 0) throws -> Double {
        try initializeNodeScore(element, flags: [.weightClasses]) + calculateContentScore(element, linkDensityModifier: linkDensityModifier)
    }

    static func isValidByline(_ element: Element, matchString: String) -> Bool {
        let rel = DOMUtils.attribute("rel", of: element).lowercased()
        let itemprop = DOMUtils.attribute("itemprop", of: element).lowercased()
        let length = DOMUtils.getInnerText(element, normalizeSpaces: false).utf8.count
        return (rel == "author" || itemprop.contains("author") || matches(matchString, Constants.byline)) && length > 0 && length < 100
    }

    private static func matches(_ value: String, _ regex: Regex<Substring>) -> Bool {
        value.firstMatch(of: regex) != nil
    }
}
