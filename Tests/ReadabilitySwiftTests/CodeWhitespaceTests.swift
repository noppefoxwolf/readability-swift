import Foundation
import Testing
@testable import ReadabilitySwift

private let codeWhitespacePadding = """
This paragraph exists only to push the article over the scoring threshold so the extractor keeps the section that holds the code listing under test, padding padding padding padding padding.
"""

private func parseCodeArticle(
    _ body: String,
    options: ReadabilityOptions = .init(markdown: .init())
) throws -> Article {
    let html = """
    <html><head><title>Code</title></head><body><article><h1>Code</h1><p>\(codeWhitespacePadding)</p>\(body)<p>\(codeWhitespacePadding)</p></article></body></html>
    """
    return try Readability(html, baseURL: URL(string: "https://example.com/a"), options: options).parse()
}

@Test func preBlockKeepsIndentationInContentAndMarkdown() throws {
    let article = try parseCodeArticle("""
    <pre tabindex="0" class="chroma"><code class="language-rust">fn main() {
        let x = 1;
            deeper();
    }
    </code></pre>
    """)

    let content = article.content
    #expect(content.contains("\n    let x = 1;\n"))
    #expect(content.contains("\n        deeper();\n"))

    let markdown = try #require(article.markdownContent)
    #expect(markdown.contains("\n    let x = 1;\n"))
    #expect(markdown.contains("\n        deeper();\n"))
}

@Test func preBlockKeepsBlankLines() throws {
    let article = try parseCodeArticle("<pre><code>first();\n\n\n\nlast();\n</code></pre>")
    let content = article.content
    #expect(content.contains("first();\n\n\n\nlast();"))
}

@Test func inlineCodeKeepsInternalSpacing() throws {
    let article = try parseCodeArticle("<p>The literal <code>a    b</code> matters.</p>")
    let content = article.content
    #expect(content.contains("<code>a    b</code>"))
}

@Test func commentInsidePreDoesNotEndListing() throws {
    let article = try parseCodeArticle("<pre><code><!-- </pre> -->fn f() {\n    body();\n}\n</code></pre>")
    let content = article.content
    #expect(content.contains("\n    body();\n"))
}

@Test func titleRemovalKeepsCodeIndentation() throws {
    let article = try parseCodeArticle(
        "<pre><code>fn f() {\n\n\n    body();\n   \n    tail();\n}\n</code></pre>",
        options: .init(removesTitleFromContent: true, markdown: .init())
    )
    let content = article.content
    #expect(!content.contains("<h1"))
    #expect(content.contains("{\n\n\n    body();\n   \n"))
}

@Test func titleRemovalKeepsEmptyWrappersInsideListing() throws {
    let article = try parseCodeArticle(
        "<pre><header>   </header>\n    indented\n</pre>",
        options: .init(removesTitleFromContent: true, markdown: .init())
    )
    let content = article.content
    #expect(!content.contains("<h1"))
    #expect(content.contains("<header>   </header>"))
    #expect(content.contains("\n    indented\n"))
}

@Test func proseWhitespaceStillCollapses() throws {
    let article = try parseCodeArticle("<p>ordinary    prose    spacing</p><pre>  kept  </pre>")
    let content = article.content
    #expect(content.contains("ordinary prose spacing"))
    #expect(content.contains("<pre>  kept  </pre>"))
}
