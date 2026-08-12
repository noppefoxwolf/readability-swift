import Foundation
import Testing
@testable import ReadabilitySwift

@Test func setextHeadingStyleMatchesReadabilityrs() throws {
    let markdown = try Markdown.convert(
        "<h2>Subtitle</h2>",
        options: .init(headingStyle: .setext)
    )
    #expect(markdown == "Subtitle\n--------")
}

@Test func customMarkdownDelimitersMatchReadabilityrs() throws {
    let markdown = try Markdown.convert(
        "<p><em>emphasis</em> and <strong>strong</strong></p><ul><li>item</li></ul>",
        options: .init(bulletCharacter: "+", emphasisDelimiter: "_", strongDelimiter: "__")
    )
    #expect(markdown.contains("_emphasis_"))
    #expect(markdown.contains("__strong__"))
    #expect(markdown.contains("+ item"))
}

@Test func customFenceAndReferenceLinksMatchReadabilityrs() throws {
    let markdown = try Markdown.convert(
        "<pre><code>code</code></pre><p><a href='https://example.com'>Example</a></p>",
        options: .init(codeFence: "~", linkStyle: .reference)
    )
    #expect(markdown.contains("~~~\ncode\n~~~"))
    #expect(markdown.contains("[Example][1]"))
    #expect(markdown.contains("[1]: https://example.com"))
}

@Test func headingStandardizationUsesArticleTitle() throws {
    let matching = try MarkdownConverter.htmlToMarkdown(
        "<h1>My Title</h1><p>Content</p>",
        options: .init(),
        title: "My Title"
    )
    #expect(!matching.contains("# My Title"))
    #expect(matching.contains("Content"))

    let different = try MarkdownConverter.htmlToMarkdown(
        "<h1>Other Heading</h1>",
        options: .init(),
        title: "Different Title"
    )
    #expect(different == "## Other Heading")
}

@Test func fullReadabilityMarkdownPipelineMatchesReadabilityrs() throws {
    let paragraph = "This is substantial article content with enough words for extraction and scoring."
    let html = """
    <html><head><title>Test Article</title></head><body><article>
    <h1>Test Article</h1>
    <p>This is a <strong>test article</strong> with <em>rich formatting</em>.</p>
    <p>\(paragraph)</p><p>\(paragraph)</p><p>\(paragraph)</p><p>\(paragraph)</p>
    <p>Final paragraph with a <a href="https://example.com">link</a>.</p>
    </article></body></html>
    """
    let article = try Readability(
        html,
        options: .init(characterThreshold: 100, markdown: .init())
    ).parse()
    let markdown = try #require(article.markdownContent)
    #expect(!article.content.isEmpty)
    #expect(markdown.contains("**test article**"))
    #expect(markdown.contains("*rich formatting*"))
    #expect(markdown.contains("[link](https://example.com)"))
}

@Test func markdownIsDisabledByDefault() throws {
    let text = String(repeating: "Simple content that should pass the extraction threshold. ", count: 12)
    let article = try Readability("<article><p>\(text)</p></article>").parse()
    #expect(article.markdownContent == nil)
}

@Test func dangerousURLDetectionMatchesReadabilityrs() {
    for value in [
        "JavaScript:alert(1)",
        "\t\n javascript:alert(1)",
        "VBScript:msgbox(1)",
        "data:text/html,<script>alert(1)</script>",
        "java\tscript:alert(1)",
        "java\nscript:alert(1)",
        "java\rscript:alert(1)",
        "jav\0ascript:alert(1)",
    ] {
        #expect(Utils.isDangerousURL(value))
    }
    for value in [
        "data:image/png;base64,iVBORw0KGgo=",
        "/relative/path",
        "//host/path",
        "https://example.com",
        "https://example.com/İstanbul/🎉",
        "İ",
        "🎉:notreal",
    ] {
        #expect(!Utils.isDangerousURL(value))
    }
}

@Test func sanitizeContentRemovesActiveMarkupAndDangerousURLs() throws {
    let paragraph = "This substantial paragraph exists to ensure the article is selected by the content extractor."
    let html = """
    <article onclick="evil()"><h1>Sanitize Article</h1>
    <p>\(paragraph)</p><p>\(paragraph)</p><p>\(paragraph)</p><p>\(paragraph)</p>
    <p><a href="javascript:evil()" onmouseover="evil()">dangerous</a>
    <a href="https://example.com" onclick="evil()">safe</a></p>
    <template><p>hidden template</p></template><!-- dangerous comment -->
    </article>
    """
    let article = try Readability(
        html,
        options: .init(characterThreshold: 100, markdown: .init(), sanitizesContent: true)
    ).parse()
    let content = article.content
    let markdown = try #require(article.markdownContent)

    #expect(!content.contains("onclick"))
    #expect(!content.contains("onmouseover"))
    #expect(!content.contains("javascript:"))
    #expect(!content.contains("<template"))
    #expect(!content.contains("dangerous comment"))
    #expect(content.contains("href=\"https://example.com\""))
    #expect(!markdown.contains("javascript:"))
    #expect(markdown.contains("[safe](https://example.com)"))
}

@Test func markdownURLSanitizationIsOptIn() throws {
    let html = "<p><a href='javascript:evil()'>link</a><img src='javascript:evil()' alt='image'></p>"
    let defaultMarkdown = try Markdown.convert(html)
    #expect(defaultMarkdown.contains("javascript:"))

    let sanitized = try Markdown.convert(html, options: .init(sanitizeURLs: true))
    #expect(!sanitized.contains("javascript:"))
    #expect(sanitized == "link")
}
