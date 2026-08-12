public enum MarkdownHeadingStyle: String, Equatable {
    case atx
    case setext
}

public enum MarkdownLinkStyle: String, Equatable {
    case inline
    case reference
}

public struct MarkdownOptions: Equatable {
    public var headingStyle: MarkdownHeadingStyle
    public var bulletCharacter: Character
    public var codeFence: Character
    public var emphasisDelimiter: Character
    public var strongDelimiter: String
    public var linkStyle: MarkdownLinkStyle
    public var preserveComplexTables: Bool
    public var sanitizeURLs: Bool

    public init(
        headingStyle: MarkdownHeadingStyle = .atx,
        bulletCharacter: Character = "-",
        codeFence: Character = "`",
        emphasisDelimiter: Character = "*",
        strongDelimiter: String = "**",
        linkStyle: MarkdownLinkStyle = .inline,
        preserveComplexTables: Bool = true,
        sanitizeURLs: Bool = false
    ) {
        self.headingStyle = headingStyle
        self.bulletCharacter = bulletCharacter
        self.codeFence = codeFence
        self.emphasisDelimiter = emphasisDelimiter
        self.strongDelimiter = strongDelimiter
        self.linkStyle = linkStyle
        self.preserveComplexTables = preserveComplexTables
        self.sanitizeURLs = sanitizeURLs
    }

}
