import Foundation
import SwiftSoup

struct Metadata {
    var title: String?
    var excerpt: String?
    var byline: String?
    var image: String?
    var dir: String?
    var siteName: String?
    var lang: String?
    var publishedTime: String?

    var isEmpty: Bool {
        title == nil && excerpt == nil && byline == nil && image == nil && siteName == nil && lang == nil && publishedTime == nil
    }
}

enum MetadataExtractor {
    static func getJSONLD(_ document: Document) throws -> Metadata {
        var metadata = Metadata()
        let scripts = try document.select("script[type='application/ld+json']")

        for script in scripts {
            let source = try script.html()
            let withoutCDATAStart = source.replacing(/(?i)^\s*<!\[CDATA\[/, with: "")
            let cleanedSource = withoutCDATAStart.replacing(/(?i)\]\]>\s*$/, with: "").trimmed()
            guard let data = cleanedSource.data(using: .utf8) else { continue }
            let object: Any
            do {
                object = try JSONSerialization.jsonObject(with: data)
            } catch {
                continue
            }
            // readabilityrs traverses serde_json::Value. Foundation exposes an
            // untyped Any graph instead, so articleDictionary and the helpers
            // below explicitly preserve the object/array/string cases used by
            // the Rust implementation.
            guard let value = articleDictionary(from: object) else { continue }

            let name = string(value["name"])
            let headline = string(value["headline"])
            let publisherName = (value["publisher"] as? [String: Any]).flatMap { string($0["name"]) }
            if metadata.title == nil {
                if let name, let publisherName, name.trimmed() == publisherName.trimmed() {
                    metadata.title = headline?.trimmed()
                } else {
                    metadata.title = (name ?? headline)?.trimmed()
                }
            }
            if metadata.byline == nil { metadata.byline = authorName(value["author"]) }
            if metadata.excerpt == nil { metadata.excerpt = string(value["description"])?.trimmed() }
            if metadata.siteName == nil, let publisher = value["publisher"] as? [String: Any] {
                metadata.siteName = string(publisher["name"])?.trimmed()
            }
            if metadata.publishedTime == nil { metadata.publishedTime = string(value["datePublished"])?.trimmed() }
            if metadata.image == nil { metadata.image = imageURL(value["image"]) ?? string(value["thumbnailUrl"]) }
        }
        return metadata
    }

