import SwiftSoup

public struct ReaderableOptions {
    public var minContentLength: Int
    public var minScore: Double
    public var maxElemsToParse: Int

    public init(minContentLength: Int = 140, minScore: Double = 20, maxElemsToParse: Int = 0) {
        self.minContentLength = minContentLength
        self.minScore = minScore
        self.maxElemsToParse = maxElemsToParse
    }

}

public enum Readerable {
    public static func isProbablyReaderable(_ html: String, options: ReaderableOptions = .init()) -> Bool {
        guard let document = try? DOMUtils.parse(html) else { return false }
        let elements = (try? document.select("p,pre,article")) ?? SwiftSoup.Elements()
        if options.maxElemsToParse > 0 && elements.count > options.maxElemsToParse { return false }
        var score = 0.0
        for element in elements {
            let text = rawText(from: element).trimmed()
            // Rust str::len() is a UTF-8 byte count, not Swift's grapheme count.
            let textLength = text.utf8.count
            guard textLength >= options.minContentLength else { continue }
            score += Double(textLength - options.minContentLength).squareRoot()
            if score > options.minScore { return true }
        }
        return false
    }

    private static func rawText(from element: Element) -> String {
        element.getChildNodes().reduce(into: "") { result, node in
            if let text = node as? TextNode { result += text.getWholeText() }
            else if let child = node as? Element { result += rawText(from: child) }
        }
    }

}
