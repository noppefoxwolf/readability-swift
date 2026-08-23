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