    static func getArticleMetadata(_ document: Document, jsonLD: Metadata) throws -> Metadata {
        var metadata = jsonLD
        let metaTags = try document.select("meta")
        var values: [String: String] = [:]
        for meta in metaTags {
            let name = DOMUtils.attribute("name", of: meta).lowercased()
            let property = DOMUtils.attribute("property", of: meta).lowercased()
            let content = DOMUtils.attribute("content", of: meta).trimmed()
            guard !content.isEmpty else { continue }
            for key in property.split(whereSeparator: { $0.isWhitespace }) where !key.isEmpty {
                let propertyName = String(key).lowercased()
                if let canonical = canonicalPropertyName(propertyName) {
                    values[canonical] = content
                }
            }
            if !name.isEmpty, let canonical = canonicalName(name) { values[canonical] = content }
        }

        metadata.title = metadata.title ?? values["dc:title"] ?? values["dcterm:title"] ?? values["og:title"] ?? values["weibo:article:title"] ?? values["weibo:webpage:title"] ?? values["title"] ?? values["twitter:title"] ?? values["parsely-title"]
        metadata.excerpt = metadata.excerpt ?? values["dc:description"] ?? values["dcterm:description"] ?? values["og:description"] ?? values["weibo:article:description"] ?? values["weibo:webpage:description"] ?? values["description"] ?? values["twitter:description"]
        metadata.siteName = metadata.siteName ?? values["og:site_name"]
        let articleAuthor = ["article:author", "article:author_name"].compactMap { values[$0] }.first(where: { !Utils.isURL($0) })
        metadata.byline = metadata.byline ?? values["dc:creator"] ?? values["dcterm:creator"] ?? values["author"] ?? values["parsely-author"] ?? articleAuthor
        metadata.image = metadata.image ?? values["og:image:secure_url"] ?? values["og:image:url"] ?? values["og:image"] ?? values["twitter:image"] ?? values["thumbnail"] ?? values["image"]
        metadata.publishedTime = metadata.publishedTime ?? values["article:published_time"] ?? values["parsely-pub-date"]

        if let html = try document.select("html").first() {
            metadata.dir = nonEmpty(DOMUtils.attribute("dir", of: html))
            metadata.lang = nonEmpty(DOMUtils.attribute("lang", of: html))
        }
        if metadata.lang == nil {
            metadata.lang = try document.select("meta[http-equiv='Content-Language'], meta[http-equiv='content-language']")
                .compactMap { nonEmpty(DOMUtils.attribute("content", of: $0)) }.first
        }
        if metadata.lang == nil {
            metadata.lang = try document.select("meta[name='lang'], meta[name='language']")
                .compactMap { nonEmpty(DOMUtils.attribute("content", of: $0)) }.first
        }
        if metadata.image == nil {
            if let imageSource = try document.select("link[rel=image_src]").first() {
                metadata.image = nonEmpty(DOMUtils.attribute("href", of: imageSource))
            }
            if metadata.image == nil, let imageElement = try document.select("[itemprop=image]").first() {
                metadata.image = nonEmpty(DOMUtils.attribute("content", of: imageElement))
                    ?? nonEmpty(DOMUtils.attribute("src", of: imageElement))
                    ?? nonEmpty(DOMUtils.attribute("href", of: imageElement))
            }
        }
        let cleanedMetaByline = metadata.byline.flatMap { Utils.cleanBylineText(Utils.unescapeHTMLEntities($0)) }
        if let domByline = try findByline(in: document) {
            if let existing = cleanedMetaByline {
                if shouldPreferDOMByline(existing: existing, dom: domByline.text, highConfidence: domByline.highConfidence) { metadata.byline = domByline.text } else { metadata.byline = existing }
            } else {
                metadata.byline = domByline.text
            }
        } else {
            metadata.byline = cleanedMetaByline
        }
        if metadata.title == nil {
            metadata.title = try extractTitleFromDocument(document)
        }
        metadata.title = metadata.title.map(Utils.unescapeHTMLEntities)
        metadata.excerpt = metadata.excerpt.map(Utils.unescapeHTMLEntities).flatMap { value in
            let cleaned = value.trimmed()
            return cleaned.isEmpty || Utils.looksLikeBracketMenu(cleaned) ? nil : cleaned
        }
        metadata.siteName = metadata.siteName.map(Utils.unescapeHTMLEntities)
        metadata.publishedTime = metadata.publishedTime.map(Utils.unescapeHTMLEntities)
        metadata.image = metadata.image.map { Utils.unescapeHTMLEntities($0).trimmed() }.flatMap(nonEmpty)
        if let byline = metadata.byline, let siteName = metadata.siteName, Utils.isBylineRedundantWithSiteName(byline, siteName: siteName) {
            metadata.byline = nil
        }
        return metadata
    }

private struct DOMBylineCandidate {
    let text: String
    let highConfidence: Bool
}

private struct BylineContext {
    let isIgnorable: Bool
    let isNoise: Bool
}

