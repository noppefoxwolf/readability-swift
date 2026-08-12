import Foundation

/// Main Readability parser. It follows the same preprocessing, extraction,
/// metadata, and post-processing stages as readabilityrs.
public struct Readability {
    private let html: String
    private let baseURL: URL?
    public let options: ReadabilityOptions

    public init(_ html: String, baseURL: URL? = nil, options: ReadabilityOptions = .init()) throws {
        self.html = html
        // readabilityrs accepts a raw string and validates it with url::Url.
        // This API accepts an already-parsed Foundation.URL, so the remaining
        // equivalent validation is that the URL is absolute.
        if let baseURL, baseURL.scheme?.isEmpty != false {
            throw ReadabilityError.invalidURL(baseURL.absoluteString)
        }
        self.baseURL = baseURL
        self.options = options
    }

    public static func parse(
        _ html: String,
        baseURL: URL? = nil,
        options: ReadabilityOptions = .init()
    ) throws -> Article {
        try Readability(html, baseURL: baseURL, options: options).parse()
    }

    public func parse() throws -> Article {
        let baseURI = baseURL?.absoluteString
        let document = try DOMUtils.parse(html, baseURI: baseURI)
        let jsonLD: Metadata
        if options.extractsJSONLD {
            jsonLD = try MetadataExtractor.getJSONLD(document)
        } else {
            jsonLD = Metadata()
        }
        let metadata = try MetadataExtractor.getArticleMetadata(document, jsonLD: jsonLD)

        let preprocessedHTML = Cleaner.prepDocument(html)
        let preprocessedDocument = try DOMUtils.parse(preprocessedHTML, baseURI: baseURI)
        try Cleaner.removeUnsafeElements(from: preprocessedDocument)
        guard let extracted = try ContentExtractor.grabArticle(
            preprocessedDocument,
            options: options,
            resolvesRelativeURLs: baseURL != nil
        ) else {
            throw ReadabilityError.noContentFound
        }

        let lightHTML = try Cleaner.cleanArticleContentLight(extracted)
        var preparedHTML = PostProcessor.prepArticle(
            lightHTML,
            cleanStyles: options.cleansStyles,
            cleanWhitespace: options.cleansWhitespace
        )
        let metadataTitle = metadata.title.flatMap { $0.isEmpty ? nil : $0 }
        let extractedTitle: String?
        if let metadataTitle {
            extractedTitle = metadataTitle
        } else {
            extractedTitle = try titleFromContent(extracted)
        }
        if options.removesTitleFromContent, let title = extractedTitle {
            preparedHTML = try PostProcessor.removeTitleFromContent(preparedHTML, title: title)
        }
        let cleanedHTML = try Cleaner.cleanArticleContent(
            preparedHTML,
            allowedVideoRegex: options.allowedVideoRegex
        )

        let text = try extractText(from: cleanedHTML)
        guard !text.isEmpty else { throw ReadabilityError.noContentFound }
        let title: String?
        if let extractedTitle {
            title = extractedTitle
        } else {
            title = try titleFromContent(cleanedHTML)
        }
        let cleanedExcerpt = try firstParagraph(from: cleanedHTML)
        let sourceExcerpt: String?
        if let cleanedExcerpt {
            sourceExcerpt = try paragraphPreservingSourceWhitespace(cleanedExcerpt, in: extracted)
        } else {
            sourceExcerpt = nil
        }
        let excerpt = metadata.excerpt ?? sourceExcerpt ?? cleanedExcerpt ?? excerptFromText(text)
        let markdown = try options.markdown.map {
            try MarkdownConverter.htmlToMarkdown(cleanedHTML, options: $0, title: metadata.title)
        }
        let finalHTML = try PostProcessor.applyClassPolicy(options.classPolicy, to: cleanedHTML)
        return Article(
            title: title,
            content: finalHTML,
            textContent: text,
            excerpt: excerpt,
            byline: metadata.byline,
            image: metadata.image,
            dir: try DOMUtils.articleDirection(document) ?? metadata.dir,
            siteName: metadata.siteName,
            lang: metadata.lang,
            publishedTime: metadata.publishedTime,
            rawContent: extracted,
            markdownContent: markdown
        )
    }

    private func extractText(from html: String) throws -> String {
        let document = try DOMUtils.parse(html)
        guard let body = document.body() else { return "" }
        return DOMUtils.textContent(body)
    }

    private func titleFromContent(_ html: String) throws -> String? {
        let document = try DOMUtils.parse(html)
        guard let title = try document.select("h1,h2").first() else { return nil }
        let value = DOMUtils.normalizeWhitespace(DOMUtils.textContent(title))
        return value.isEmpty ? nil : value
    }

    private func firstParagraph(from html: String) throws -> String? {
        let document = try DOMUtils.parse(html)
        let elements = try document.select("p")
        for element in elements {
            let value = DOMUtils.textContent(element).trimmed()
            guard value.utf8.count >= 25 else { continue }
            guard !Utils.looksLikeBracketMenu(value) else { continue }

            let className = DOMUtils.attribute("class", of: element).lowercased()
            let idName = DOMUtils.attribute("id", of: element).lowercased()
            let noiseClassNames = ["hatnote", "shortdescription", "metadata", "navbox", "dablink", "noprint", "mwe-math-element", "mw-empty-elt"]
            if noiseClassNames.contains(where: { className.contains($0) || idName.contains($0) }) { continue }
            if DOMUtils.attribute("role", of: element).lowercased() == "note" { continue }
            let lower = value.lowercased()
            if ["see also", "coordinates", "navigation menu", "external links", "further reading"].contains(where: { lower.hasPrefix($0) }) { continue }
            if try DOMUtils.linkDensity(element) > 0.8 { continue }
            if Utils.looksLikeByline(value) || className.contains("byline") || className.contains("author") || idName.contains("byline") || idName.contains("author") { continue }
            return value
        }
        return nil
    }

    private func excerptFromText(_ text: String) -> String? {
        let cleaned = text.trimmed()
        guard !cleaned.isEmpty else { return nil }
        for paragraph in cleaned.split(separator: "\n\n", omittingEmptySubsequences: false) {
            let value = paragraph.trimmed()
            guard value.utf8.count >= 80, !Utils.looksLikeBracketMenu(value) else { continue }
            return truncateText(value, maximumLength: 300)
        }
        guard !Utils.looksLikeBracketMenu(cleaned), cleaned.utf8.count > 40 else { return nil }
        return truncateText(cleaned, maximumLength: 300)
    }

    private func paragraphPreservingSourceWhitespace(_ excerpt: String, in html: String) throws -> String? {
        let document = try DOMUtils.parse(html)
        let elements = try document.select("p")
        let normalizedExcerpt = excerpt.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        for element in elements {
            let value = DOMUtils.textContent(element).trimmed()
            let normalizedValue = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            if normalizedValue == normalizedExcerpt {
                return value.replacing(/\n[ \t]+/, with: "\n ")
            }
        }
        return nil
    }

    private func truncateText(_ text: String, maximumLength: Int) -> String {
        guard let end = text.index(text.startIndex, offsetBy: maximumLength, limitedBy: text.endIndex),
              end < text.endIndex else { return text }
        let prefix = text[..<end]
        guard let boundary = prefix.lastIndex(where: \.isWhitespace) else { return prefix.trimmed() }
        return prefix[..<boundary].trimmed()
    }

}
