/// Article data structure representing a successfully parsed document.
public struct Article: Codable, Hashable, Sendable {
    public let title: String?
    public let content: String
    public let textContent: String
    public let excerpt: String?
    public let byline: String?
    public let image: String?
    public let dir: String?
    public let siteName: String?
    public let lang: String?
    public let publishedTime: String?
    public let rawContent: String
    public let markdownContent: String?

    /// The UTF-8 byte count used by readabilityrs compatibility thresholds.
    public var utf8Length: Int { textContent.utf8.count }

    @available(*, deprecated, renamed: "utf8Length")
    public var length: Int { utf8Length }

    public init(
        title: String? = nil,
        content: String,
        textContent: String,
        excerpt: String? = nil,
        byline: String? = nil,
        image: String? = nil,
        dir: String? = nil,
        siteName: String? = nil,
        lang: String? = nil,
        publishedTime: String? = nil,
        rawContent: String,
        markdownContent: String? = nil
    ) {
        self.title = title
        self.content = content
        self.textContent = textContent
        self.excerpt = excerpt
        self.byline = byline
        self.image = image
        self.dir = dir
        self.siteName = siteName
        self.lang = lang
        self.publishedTime = publishedTime
        self.rawContent = rawContent
        self.markdownContent = markdownContent
    }

    private enum CodingKeys: String, CodingKey {
        case title, content, textContent = "text_content", length, excerpt, byline, image, dir
        case siteName = "site_name", lang, publishedTime = "published_time"
        case rawContent = "raw_content", markdownContent = "markdown_content"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        textContent = try container.decode(String.self, forKey: .textContent)
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt)
        byline = try container.decodeIfPresent(String.self, forKey: .byline)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        dir = try container.decodeIfPresent(String.self, forKey: .dir)
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName)
        lang = try container.decodeIfPresent(String.self, forKey: .lang)
        publishedTime = try container.decodeIfPresent(String.self, forKey: .publishedTime)
        rawContent = try container.decode(String.self, forKey: .rawContent)
        markdownContent = try container.decodeIfPresent(String.self, forKey: .markdownContent)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(textContent, forKey: .textContent)
        try container.encode(utf8Length, forKey: .length)
        try container.encodeIfPresent(excerpt, forKey: .excerpt)
        try container.encodeIfPresent(byline, forKey: .byline)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(dir, forKey: .dir)
        try container.encodeIfPresent(siteName, forKey: .siteName)
        try container.encodeIfPresent(lang, forKey: .lang)
        try container.encodeIfPresent(publishedTime, forKey: .publishedTime)
        try container.encode(rawContent, forKey: .rawContent)
        try container.encodeIfPresent(markdownContent, forKey: .markdownContent)
    }
}