    private static func findByline(in document: Document) throws -> DOMBylineCandidate? {
        if let standfirst = try findStandfirstByline(in: document) { return DOMBylineCandidate(text: standfirst, highConfidence: true) }
        let authorLinks = try document.select("a").filter { link in
            DOMUtils.attribute("rel", of: link).split(whereSeparator: { $0.isWhitespace }).contains { $0.lowercased() == "author" }
        }
        for element in authorLinks {
            if try isDroppedOrganizationByline(element) { return nil }
            if let value = try bylineCandidate(element, explicit: true) { return DOMBylineCandidate(text: value, highConfidence: true) }
        }
        for element in try document.select("[itemprop]") {
            let itemprop = DOMUtils.attribute("itemprop", of: element).lowercased()
            if itemprop.split(whereSeparator: { $0.isWhitespace }).contains("author") {
                if try isDroppedOrganizationByline(element) { return nil }
                if let value = try bylineCandidate(element, explicit: true) { return DOMBylineCandidate(text: value, highConfidence: true) }
            }
        }

        var fallback: DOMBylineCandidate?
        let patterns = [".byline", ".pb-byline", ".author", ".by", ".writer", ".article-author", ".post-author", ".entry-author", "#byline", "#author", "[class*=author]", "[class*=byline]"]
        for pattern in patterns {
            for element in try document.select(pattern) {
                let context = bylineContext(for: element)
                if context.isIgnorable || context.isNoise, !elementHasBylineKeyword(element) { continue }
                let text = try cleanedCandidateText(element)
                guard !text.isEmpty, text.utf8.count <= 100 else { continue }
                let caps = looksLikeCapsAuthor(text)
                if Scoring.isValidByline(element, matchString: DOMUtils.classAndID(element)) || Utils.looksLikeByline(text) || caps {
                    let cleaned = Utils.cleanBylineTextWithReason(text)
                    if case .droppedOrganization = cleaned { return nil }
                    guard case let .accepted(value) = cleaned else { continue }
                    let candidate = DOMBylineCandidate(text: value, highConfidence: elementHasExplicitBylineMarker(element))
                    if caps || Utils.looksLikeByline(text) { return candidate }
                    fallback = fallback ?? candidate
                }
            }
        }
        for element in try document.select("[class], [id]") {
            let context = bylineContext(for: element)
            guard !context.isIgnorable, !context.isNoise, elementHasBylineKeyword(element) else { continue }
            let text = try cleanedCandidateText(element)
            guard !text.isEmpty, text.utf8.count <= 120 else { continue }
            if Scoring.isValidByline(element, matchString: DOMUtils.classAndID(element)) || Utils.looksLikeByline(text) || looksLikeCapsAuthor(text) {
                guard let value = Utils.cleanBylineText(text) else { continue }
                let candidate = DOMBylineCandidate(text: value, highConfidence: false)
                if Scoring.isValidByline(element, matchString: DOMUtils.classAndID(element)) || Utils.looksLikeByline(text) || looksLikeCapsAuthor(text) { return candidate }
                fallback = fallback ?? candidate
            }
        }
        for element in try document.select("address") {
            let context = bylineContext(for: element)
            guard !context.isIgnorable, !context.isNoise else { continue }
            let text = try cleanedCandidateText(element)
            if text.utf8.count <= 100 && (Utils.looksLikeByline(text) || Scoring.isValidByline(element, matchString: text) || looksLikeCapsAuthor(text)) {
                guard let value = Utils.cleanBylineText(text) else { continue }
                let candidate = DOMBylineCandidate(text: value, highConfidence: false)
                if looksLikeCapsAuthor(text) || Utils.looksLikeByline(text) { return candidate }
                fallback = fallback ?? candidate
            }
        }
        for element in try document.select("p,div,span") {
            let context = bylineContext(for: element)
            guard !context.isIgnorable, !context.isNoise else { continue }
            let text = try cleanedCandidateText(element)
            guard text.utf8.count <= 120, Utils.looksLikeByline(text) || looksLikeCapsAuthor(text) else { continue }
            if !looksLikeDateline(text) {
                let cleaned = Utils.cleanBylineTextWithReason(text)
                if case .droppedOrganization = cleaned { return nil }
                if case let .accepted(value) = cleaned { return DOMBylineCandidate(text: value, highConfidence: false) }
            }
        }
        return fallback ?? nil
    }

    private static func bylineCandidate(_ element: Element, explicit: Bool) throws -> String? {
        let context = bylineContext(for: element)
        guard !context.isIgnorable, !context.isNoise else { return nil }
        if let parent = element.parent(), elementHasBylineKeyword(parent), !bylineContext(for: parent).isIgnorable, let value = Utils.cleanBylineText(try cleanedCandidateText(parent)) { return value }
        let text = try cleanedCandidateText(element)
        guard !text.isEmpty else { return nil }
        let match = DOMUtils.classAndID(element)
        guard explicit || Scoring.isValidByline(element, matchString: match) else { return nil }
        return Utils.cleanBylineText(text)
    }

