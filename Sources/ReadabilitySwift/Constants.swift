import Foundation

struct RegexPatterns: Sendable {
    let unlikelyCandidates = "-ad-|ai2html|banner|breadcrumbs|combx|comment|community|cover-wrap|disqus|extra|footer|gdpr|header|legends|menu|related|remark|replies|rss|shoutbox|sidebar|skyscraper|social|sponsor|supplemental|ad-break|agegate|pagination|pager|popup|yom-remote"
    let okMaybeItsACandidate = "and|article|body|column|content|main|mathjax|shadow"
    let positive = "article|body|content|entry|hentry|h-entry|main|page|pagination|post|text|blog|story"
    let negative = "-ad-|hidden|^hid$| hid$| hid |^hid |banner|combx|comment|com-|contact|footer|gdpr|masthead|media|meta|outbrain|promo|related|scroll|share|shoutbox|sidebar|skyscraper|sponsor|shopping|tags|widget"
    let byline = "byline|author|dateline|writtenby|p-author"
    let videos = "(dailymotion|youtube|youtube-nocookie|player.vimeo|v.qq|bilibili|live.bilibili).com"
    let hashURL = "^#.+"
    let commas = ",،﹐､，；;⸲⹁⸴⹉⹌"
    let adWords = "^(ad(vertising|vertisement)?|pub(licité)?|werbung|广告|реклама|anuncio)$"
    let loadingWords = "^((loading|正在加载|загрузка|chargement|cargando)(…|\\.\\.\\.)?)$"
    let jsonLDArticleTypes = "Article|AdvertiserContentArticle|NewsArticle|AnalysisNewsArticle|OpinionNewsArticle|ReportageNewsArticle|ReviewNewsArticle|ScholarlyArticle|SocialMediaPosting|BlogPosting|LiveBlogPosting|DiscussionForumPosting|TechArticle|APIReference"

    init() {}
}

struct ParseFlags: OptionSet, Sendable {
    let rawValue: UInt32

    init(rawValue: UInt32) { self.rawValue = rawValue }
    static let stripUnlikelies = ParseFlags(rawValue: 1)
    static let weightClasses = ParseFlags(rawValue: 2)
    static let cleanConditionally = ParseFlags(rawValue: 4)
}

enum Constants {
    static let defaultTagsToScore = ["SECTION", "H2", "H3", "H4", "H5", "H6", "P", "TD", "PRE", "DIV"]
    static let divToPElems = ["BLOCKQUOTE", "DL", "DIV", "IMG", "OL", "P", "PRE", "TABLE", "UL"]
    static let phrasingElems = ["ABBR", "AUDIO", "B", "BDO", "BR", "BUTTON", "CITE", "CODE", "DATA", "DATALIST", "DFN", "EM", "EMBED", "I", "IMG", "INPUT", "KBD", "LABEL", "MARK", "MATH", "METER", "NOSCRIPT", "OBJECT", "OUTPUT", "PROGRESS", "Q", "RUBY", "SAMP", "SCRIPT", "SELECT", "SMALL", "SPAN", "STRONG", "SUB", "SUP", "TIME", "VAR", "WBR"]
    static let regexps = RegexPatterns()
}
