import Synchronization

struct ParseFlags: OptionSet, Sendable {
    let rawValue: UInt32

    init(rawValue: UInt32) { self.rawValue = rawValue }
    static let stripUnlikelies = ParseFlags(rawValue: 1)
    static let weightClasses = ParseFlags(rawValue: 2)
}

enum Constants {
    static let defaultTagsToScore = ["SECTION", "H2", "H3", "H4", "H5", "H6", "P", "TD", "PRE", "DIV"]
    static let divToPElems = ["BLOCKQUOTE", "DL", "DIV", "IMG", "OL", "P", "PRE", "TABLE", "UL"]
    static let phrasingElems = ["ABBR", "AUDIO", "B", "BDO", "BR", "BUTTON", "CITE", "CODE", "DATA", "DATALIST", "DFN", "EM", "EMBED", "I", "IMG", "INPUT", "KBD", "LABEL", "MARK", "MATH", "METER", "NOSCRIPT", "OBJECT", "OUTPUT", "PROGRESS", "Q", "RUBY", "SAMP", "SCRIPT", "SELECT", "SMALL", "SPAN", "STRONG", "SUB", "SUP", "TIME", "VAR", "WBR"]

    private static let regexes = Mutex(RegexPatterns())

    static func isUnlikelyCandidate(_ value: String) -> Bool {
        regexes.withLock { value.firstMatch(of: $0.unlikelyCandidates) != nil }
    }

    static func isMaybeCandidate(_ value: String) -> Bool {
        regexes.withLock { value.firstMatch(of: $0.okMaybeItsACandidate) != nil }
    }

    static func isPositive(_ value: String) -> Bool {
        regexes.withLock { value.firstMatch(of: $0.positive) != nil }
    }

    static func isNegative(_ value: String) -> Bool {
        regexes.withLock { value.firstMatch(of: $0.negative) != nil }
    }

    static func isByline(_ value: String) -> Bool {
        regexes.withLock { value.firstMatch(of: $0.byline) != nil }
    }

    static func isVideo(_ value: String) -> Bool {
        regexes.withLock { value.firstMatch(of: $0.videos) != nil }
    }

    static func isAdvertisementWord(_ value: String) -> Bool {
        regexes.withLock { value.firstMatch(of: $0.adWords) != nil }
    }

    static func isLoadingWord(_ value: String) -> Bool {
        regexes.withLock { value.firstMatch(of: $0.loadingWords) != nil }
    }

    static func isJSONLDArticleType(_ value: String) -> Bool {
        regexes.withLock { value.wholeMatch(of: $0.jsonLDArticleTypes) != nil }
    }
}

private struct RegexPatterns {
    let unlikelyCandidates = #/(?i)-ad-|ai2html|banner|breadcrumbs|combx|comment|community|cover-wrap|disqus|extra|footer|gdpr|header|legends|menu|related|remark|replies|rss|shoutbox|sidebar|skyscraper|social|sponsor|supplemental|ad-break|agegate|pagination|pager|popup|yom-remote/#
    let okMaybeItsACandidate = /(?i)and|article|body|column|content|main|mathjax|shadow/
    let positive = /(?i)article|body|content|entry|hentry|h-entry|main|page|pagination|post|text|blog|story/
    let negative = #/(?i)-ad-|hidden|^hid$| hid$| hid |^hid |banner|combx|comment|com-|contact|footer|gdpr|masthead|media|meta|outbrain|promo|related|scroll|share|shoutbox|sidebar|skyscraper|sponsor|shopping|tags|widget/#
    let byline = /(?i)byline|author|dateline|writtenby|p-author/
    let videos = #/(?i)(?:dailymotion|youtube|youtube-nocookie|player\.vimeo|v\.qq|bilibili|live\.bilibili)\.com/#
    let adWords = #/(?i)^(?:ad(?:vertising|vertisement)?|pub(?:licité)?|werbung|广告|реклама|anuncio)$/#
    let loadingWords = #/(?i)^(?:(?:loading|正在加载|загрузка|chargement|cargando)(?:…|\.\.\.)?)$/#
    let jsonLDArticleTypes = #/(?i)^(?:Article|AdvertiserContentArticle|NewsArticle|AnalysisNewsArticle|OpinionNewsArticle|ReportageNewsArticle|ReviewNewsArticle|ScholarlyArticle|SocialMediaPosting|BlogPosting|LiveBlogPosting|DiscussionForumPosting|TechArticle|APIReference)$/#
}
