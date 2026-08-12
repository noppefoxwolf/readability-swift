import Foundation
import Testing
@testable import ReadabilitySwift

@Test func articleExtraction() throws {
    let html = """
    <html lang="en"><head><title>Example Article | Example</title>
    <meta property="og:site_name" content="Example">
    <meta name="author" content="Ada Lovelace">
    </head><body><nav>Navigation and links</nav>
    <article><h1>Example Article</h1>
    <p>This is the first substantial paragraph of the article with enough text to be selected.</p>
    <p>This is the second substantial paragraph, and it contains an <a href="/source">important link</a>.</p>
    <script>should be removed</script></article></body></html>
    """

    let article = try Readability(html, baseURL: URL(string: "https://example.com/story")).parse()
    #expect(article.title == "Example Article | Example")
    #expect(article.byline == "Ada Lovelace")
    #expect(!article.content.contains("Navigation"))
    #expect(!article.content.contains("should be removed"))
    #expect(article.content.contains("https://example.com/source"))
    #expect(article.textContent.contains("first substantial paragraph"))
    #expect(article.utf8Length > 100)
}

@Test func unsafeElementsAreRemovedAfterHTMLParsing() throws {
    let html = """
    <article>
      <p>This substantial article paragraph remains readable after unsafe elements are removed from the parsed document.</p>
      <script>script text must not be scored</script >
      <style>style text must not be scored</style\n>
      <noscript>fallback text must not be scored</noscript>
      <template>template text must not be scored</template>
    </article>
    """
    let article = try Readability(html, options: .init(characterThreshold: 20)).parse()
    #expect(article.textContent.contains("substantial article paragraph"))
    #expect(!article.textContent.contains("must not be scored"))
}

@Test func optionsAndMarkdownOutput() throws {
    let html = "<article><h1>Title</h1><p>A paragraph with <strong>emphasis</strong>.</p><ul><li>One</li></ul></article>"
    let options = ReadabilityOptions(
        characterThreshold: 10,
        removesTitleFromContent: true,
        markdown: .init()
    )
    let article = try Readability(html, options: options).parse()
    #expect(!article.content.contains("<h1>"))
    #expect(article.markdownContent?.contains("**emphasis**") == true)
    #expect(article.markdownContent?.contains("- One") == true)
}

@Test func readerableAndTypedBaseURL() throws {
    let html = "<p>" + String(repeating: "This paragraph contains article content. ", count: 30) + "</p>"
    #expect(Readerable.isProbablyReaderable(html))
    let parser = try Readability(html, baseURL: URL(string: "https://example.com/story"))
    #expect(try !parser.parse().textContent.isEmpty)
    #expect(throws: ReadabilityError.invalidURL("/relative")) {
        _ = try Readability(html, baseURL: URL(string: "/relative"))
    }
}

@Test func parseReportsNoContent() {
    #expect(throws: ReadabilityError.noContentFound) {
        _ = try Readability("<html><body><nav>Navigation only</nav></body></html>").parse()
    }
}

@Test func jsonLDMetadataHasPriority() throws {
    let html = """
    <html><head><script type="application/ld+json">
    {"@context":"https://schema.org","@type":"NewsArticle","headline":"JSON-LD title","author":{"name":"Grace Hopper"},"datePublished":"2026-01-02","description":"A JSON-LD description"}
    </script><meta property="og:title" content="OpenGraph title"></head>
    <body><main><p>A substantial article paragraph with enough words for the content extractor to choose this main element.</p></main></body></html>
    """
    let article = try Readability(html).parse()
    #expect(article.title == "JSON-LD title")
    #expect(article.byline == "Grace Hopper")
    #expect(article.publishedTime == "2026-01-02")
    #expect(article.excerpt == "A JSON-LD description")
}

@Test func candidateScoringAggregatesArticleSiblings() throws {
    let html = """
    <html><body>
    <div class="sidebar"><a href="/one">One</a><a href="/two">Two</a><a href="/three">Three</a></div>
    <main id="article-content">
      <p>First article paragraph has enough text and punctuation, so it contributes a meaningful candidate score.</p>
      <p>Second article paragraph is a separate sibling that must be retained when the best candidate is selected.</p>
    </main>
    <p hidden>This hidden paragraph must not affect the result.</p>
    </body></html>
    """
    let article = try Readability(html).parse()
    #expect(article.textContent.contains("First article paragraph"))
    #expect(article.textContent.contains("Second article paragraph"))
    #expect(!article.textContent.contains("One Two Three"))
    #expect(!article.textContent.contains("hidden paragraph"))
}