    private static func isDroppedOrganizationByline(_ element: Element) throws -> Bool {
        let target = element.parent().flatMap { elementHasBylineKeyword($0) ? $0 : nil } ?? element
        if case .droppedOrganization = Utils.cleanBylineTextWithReason(try cleanedCandidateText(target)) { return true }
        return false
    }

    private static func cleanedCandidateText(_ element: Element) throws -> String {
        let raw = buildBylineText(element)
        let names = try childAuthorNames(element)
        let normalized = raw.trimmed()
        let prefersChildNames = names.isEmpty ? false : try shouldPreferChildNames(element, names: names, raw: raw)
        if prefersChildNames {
            return unique(names).joined(separator: ", ")
        }
        return normalized
    }

    private static func childAuthorNames(_ element: Element) throws -> [String] {
        var names: [String] = []
        names.append(contentsOf: (try element.select("[itemprop=name], [itemprop~=name]"))
            .map { DOMUtils.getInnerText($0).trimmed() }
            .filter { !$0.isEmpty })

        for anchor in try element.select("a") {
            let name = DOMUtils.getInnerText(anchor).trimmed()
            guard !name.isEmpty, Utils.looksLikeAuthorName(name) else { continue }
            let href = DOMUtils.attribute("href", of: anchor).lowercased()
            guard !href.hasPrefix("mailto:"), !href.contains("twitter.com"), !href.contains("facebook.com"), !href.contains("linkedin.com") else { continue }
            names.append(name)
        }
        return unique(names)
    }

    private static func shouldPreferChildNames(_ element: Element, names: [String], raw: String) throws -> Bool {
        guard !names.isEmpty else { return false }
        let authorish = ["authorinfo", "author-info"]
        if DOMUtils.ancestors(element, limit: 4).contains(where: { ancestor in
            let marker = DOMUtils.classAndID(ancestor).lowercased()
            return authorish.contains(where: marker.contains)
        }) { return true }

        let marker = DOMUtils.classAndID(element).lowercased()
        if authorish.contains(where: marker.contains) { return true }
        let section = DOMUtils.attribute("section", of: element).lowercased()
        if section.contains("author") { return true }

        var normalized = raw.lowercased()
        for name in names { normalized = normalized.replacing(name.lowercased(), with: " ") }
        normalized = normalized
            .replacing("\u{00a0}", with: " ")
            .replacing("\u{200B}", with: " ")
            .replacing("\r", with: " ")
            .replacing("\n", with: " ")
        for separator in ".,–—-|:;/()" {
            normalized = normalized.replacing(String(separator), with: " ")
        }
        let tokens = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if tokens.isEmpty { return true }
        let jobKeywords = ["reporter", "editor", "writer", "staff", "senior", "technologist", "correspondent", "columnist", "analyst", "producer", "anchor", "bureau", "desk", "spokesman", "spokeswoman", "spokesperson", "contributor", "team", "author"]
        if tokens.contains(where: jobKeywords.contains) { return true }
        let semanticNameAttribute = DOMUtils.attribute("itemprop", of: element)
            .split(whereSeparator: { $0.isWhitespace })
            .contains { $0.lowercased() == "name" }
        let semanticNameChild = try !element.select("[itemprop='name'], [itemprop~=name]").isEmpty()
        let semanticName = semanticNameAttribute || semanticNameChild
        return semanticName && tokens.allSatisfy { $0 == "by" }
    }

    private static func canonicalPropertyName(_ property: String) -> String? {
        let supported = [
            "article:author", "article:description", "article:published_time",
            "dc:creator", "dc:description", "dc:title", "dcterm:creator", "dcterm:description", "dcterm:title",
            "og:description", "og:image", "og:image:secure_url", "og:image:url", "og:site_name", "og:title",
            "twitter:description", "twitter:image", "twitter:title"
        ]
        if supported.contains(property) { return property }
        if let key = supported.first(where: { property.hasSuffix(":" + $0) }) { return key }
        return nil
    }

