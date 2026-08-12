import Foundation

public struct ReadabilityOptions {
    public var debug: Bool
    public var maxElemsToParse: Int
    public var nbTopCandidates: Int
    public var charThreshold: Int
    public var classesToPreserve: [String]
    public var keepClasses: Bool
    public var disableJSONLD: Bool
    public var allowedVideoRegex: NSRegularExpression?
    public var linkDensityModifier: Double
    public var removeTitleFromContent: Bool
    public var cleanStyles: Bool
    public var cleanWhitespace: Bool
    public var outputMarkdown: Bool
    public var markdownOptions: MarkdownOptions?
    public var sanitizeContent: Bool

    public init(
        debug: Bool = false,
        maxElemsToParse: Int = 0,
        nbTopCandidates: Int = 5,
        charThreshold: Int = 500,
        classesToPreserve: [String] = ["page"],
        keepClasses: Bool = false,
        disableJSONLD: Bool = false,
        allowedVideoRegex: NSRegularExpression? = nil,
        linkDensityModifier: Double = 0,
        removeTitleFromContent: Bool = false,
        cleanStyles: Bool = true,
        cleanWhitespace: Bool = true,
        outputMarkdown: Bool = false,
        markdownOptions: MarkdownOptions? = nil,
        sanitizeContent: Bool = false
    ) {
        self.debug = debug
        self.maxElemsToParse = maxElemsToParse
        self.nbTopCandidates = nbTopCandidates
        self.charThreshold = charThreshold
        self.classesToPreserve = classesToPreserve
        self.keepClasses = keepClasses
        self.disableJSONLD = disableJSONLD
        self.allowedVideoRegex = allowedVideoRegex
        self.linkDensityModifier = linkDensityModifier
        self.removeTitleFromContent = removeTitleFromContent
        self.cleanStyles = cleanStyles
        self.cleanWhitespace = cleanWhitespace
        self.outputMarkdown = outputMarkdown
        self.markdownOptions = markdownOptions
        self.sanitizeContent = sanitizeContent
    }

}