@Test func standardizationAndDirectMarkdownConversion() throws {
    let html = "<h2 id=\"x\"><a class=\"header-anchor\" href=\"#x\">#</a>Heading</h2><p><img data-src=\"image.jpg\" alt=\"Image\"></p>"
    let standardized = try Elements.standardizeAll(html)
    #expect(standardized.contains("src=\"image.jpg\""))
    #expect(!standardized.contains("header-anchor"))
    #expect(try Markdown.convert(standardized).contains("## Heading"))
}

@Test func markdownBlockAndTableRules() throws {
    let html = "<blockquote><p>Quoted text</p></blockquote><table><tr><th>Name</th><th>Value</th></tr><tr><td>A</td><td>B</td></tr></table>"
    let markdown = try Markdown.convert(html)
    #expect(markdown.contains("> Quoted text"))
    #expect(markdown.contains("| Name | Value |"))
    #expect(markdown.contains("|------|-------|"))
}

@Test func markdownRustRulesCoverInlineBlocksAndMedia() throws {
    let html = """
    <h1>Article</h1><p><del>old</del> <mark>important</mark> <sup>2</sup> <sub>n</sub><br>next</p>
    <hr><figure><img src="photo.jpg" alt="photo"><figcaption>Caption</figcaption></figure>
    <blockquote data-callout="warning"><p>Be careful.</p></blockquote>
    <iframe src="https://www.youtube.com/embed/demo"></iframe>
    <video src="movie.mp4"></video><audio src="sound.mp3"></audio>
    """
    let markdown = try Markdown.convert(html)
    #expect(markdown.contains("~~old~~"))
    #expect(markdown.contains("==important=="))
    #expect(markdown.contains("^2^"))
    #expect(markdown.contains("~n~"))
    #expect(markdown.contains("---"))
    #expect(markdown.contains("![Caption](photo.jpg)"))
    #expect(markdown.contains("> [!WARNING]"))
    #expect(markdown.contains("[Video](https://www.youtube.com/embed/demo)"))
    #expect(markdown.contains("[Audio](sound.mp3)"))
}

@Test func elementsStandardizeRustVendors() throws {
    let html = """
    <img src="placeholder.gif" data-src="real.jpg" data-srcset="small.jpg 400w,large.jpg 1200w" width="800" height="600">
    <pre class="language-swift"><code>let x = 1</code></pre>
    <span class="katex" data-latex="x^2">rendered</span>
    """
    let standardized = try Elements.standardizeAll(html)
    #expect(standardized.contains("src=\"large.jpg\""))
    #expect(standardized.contains("data-lang=\"swift\""))
    #expect(standardized.contains("<math data-latex=\"x^2\""))
    #expect(Elements.pickBestSrcset("a.jpg 1x,b.jpg 2x") == "b.jpg")
}

@Test func markdownReferenceLinksMatchRustState() throws {
    let options = MarkdownOptions(linkStyle: .reference)
    let markdown = try Markdown.convert("<p><a href='https://example.com'>one</a> <a href='https://example.com'>two</a></p>", options: options)
    #expect(markdown.contains("[one][1]"))
    #expect(markdown.contains("[two][2]"))
    #expect(markdown.contains("[1]: https://example.com"))
    #expect(markdown.contains("[2]: https://example.com"))
}

@Test func htmlEntitiesAndVisibilityMatchRustSignals() throws {
    #expect(Utils.unescapeHTMLEntities("A &#65; &#x1F600; &amp; B") == "A A 😀 & B")
    let document = try DOMUtils.parse("<div style='display:none'><p>hidden</p></div><p id='visible'>visible</p>")
    let hidden = try #require(document.select("p").first())
    #expect(!DOMUtils.isProbablyVisible(hidden))
    let visible = try #require(document.select("#visible").first())
    #expect(DOMUtils.isProbablyVisible(visible))
}