    private static func canonicalName(_ name: String) -> String? {
        let normalized = name.lowercased().replacing(" ", with: "").replacing(".", with: ":")
        let suffixes = ["author", "author_name", "creator", "pub-date", "description", "title", "site_name", "image", "thumbnail"]
        if suffixes.contains(normalized) { return normalized }
        if normalized.hasPrefix("parsely-") {
            let suffix = String(normalized.dropFirst("parsely-".count))
            if suffixes.contains(suffix) { return normalized }
        }
        let prefixes = ["article", "dc", "dcterm", "og", "twitter", "parsely", "weibo:article", "weibo:webpage"]
        for prefix in prefixes where normalized.hasPrefix(prefix) {
            let separator = normalized.dropFirst(prefix.count).first
            if separator == ":" || separator == "-" {
                let suffix = String(normalized.dropFirst(prefix.count + 1))
                if suffixes.contains(suffix) { return "\(prefix):\(suffix)" }
            }
        }
        return nil
    }

    private static func buildBylineText(_ element: Element) -> String {
        element.getChildNodes().reduce(into: "") { result, node in
            if let text = node as? TextNode {
                let wholeText = text.getWholeText()
                result += result.last == "\n" ? stripIntermediateNewline(wholeText) : wholeText
            }
            else if let child = node as? Element {
                if child.tagName().lowercased() == "br" { result += "\n" }
                result += buildBylineText(child)
            }
        }
    }

    private static func stripIntermediateNewline(_ text: String) -> String {
        var index = text.startIndex
        while index < text.endIndex, text[index].isWhitespace, text[index] != "\n" {
            text.formIndex(after: &index)
        }
        guard index < text.endIndex, text[index] == "\n" else { return text }
        return String(text[..<index]) + String(text[text.index(after: index)...])
    }

    private static func unique(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values where !result.contains(where: { $0.lowercased() == value.lowercased() }) { result.append(value) }
        return result
    }

    private static func findStandfirstByline(in document: Document) throws -> String? {
        for element in try document.select("em.byline, [class*=byline]") {
            guard DOMUtils.ancestors(element, limit: 5).contains(where: { DOMUtils.classAndID($0).lowercased().contains("standfirst") }) else { continue }
            let text = try cleanedCandidateText(element)
            if looksLikeCapsAuthor(text) { return Utils.cleanBylineText(text) }
        }
        return nil
    }

    private static let ignorableBylineKeywords = [
        "post-footer", "entry-footer", "article-footer", "section-footer", "postmeta", "meta-footer", "footer",
        "profile", "sidebar", "widget", "comment", "bio", "related-post", "user-bylines", "byline__body",
        "byline__title", "post-info", "entry-byline", "entry-author", "assetauthor", "contentpromo", "promo",
        "asset-author", "videopromo", "poponscroll", "most-popular", "popular-stories", "videoslide",
        "video-container", "card-box", "article-view-box", "cardbox", "article-content", "story-info"
    ]

    private static let noiseBylineKeywords = [
        "videopromo", "videoslide", "video-slide", "video-module", "poponscroll", "contentpromo", "promo",
        "popular", "most-popular", "popular-stories", "more-stories", "related", "recirc", "recommend",
        "newsletter", "signup", "asset", "social", "share", "gallery", "slideshow", "indepth",
        "indepth-module", "hot_stats", "hot-stats", "trending-badge", "views"
    ]

