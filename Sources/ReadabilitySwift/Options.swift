public enum HTMLClassPolicy: Sendable, Hashable {
    /// Removes every HTML class from extracted content.
    case removeAll

    /// Keeps only the listed class names.
    case preserve(Set<String>)

    /// Keeps every HTML class from the source document.
    case keepAll

    func retainedClasses(from value: String) -> String? {
        let classes = value.split(whereSeparator: \.isWhitespace).map(String.init)
        let retained: [String]
        switch self {
        case .removeAll:
            retained = []
        case let .preserve(preservedClasses):
            retained = classes.filter(preservedClasses.contains)
        case .keepAll:
            retained = classes
        }
        return retained.isEmpty ? nil : retained.joined(separator: " ")
    }
}

public struct ReadabilityOptions {
    public var maximumElementCount: Int
    public var topCandidateCount: Int
    public var characterThreshold: Int
    public var classPolicy: HTMLClassPolicy
    public var extractsJSONLD: Bool
    public var allowedVideoRegex: Regex<Substring>?
    public var linkDensityModifier: Double
    public var removesTitleFromContent: Bool
    public var cleansStyles: Bool
    public var cleansWhitespace: Bool
    public var markdown: MarkdownOptions?
    public var sanitizesContent: Bool

    public init(
        maximumElementCount: Int = 0,
        topCandidateCount: Int = 5,
        characterThreshold: Int = 500,
        classPolicy: HTMLClassPolicy = .preserve(["page"]),
        extractsJSONLD: Bool = true,
        allowedVideoRegex: Regex<Substring>? = nil,
        linkDensityModifier: Double = 0,
        removesTitleFromContent: Bool = false,
        cleansStyles: Bool = true,
        cleansWhitespace: Bool = true,
        markdown: MarkdownOptions? = nil,
        sanitizesContent: Bool = false
    ) {
        self.maximumElementCount = maximumElementCount
        self.topCandidateCount = topCandidateCount
        self.characterThreshold = characterThreshold
        self.classPolicy = classPolicy
        self.extractsJSONLD = extractsJSONLD
        self.allowedVideoRegex = allowedVideoRegex
        self.linkDensityModifier = linkDensityModifier
        self.removesTitleFromContent = removesTitleFromContent
        self.cleansStyles = cleansStyles
        self.cleansWhitespace = cleansWhitespace
        self.markdown = markdown
        self.sanitizesContent = sanitizesContent
    }
}
