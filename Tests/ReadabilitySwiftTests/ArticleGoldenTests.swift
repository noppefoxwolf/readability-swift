import Foundation
import Testing
@testable import ReadabilitySwift

private let articleGoldenBaselineName = "ArticleGoldenKnownDifferences.txt"

private struct ArticleGoldenCase: Decodable {
    let name: String
    let article: ArticleGolden?
}

private struct ArticleGolden: Decodable {
    let title: String?
    let excerpt: String?
    let byline: String?
    let image: String?
    let dir: String?
    let siteName: String?
    let lang: String?
    let publishedTime: String?
    let length: Int
    let normalizedTextContent: String

    private enum CodingKeys: String, CodingKey {
        case title, excerpt, byline, image, dir, lang, length
        case siteName = "site_name"
        case publishedTime = "published_time"
        case normalizedTextContent = "normalized_text_content"
    }
}

private struct ArticleGoldenDifference {
    let name: String
    let field: String
    let expected: String
    let actual: String

    var key: String { "\(name).\(field)" }
}

@Test func readabilityrsArticleGoldenCompatibility() throws {
    let cases = try loadArticleGoldenCases()
    #expect(cases.count == 130)

    let differences = cases.flatMap(evaluateArticleGolden)
    let divergenceKeys = Set(differences.map(\.key))
    let knownDivergences: Set<String>
    if let outputPath = ProcessInfo.processInfo.environment["READABILITY_SWIFT_ARTICLE_BASELINE_OUTPUT"] {
        let baseline = divergenceKeys.sorted().joined(separator: "\n") + "\n"
        try baseline.write(toFile: outputPath, atomically: true, encoding: .utf8)
        knownDivergences = divergenceKeys
    } else {
        knownDivergences = try loadArticleGoldenBaseline()
    }

    let unexpectedKeys = divergenceKeys.subtracting(knownDivergences)
    let resolvedKeys = knownDivergences.subtracting(divergenceKeys)
    print("\nreadabilityrs Article golden compatibility: \(cases.count) cases, \(differences.count) field differences")
    differences.filter { unexpectedKeys.contains($0.key) }.forEach { difference in
        print("- \(difference.key)")
        print("  expected: \(difference.expected)")
        print("  actual:   \(difference.actual)")
    }
    if !resolvedKeys.isEmpty {
        print("Resolved baseline entries: \(resolvedKeys.sorted().joined(separator: ", "))")
    }

    #expect(divergenceKeys == knownDivergences)
}

@Test func bug1255978DoesNotCollapseToWhitespace() throws {
    let sourceURL = try mozillaFixtureRoot()
        .appendingPathComponent("bug-1255978", isDirectory: true)
        .appendingPathComponent("source.html")
    let sourceHTML = try String(contentsOf: sourceURL, encoding: .utf8)
    let options = ReadabilityOptions()
    let preprocessedHTML = Cleaner.prepDocument(sourceHTML)
    let document = try DOMUtils.parse(preprocessedHTML)
    Cleaner.removeUnsafeElements(from: document)
    let extracted = try #require(try ContentExtractor.grabArticle(document, options: options).get())
    let lightHTML = try Cleaner.cleanArticleContentLight(extracted, baseURL: nil).get()
    let preparedHTML = PostProcessor.prepArticle(
        lightHTML,
        cleanStyles: options.cleanStyles,
        cleanWhitespace: options.cleanWhitespace,
        keepClasses: options.keepClasses,
        classesToPreserve: options.classesToPreserve
    )
    let cleanedHTML = try Cleaner.cleanArticleContent(preparedHTML, baseURL: nil).get()

    let stageLengths = [extracted, lightHTML, preparedHTML, cleanedHTML].map(normalizedArticleGoldenHTMLLength)
    #expect(stageLengths.allSatisfy { $0 >= 1_000 })

    let article = try Readability(sourceHTML).parse()
    let actualText = normalizeArticleGoldenText(article.textContent)
    let golden = try #require(loadArticleGoldenCases().first { $0.name == "bug-1255978" }?.article)
    if actualText != golden.normalizedTextContent {
        printArticleGoldenFirstDifference(expected: golden.normalizedTextContent, actual: actualText)
    }
    #expect(actualText == golden.normalizedTextContent)
}

@Test func priorityArticleTextGoldenCompatibility() throws {
    let names = ["citylab-1", "cnet", "engadget", "liberation-1", "quanta-1", "yahoo-2", "yahoo-4"]
    let goldenCases = try loadArticleGoldenCases()
    let fixtureRoot = try mozillaFixtureRoot()

    for name in names {
        let golden = try #require(goldenCases.first { $0.name == name }?.article)
        let sourceURL = fixtureRoot
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("source.html")
        let sourceHTML = try String(contentsOf: sourceURL, encoding: .utf8)
        let article = try Readability(sourceHTML).parse()
        let actualText = normalizeArticleGoldenText(article.textContent)
        if actualText != golden.normalizedTextContent {
            print("\n\(name):")
            printArticleGoldenFirstDifference(expected: golden.normalizedTextContent, actual: actualText)
        }
        #expect(actualText == golden.normalizedTextContent, "\(name)")
    }
}