    private static func bylineContext(for element: Element) -> BylineContext {
        var isIgnorable = false
        var isNoise = false
        var ancestor = element.parent()
        var depth = 0

        while let current = ancestor, depth < 16 {
            let marker = DOMUtils.classAndID(current).lowercased()
            if !isIgnorable {
                let tag = current.tagName().lowercased()
                isIgnorable = ["footer", "aside", "nav"].contains(tag)
                    || ignorableBylineKeywords.contains(where: marker.contains)
            }
            if !isNoise {
                isNoise = noiseBylineKeywords.contains(where: marker.contains)
            }
            if isIgnorable && isNoise { break }
            ancestor = current.parent()
            depth += 1
        }

        if !isIgnorable {
            let marker = DOMUtils.classAndID(element).lowercased()
            isIgnorable = ignorableBylineKeywords.contains(where: marker.contains)
        }
        return BylineContext(isIgnorable: isIgnorable, isNoise: isNoise)
    }

    private static func elementHasBylineKeyword(_ element: Element) -> Bool {
        let marker = DOMUtils.classAndID(element).lowercased()
        return ["byline", "author", "writer", "credit"].contains(where: marker.contains)
    }

    private static func elementHasExplicitBylineMarker(_ element: Element) -> Bool {
        let marker = DOMUtils.classAndID(element).lowercased()
        return marker.contains("byline")
    }

    private static func looksLikeCapsAuthor(_ text: String) -> Bool {
        let value = text.trimmed()
        guard value.contains(where: { $0.isWhitespace }) else { return false }
        let letters = value.filter(\.isLetter)
        guard letters.count >= 3 else { return false }
        let noise = ["views", "view", "votes", "vote", "post", "posts", "yes", "no", "hot", "stats", "trending", "share", "sections"]
        guard !value.split(whereSeparator: { $0.isWhitespace }).contains(where: { noise.contains($0.trimmed(where: \.isPunctuation).lowercased()) }) else { return false }
        return letters.filter(\.isUppercase).count * 10 >= letters.count * 8
    }

