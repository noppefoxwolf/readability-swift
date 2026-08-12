public enum MarkdownHeadingStyle: String, Codable, CaseIterable, Sendable {
    case atx
    case setext
}

public enum MarkdownLinkStyle: String, Codable, CaseIterable, Sendable {
    case inline
    case reference
}

public struct MarkdownOptions: Codable, Hashable, Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case headingStyle
        case bulletCharacter
        case codeFence
        case emphasisDelimiter
        case strongDelimiter
        case linkStyle
        case preserveComplexTables
        case sanitizeURLs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headingStyle = try container.decode(MarkdownHeadingStyle.self, forKey: .headingStyle)
        bulletCharacter = try Self.decodeCharacter(forKey: .bulletCharacter, from: container)
        codeFence = try Self.decodeCharacter(forKey: .codeFence, from: container)
        emphasisDelimiter = try Self.decodeCharacter(forKey: .emphasisDelimiter, from: container)
        strongDelimiter = try container.decode(String.self, forKey: .strongDelimiter)
        linkStyle = try container.decode(MarkdownLinkStyle.self, forKey: .linkStyle)
        preserveComplexTables = try container.decode(Bool.self, forKey: .preserveComplexTables)
        sanitizeURLs = try container.decode(Bool.self, forKey: .sanitizeURLs)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(headingStyle, forKey: .headingStyle)
        try container.encode(String(bulletCharacter), forKey: .bulletCharacter)
        try container.encode(String(codeFence), forKey: .codeFence)
        try container.encode(String(emphasisDelimiter), forKey: .emphasisDelimiter)
        try container.encode(strongDelimiter, forKey: .strongDelimiter)
        try container.encode(linkStyle, forKey: .linkStyle)
        try container.encode(preserveComplexTables, forKey: .preserveComplexTables)
        try container.encode(sanitizeURLs, forKey: .sanitizeURLs)
    }

    private static func decodeCharacter(
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Character {
        let value = try container.decode(String.self, forKey: key)
        guard value.count == 1, let character = value.first else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Expected exactly one Character"
            )
        }
        return character
    }

}
