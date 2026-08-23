import Testing
@testable import ReadabilitySwift

@Test func cachedRegexPredicatesRetainTheirMatchingBehavior() {
    #expect(Constants.isUnlikelyCandidate("sidebar"))
    #expect(Constants.isMaybeCandidate("main-content"))
    #expect(Constants.isPositive("article-body"))
    #expect(Constants.isNegative("sidebar-widget"))
    #expect(Constants.isByline("writtenby"))
    #expect(Constants.isVideo("https://www.youtube.com/embed/example"))
    #expect(Constants.isAdvertisementWord("advertisement"))
    #expect(Constants.isLoadingWord("正在加载…"))
    #expect(Constants.isJSONLDArticleType("NewsArticle"))
}