    private static func looksLikeDateline(_ text: String) -> Bool {
        let value = text.trimmed { "-–— ".contains($0) }
        guard value.utf8.count <= 40, !value.isEmpty else { return false }
        let words = value.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "—" || $0 == "-" })
        return !words.isEmpty && words.allSatisfy { !$0.contains(where: { $0.isLowercase }) && $0.contains(where: { $0.isLetter }) }
    }

    private static func shouldPreferDOMByline(existing: String, dom: String, highConfidence: Bool) -> Bool {
        let existingValue = existing.trimmed()
        let domValue = dom.trimmed()
        guard existingValue.lowercased() != domValue.lowercased() else { return false }
        if Utils.isBylineOrganizationCredit(existingValue) && !Utils.isBylineOrganizationCredit(domValue) { return true }
        if looksLikeDateline(existingValue) && !looksLikeDateline(domValue) { return true }
        if highConfidence && looksLikeCapsAuthor(domValue) && !looksLikeCapsAuthor(existingValue) { return true }
        let lowerExisting = existingValue.lowercased()
        let lowerDOM = domValue.lowercased()
        guard lowerDOM.contains(lowerExisting) else { return false }
        let remainder = lowerDOM.replacing(lowerExisting, with: "")
        let ignored = remainder.replacing(/[|_\-–—,.:()\[\]{}"']/, with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .filter { token in
                let value = String(token)
                let months = ["jan", "january", "feb", "february", "mar", "march", "apr", "april", "may", "jun", "june", "jul", "july", "aug", "august", "sep", "sept", "september", "oct", "october", "nov", "november", "dec", "december"]
                return !value.allSatisfy(\.isNumber) && !["by", "updated", "at", "am", "pm"].contains(value) && !months.contains(value)
            }
        return !ignored.isEmpty
    }

    private static func jsonDictionaries(from object: Any) -> [[String: Any]] {
        if let dictionary = object as? [String: Any] {
            var result = [dictionary]
            if let graph = dictionary["@graph"] { result.append(contentsOf: jsonDictionaries(from: graph)) }
            return result
        }
        if let array = object as? [Any] { return array.flatMap(jsonDictionaries(from:)) }
        return []
    }

    private static func articleDictionary(from object: Any) -> [String: Any]? {
        var value: [String: Any]
        if let array = object as? [Any] {
            guard let article = array.compactMap({ $0 as? [String: Any] }).first(where: { isArticleType($0["@type"]) }) else { return nil }
            value = article
        } else if let dictionary = object as? [String: Any] {
            value = dictionary
        } else {
            return nil
        }

        guard hasSchemaContext(value["@context"]) else { return nil }
        if value["@type"] == nil,
           let graph = value["@graph"] as? [Any],
           let article = graph.compactMap({ $0 as? [String: Any] }).first(where: { isArticleType($0["@type"]) }) {
            value = article
        }
        return isArticleType(value["@type"]) ? value : nil
    }

    private static func hasSchemaContext(_ value: Any?) -> Bool {
        if let context = value as? String {
            return context.wholeMatch(of: #/https?://schema\.org/?/#) != nil
        }
        if let context = value as? [String: Any], let vocabulary = context["@vocab"] as? String {
            return vocabulary.wholeMatch(of: #/https?://schema\.org/?/#) != nil
        }
        return false
    }

    private static func isArticleType(_ value: Any?) -> Bool {
        guard let type = value as? String else { return false }
        return Constants.isJSONLDArticleType(type)
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String { return nonEmpty(Utils.unescapeHTMLEntities(string)) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func authorName(_ value: Any?) -> String? {
        if let dictionary = value as? [String: Any] { return string(dictionary["name"]) }
        if let array = value as? [Any] {
            let names = array.compactMap { ($0 as? [String: Any]).flatMap { string($0["name"]) } }
            return nonEmpty(names.joined(separator: ", "))
        }
        return nil
    }

    private static func imageURL(_ value: Any?) -> String? {
        if let image = string(value) { return image }
        if let dictionary = value as? [String: Any] {
            if let url = string(dictionary["url"]) { return url }
            if let id = string(dictionary["@id"]), let parsed = URL(string: id), ["http", "https"].contains(parsed.scheme?.lowercased() ?? "") { return id }
        }
        if let array = value as? [Any] { return array.compactMap(imageURL).first }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func extractTitleFromDocument(_ document: Document) throws -> String? {
        guard let original = nonEmpty(try document.title())?.trimmed(), !original.isEmpty else { return nil }
        var current = original
        let separator = #/\s(?:\||-|–|—|\\|/|>|»)\s/#
        let separatorMatches = original.matches(of: separator)
        var hadHierarchicalSeparator = false
        if !separatorMatches.isEmpty {
            hadHierarchicalSeparator = original.firstMatch(of: #/\s[\\/>»]\s/#) != nil
            if let end = separatorMatches.last {
                current = String(original[..<end.range.lowerBound]).trimmed()
                if wordCount(current) < 3 {
                    current = original.replacing(#/(?i)^[^|\-–—\\/>»]*[|\-–—\\/>»]/#, with: "")
                }
            }
        } else if current.contains(": ") {
            let headingMatches = (try document.select("h1,h2")).map { DOMUtils.getInnerText($0) }
            if !headingMatches.contains(where: { $0 == current }) {
                if let colon = current.lastIndex(of: ":") {
                    let suffix = String(current[current.index(after: colon)...]).trimmed()
                    if wordCount(suffix) < 3, let first = current.firstIndex(of: ":") {
                        let before = String(current[..<first])
                        current = wordCount(before) > 5 ? original : String(current[current.index(after: first)...]).trimmed()
                    } else {
                        current = suffix
                    }
                }
            }
        } else if current.count > 150 || current.count < 15 {
            let headings = try document.select("h1")
            if headings.count == 1 { current = DOMUtils.getInnerText(headings[0]) }
        }
        current = Utils.normalizeWhitespace(current)
        if wordCount(current) <= 4 {
            let originalWordCount = wordCount(original.replacing(separator, with: " "))
            if !hadHierarchicalSeparator || wordCount(current) != originalWordCount - 1 { current = original }
        }
        return current
    }

    private static func wordCount(_ value: String) -> Int {
        value.split(whereSeparator: { $0.isWhitespace }).count
    }
}
