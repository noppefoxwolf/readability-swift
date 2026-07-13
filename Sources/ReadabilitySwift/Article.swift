/// Article data structure representing the parsed output.
public struct Article: Codable, Equatable {
    public let title: String?
    public let content: String?
    public let textContent: String?
    public let length: Int
    public let excerpt: String?
    public let byline: String?
    public let image: String?
    public let dir: String?
    public let siteName: String?
    public let lang: String?
    public let publishedTime: String?
    public let rawContent: String?
    public let markdownContent: String?

    public init(
        title: String? = nil,
        content: String? = nil,
        textContent: String? = nil,
        length: Int = 0,
        excerpt: String? = nil,
        byline: String? = nil,
        image: String? = nil,
        dir: String? = nil,
        siteName: String? = nil,
        lang: String? = nil,
        publishedTime: String? = nil,
        rawContent: String? = nil,
        markdownContent: String? = nil
    ) {
        self.title = title
        self.content = content
        self.textContent = textContent
        self.length = length
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
}
