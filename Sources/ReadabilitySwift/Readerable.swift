import SwiftSoup

public struct ReaderableOptions: Hashable, Sendable {
    public var minimumContentLength: Int
    public var minimumScore: Double
    public var maximumElementCount: Int

    public init(minimumContentLength: Int = 140, minimumScore: Double = 20, maximumElementCount: Int = 0) {
        self.minimumContentLength = minimumContentLength
        self.minimumScore = minimumScore
        self.maximumElementCount = maximumElementCount
    }

}

public enum Readerable {
    public static func isProbablyReaderable(_ html: String, options: ReaderableOptions = .init()) -> Bool {
        let elements: SwiftSoup.Elements
        do {
            let document = try DOMUtils.parse(html)
            elements = try document.select("p,pre,article")
        } catch {
            return false
        }
        if options.maximumElementCount > 0 && elements.count > options.maximumElementCount { return false }
        var score = 0.0
        for element in elements {
            let text = DOMUtils.textContent(element).trimmed()
            // Rust str::len() is a UTF-8 byte count, not Swift's grapheme count.
            let textLength = text.utf8.count
            guard textLength >= options.minimumContentLength else { continue }
            score += Double(textLength - options.minimumContentLength).squareRoot()
            if score > options.minimumScore { return true }
        }
        return false
    }
}
