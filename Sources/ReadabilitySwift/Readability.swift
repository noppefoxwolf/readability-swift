import Foundation
import SwiftSoup

/// Main Readability parser. It follows the same preprocessing, extraction,
/// metadata, and post-processing stages as readabilityrs.
public final class Readability {
    private let document: Document
    private let html: String
    private let baseURL: URL?
    public let options: ReadabilityOptions

    public init(_ html: String, baseURL: URL? = nil, options: ReadabilityOptions = .init()) throws {
        self.document = try DOMUtils.parse(html)
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

    public func parse() throws -> Article {
        let jsonLD = options.disableJSONLD ? Metadata() : MetadataExtractor.getJSONLD(document)
        let metadata = MetadataExtractor.getArticleMetadata(document, jsonLD: jsonLD)

        let preprocessedHTML = Cleaner.prepDocument(html)
        guard let preprocessedDocument = try? DOMUtils.parse(preprocessedHTML) else {
            throw ReadabilityError.parsingFailed("Unable to parse the preprocessed HTML")
        }
        Cleaner.removeUnsafeElements(from: preprocessedDocument)
        let extraction = ContentExtractor.grabArticle(preprocessedDocument, options: options)
        let extracted: String
        // readabilityrs flattens extraction errors and no-content into None.
        // The Swift API is throwing, so preserve both states as typed errors
        // instead of silently returning an optional Article.
        switch extraction {
        case let .success(value?):
            extracted = value
        case .success(nil):
            throw ReadabilityError.noContentFound
        case let .failure(error):
            throw error
        }

        let lightHTML: String
        switch Cleaner.cleanArticleContentLight(extracted) {
        case let .success(value): lightHTML = value
        case let .failure(error): throw error
        }
        var preparedHTML = PostProcessor.prepArticle(
            lightHTML,
            cleanStyles: options.cleanStyles,
            cleanWhitespace: options.cleanWhitespace,
            keepClasses: options.keepClasses,
            classesToPreserve: options.classesToPreserve
        )
        let extractedTitle = metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? titleFromContent(extracted)
        if options.removeTitleFromContent, let title = extractedTitle {
            preparedHTML = PostProcessor.removeTitleFromContent(preparedHTML, title: title)
        }
        let cleanedHTML: String
        switch Cleaner.cleanArticleContent(
            preparedHTML,
            allowedVideoRegex: options.allowedVideoRegex
        ) {
        case let .success(value): cleanedHTML = value
        case let .failure(error): throw error
        }

        let text = extractText(from: cleanedHTML)
        guard !text.isEmpty else { throw ReadabilityError.noContentFound }
        let titleValue = extractedTitle ?? titleFromContent(cleanedHTML) ?? ""
        let title: String? = titleValue
        let cleanedExcerpt = firstParagraph(from: cleanedHTML)
        let excerpt = metadata.excerpt
            ?? cleanedExcerpt.flatMap { paragraphPreservingSourceWhitespace($0, in: extracted) } ?? cleanedExcerpt
            ?? excerptFromText(text)
        var markdownOptions = options.markdownOptions ?? MarkdownOptions()
        markdownOptions.sanitizeURLs = options.sanitizeContent
        let markdown = options.outputMarkdown ? MarkdownConverter.htmlToMarkdown(cleanedHTML, options: markdownOptions, title: metadata.title) : nil
        return Article(
            title: title,
            content: cleanedHTML,
            textContent: text,
            // readabilityrs exposes Rust str::len(), i.e. UTF-8 bytes.
            length: text.utf8.count,
            excerpt: excerpt,
            byline: metadata.byline,
            image: metadata.image,
            dir: DOMUtils.articleDirection(document) ?? metadata.dir,
            siteName: metadata.siteName,
            lang: metadata.lang,
            publishedTime: metadata.publishedTime,
            rawContent: extracted,
            markdownContent: markdown
        )
    }

    private func extractText(from html: String) -> String {
        guard let document = try? DOMUtils.parse(html), let body = document.body() else { return "" }
        return rawText(from: body)
    }

    private func rawText(from element: Element) -> String {
        element.getChildNodes().reduce(into: "") { result, node in
            if let text = node as? TextNode { result += text.getWholeText() }
            else if let child = node as? Element { result += rawText(from: child) }
        }
    }

    private func titleFromContent(_ html: String) -> String? {
        guard let document = try? DOMUtils.parse(html), let elements = try? document.select("h1,h2"), let title = elements.first() else { return nil }
        let value = DOMUtils.normalizeWhitespace(DOMUtils.textContent(title))
        return value.isEmpty ? nil : value
    }

    private func firstParagraph(from html: String) -> String? {
        guard let document = try? DOMUtils.parse(html) else { return nil }
        guard let elements = try? document.select("p") else { return nil }
        for element in elements {
            let value = rawText(from: element).trimmed()
            guard value.utf8.count >= 25 else { continue }
            guard !Utils.looksLikeBracketMenu(value) else { continue }

            let className = ((try? element.attr("class")) ?? "").lowercased()
            let idName = ((try? element.attr("id")) ?? "").lowercased()
            let noiseClassNames = ["hatnote", "shortdescription", "metadata", "navbox", "dablink", "noprint", "mwe-math-element", "mw-empty-elt"]
            if noiseClassNames.contains(where: { className.contains($0) || idName.contains($0) }) { continue }
            if ((try? element.attr("role")) ?? "").lowercased() == "note" { continue }
            let lower = value.lowercased()
            if ["see also", "coordinates", "navigation menu", "external links", "further reading"].contains(where: { lower.hasPrefix($0) }) { continue }
            if DOMUtils.linkDensity(element) > 0.8 { continue }
            if Utils.looksLikeByline(value) || className.contains("byline") || className.contains("author") || idName.contains("byline") || idName.contains("author") { continue }
            return value
        }
        return nil
    }

    private func excerptFromText(_ text: String) -> String? {
        let cleaned = text.trimmed()
        guard !cleaned.isEmpty else { return nil }
        for paragraph in SwiftRegex.split(cleaned, pattern: "\n\n") {
            let value = paragraph.trimmed()
            guard value.utf8.count >= 80, !Utils.looksLikeBracketMenu(value) else { continue }
            return truncateText(value, maximumLength: 300)
        }
        guard !Utils.looksLikeBracketMenu(cleaned), cleaned.utf8.count > 40 else { return nil }
        return truncateText(cleaned, maximumLength: 300)
    }

    private func paragraphPreservingSourceWhitespace(_ excerpt: String, in html: String) -> String? {
        guard let document = try? DOMUtils.parse(html), let elements = try? document.select("p") else { return nil }
        let normalizedExcerpt = excerpt.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        for element in elements {
            let value = rawText(from: element).trimmed()
            let normalizedValue = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            if normalizedValue == normalizedExcerpt {
                return SwiftRegex.replacing(in: value, pattern: "\\n[ \\t]+", with: "\n ")
            }
        }
        return nil
    }

    private func truncateText(_ text: String, maximumLength: Int) -> String {
        let characters = Array(text)
        guard characters.count > maximumLength else { return text }
        let prefix = String(characters.prefix(maximumLength))
        guard let boundary = prefix.lastIndex(where: { $0.isWhitespace }) else { return prefix.trimmed() }
        return String(prefix[..<boundary]).trimmed()
    }

}