private func loadArticleGoldenCases() throws -> [ArticleGoldenCase] {
    let url = try #require(
        Bundle.module.resourceURL?
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("ArticleGolden.jsonl")
    )
    let source = try String(contentsOf: url, encoding: .utf8)
    return try source.split(separator: "\n").map { line in
        try JSONDecoder().decode(ArticleGoldenCase.self, from: Data(line.utf8))
    }
}

private func loadArticleGoldenBaseline() throws -> Set<String> {
    let url = try #require(
        Bundle.module.resourceURL?
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(articleGoldenBaselineName)
    )
    let source = try String(contentsOf: url, encoding: .utf8)
    return Set(source.split(whereSeparator: \.isNewline).map(String.init))
}

private func evaluateArticleGolden(_ testCase: ArticleGoldenCase) -> [ArticleGoldenDifference] {
    let sourceURL = try? mozillaFixtureRoot()
        .appendingPathComponent(testCase.name, isDirectory: true)
        .appendingPathComponent("source.html")
    let sourceHTML = sourceURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    let actual = sourceHTML.flatMap { try? Readability($0).parse() }

    switch (testCase.article, actual) {
    case (nil, nil):
        return []
    case (.some, nil):
        return [difference(testCase.name, "article", "extracted", "none")]
    case (nil, .some):
        return [difference(testCase.name, "article", "none", "extracted")]
    case let (expected?, actual?):
        var differences: [ArticleGoldenDifference] = []
        compare(testCase.name, "title", expected.title, actual.title, into: &differences)
        compare(testCase.name, "excerpt", expected.excerpt, actual.excerpt, into: &differences)
        compare(testCase.name, "byline", expected.byline, actual.byline, into: &differences)
        compare(testCase.name, "image", expected.image, actual.image, into: &differences)
        compare(testCase.name, "dir", expected.dir, actual.dir, into: &differences)
        compare(testCase.name, "siteName", expected.siteName, actual.siteName, into: &differences)
        compare(testCase.name, "lang", expected.lang, actual.lang, into: &differences)
        compare(testCase.name, "publishedTime", expected.publishedTime, actual.publishedTime, into: &differences)
        if expected.length != actual.length {
            differences.append(difference(testCase.name, "length", String(expected.length), String(actual.length)))
        }
        let actualText = normalizeArticleGoldenText(actual.textContent)
        if expected.normalizedTextContent != actualText {
            differences.append(
                difference(
                    testCase.name,
                    "normalizedTextContent",
                    articleGoldenPreview(expected.normalizedTextContent),
                    articleGoldenPreview(actualText)
                )
            )
        }
        return differences
    }
}

private func compare(
    _ name: String,
    _ field: String,
    _ expected: String?,
    _ actual: String?,
    into differences: inout [ArticleGoldenDifference]
) {
    let normalizedExpected = expected.map(normalizeArticleGoldenText)
    let normalizedActual = actual.map(normalizeArticleGoldenText)
    guard normalizedExpected != normalizedActual else { return }
    differences.append(
        difference(
            name,
            field,
            normalizedExpected.map(articleGoldenPreview) ?? "nil",
            normalizedActual.map(articleGoldenPreview) ?? "nil"
        )
    )
}

private func difference(_ name: String, _ field: String, _ expected: String, _ actual: String) -> ArticleGoldenDifference {
    ArticleGoldenDifference(name: name, field: field, expected: expected, actual: actual)
}

private func normalizeArticleGoldenText(_ value: String?) -> String {
    value?.split(whereSeparator: \.isWhitespace).joined(separator: " ") ?? ""
}

private func normalizedArticleGoldenHTMLLength(_ html: String) -> Int {
    guard let document = try? DOMUtils.parse(html), let body = document.body() else { return 0 }
    return normalizeArticleGoldenText(DOMUtils.textContent(body)).count
}

private func articleGoldenPreview(_ value: String) -> String {
    guard value.count > 180 else { return value }
    return String(value.prefix(180)) + "… (\(value.count) characters)"
}

private func printArticleGoldenFirstDifference(expected: String, actual: String) {
    let expectedCharacters = Array(expected)
    let actualCharacters = Array(actual)
    let prefixCount = zip(expectedCharacters, actualCharacters).prefix { $0 == $1 }.count
    let start = max(0, prefixCount - 80)
    let expectedEnd = min(expectedCharacters.count, prefixCount + 240)
    let actualEnd = min(actualCharacters.count, prefixCount + 240)
    print("first difference at \(prefixCount)")
    print("expected: \(String(expectedCharacters[start..<expectedEnd]))")
    print("actual:   \(String(actualCharacters[start..<actualEnd]))")
}