@Test func bylineUtilitiesMatchRustCases() {
    #expect(Utils.cleanBylineText("Nicolas Perriault — ") == "Nicolas Perriault")
    #expect(Utils.cleanBylineText("Follow @example") == nil)
    #expect(Utils.cleanBylineText("Dan Goodin - Apr 16, 2015 8:02 pm UTC") == "Dan Goodin")
    #expect(Utils.cleanBylineText("Alex Perry\n                                                1 day ago") == "Alex Perry")
    #expect(Utils.cleanBylineText("Our Foreign Staff") == nil)
    #expect(Utils.looksLikeAuthorName("Daniel Kahn Gillmor"))
    #expect(!Utils.looksLikeAuthorName("BuzzFeed News Reporter"))
    #expect(Utils.looksLikeBracketMenu("[One][Two]"))
    #expect(!Utils.looksLikeBracketMenu("[One] text [Two]"))
}

@Test func swiftNativePublicSurface() throws {
    let options = ReadabilityOptions(
        maximumElementCount: 0,
        topCandidateCount: 3,
        characterThreshold: 10,
        classPolicy: .keepAll,
        allowedVideoRegex: /youtube/,
        markdown: .init()
    )
    let parser = try Readability("<article><p>Portable content that is long enough to be extracted.</p></article>", options: options)
    let article = try parser.parse()
    let encoded = try JSONEncoder().encode(article)
    let json = String(decoding: encoded, as: UTF8.self)
    #expect(json.contains("text_content"))
    #expect(article.markdownContent != nil)
}

@Test func staticParseAndComputedUTF8Length() throws {
    let text = String(repeating: "Swift value semantics make article state consistent. ", count: 12)
    let article = try Readability.parse(
        "<article><p>\(text)</p></article>",
        options: .init(characterThreshold: 20)
    )

    #expect(article.utf8Length == article.textContent.utf8.count)
    let encoded = try JSONEncoder().encode(article)
    let decoded = try JSONDecoder().decode(Article.self, from: encoded)
    #expect(decoded == article)
}

@Test func baseURLControlsRelativeURLResolution() throws {
    let paragraph = String(repeating: "Substantial article text for relative URL resolution. ", count: 8)
    let html = "<article><p>\(paragraph)</p><a href='../source'>Source</a><img src='image.jpg'></article>"

    let relative = try Readability.parse(html, options: .init(characterThreshold: 20))
    #expect(relative.content.contains("href=\"../source\""))
    #expect(relative.content.contains("src=\"image.jpg\""))

    let absolute = try Readability.parse(
        html,
        baseURL: URL(string: "https://example.com/articles/story"),
        options: .init(characterThreshold: 20)
    )
    #expect(absolute.content.contains("href=\"https://example.com/source\""))
    #expect(absolute.content.contains("src=\"https://example.com/articles/image.jpg\""))
}

@Test func classPolicyHasNoContradictoryState() throws {
    let paragraph = String(repeating: "Content long enough to retain this article. ", count: 8)
    let html = "<article class='page article-shell'><p class='copy highlighted'>\(paragraph)</p></article>"

    let defaultArticle = try Readability.parse(html, options: .init(characterThreshold: 20))
    #expect(defaultArticle.content.contains("class=\"page\""))
    #expect(!defaultArticle.content.contains("article-shell"))
    #expect(!defaultArticle.content.contains("highlighted"))

    let classless = try Readability.parse(
        html,
        options: .init(characterThreshold: 20, classPolicy: .removeAll)
    )
    #expect(!classless.content.contains("class="))

    let unchanged = try Readability.parse(
        html,
        options: .init(characterThreshold: 20, classPolicy: .keepAll)
    )
    #expect(unchanged.content.contains("article-shell"))
    #expect(unchanged.content.contains("highlighted"))
}

@Test func readabilityDoesNotOverrideMarkdownURLPolicy() throws {
    let paragraph = String(repeating: "Substantial article text for Markdown sanitization. ", count: 8)
    let html = "<article><p>\(paragraph)</p><a href='javascript:evil()'>Unsafe</a></article>"
    let article = try Readability.parse(
        html,
        options: .init(
            characterThreshold: 20,
            markdown: .init(sanitizeURLs: true),
            sanitizesContent: false
        )
    )

    #expect(article.content.contains("javascript:evil()"))
    let markdown = try #require(article.markdownContent)
    #expect(!markdown.contains("javascript:"))
    #expect(markdown.contains("Unsafe"))
}
