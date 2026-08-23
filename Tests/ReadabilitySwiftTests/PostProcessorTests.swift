import Testing
@testable import ReadabilitySwift

@Test func postProcessorRemovesShareAndNavigationWrappers() {
    let html = """
    <article>
      <div class="social-links"><p>Share this article</p></div>
      <section id="primary-navbar"><p>Site navigation</p></section>
      <ul class="breadcrumbs"><li>Home</li></ul>
      <p>Article content</p>
    </article>
    """

    let result = PostProcessor.prepArticle(
        html,
        cleanStyles: false,
        cleanWhitespace: false
    )

    #expect(!result.contains("Share this article"))
    #expect(!result.contains("Site navigation"))
    #expect(!result.contains("Home"))
    #expect(result.contains("Article content"))
}

@Test func postProcessorRemovesPresentationAttributesInOnePass() {
    let html = ##"<p STYLE="color: white" align='center' BGCOLOR="#000" valign="top">Article content</p>"##

    let result = PostProcessor.prepArticle(
        html,
        cleanStyles: true,
        cleanWhitespace: false
    )

    #expect(result == "<p>Article content</p>")
}

@Test func postProcessorRemovesUnwantedElements() {
    let html = "<article><aside>Sidebar</aside><input type=\"search\"><nav>Navigation</nav><p>Article content</p></article>"

    let result = PostProcessor.prepArticle(
        html,
        cleanStyles: false,
        cleanWhitespace: false
    )

    #expect(!result.contains("Sidebar"))
    #expect(!result.contains("type=\"search\""))
    #expect(!result.contains("Navigation"))
    #expect(result.contains("Article content"))
}
