import Foundation
import Testing
@testable import ReadabilitySwift

// Compatibility baselines are evidence from the pinned fixture run, not cases
// that are considered correct. A new entry must include an updated report with
// the observed mismatch; removing an entry after a fix is always safe.
private let knownSwiftMetadataDivergences: Set<String> = [
    "ietf-1",
    "liberation-1",
    "mathjax",
    "mercurial",
    "replace-brs",
    "salon-1",
    "seattletimes-1",
    "wikipedia-2",
    "wikipedia-4",
    "wordpress",
]

private let knownSwiftExtendedMetadataDivergences: Set<String> = [
    "ietf-1",
    "liberation-1",
    "mathjax",
    "mercurial",
    "replace-brs",
    "rtl-2",
    "rtl-3",
    "salon-1",
    "seattletimes-1",
    "tmz-1",
    "wikipedia-2",
    "wikipedia-4",
    "wordpress",
    "yahoo-3",
]

private let knownSwiftContentDivergences: Set<String> = [
    "archive-of-our-own",
    "bug-1255978",
    "heise",
    "hukumusume",
    "yahoo-3",
    "yahoo-4",
]

private struct MozillaExpectedMetadata: Decodable {
    let title: String?
    let byline: String?
    let dir: String?
    let lang: String?
    let excerpt: String?
    let siteName: String?
    let publishedTime: String?
    let readerable: Bool
}

private struct MozillaTestCase {
    let name: String
    let sourceHTML: String
    let expectedHTML: String
    let expectedMetadata: MozillaExpectedMetadata
}

private struct CaseEvaluation {
    let name: String
    let expectedReaderable: Bool
    let coreMetadataMismatches: [String]
    let extendedMetadataMismatches: [String]
    let contentFailure: String?
    let extractedArticle: Bool
}

@Test func mozillaReadabilityCompatibility() throws {
    let testCases = try loadMozillaTestCases()
    #expect(testCases.count == 130)

    let evaluations = testCases.map(evaluate)
    let coreMetadataMatches = evaluations.filter(\.coreMetadataMismatches.isEmpty)
    let extendedMetadataMatches = evaluations.filter(\.extendedMetadataMismatches.isEmpty)
    let readerableCases = evaluations.filter(\.expectedReaderable)
    let extractedReaderableCases = readerableCases.filter(\.extractedArticle)
    let contentMatches = readerableCases.filter { $0.contentFailure == nil }

    let metadataDivergences = Set(
        evaluations.filter { !$0.coreMetadataMismatches.isEmpty }.map(\.name)
    )
    let extendedMetadataDivergences = Set(
        evaluations.filter { !$0.extendedMetadataMismatches.isEmpty }.map(\.name)
    )
    let contentDivergences = Set(
        readerableCases.filter { $0.contentFailure != nil }.map(\.name)
    )

    printCompatibilitySummary(
        total: evaluations.count,
        coreMetadataMatches: coreMetadataMatches.count,
        extendedMetadataMatches: extendedMetadataMatches.count,
        readerableTotal: readerableCases.count,
        extractedReaderable: extractedReaderableCases.count,
        contentMatches: contentMatches.count
    )
    printFailures("Metadata differences", evaluations.compactMap(metadataFailureDescription))
    printFailures("Extended metadata differences", evaluations.compactMap(extendedMetadataFailureDescription))
    printFailures("Content differences", readerableCases.compactMap(contentFailureDescription))

    #expect(readerableCases.count == 122)
    #expect(extractedReaderableCases.count == readerableCases.count)
    #expect(metadataDivergences == knownSwiftMetadataDivergences)
    #expect(extendedMetadataDivergences == knownSwiftExtendedMetadataDivergences)
    #expect(contentDivergences == knownSwiftContentDivergences)
}

private func loadMozillaTestCases() throws -> [MozillaTestCase] {
    let root = try mozillaFixtureRoot()
    let directories = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ).filter {
        try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    }.sorted {
        $0.lastPathComponent < $1.lastPathComponent
    }

    return try directories.map { directory in
        let sourceHTML = try String(contentsOf: directory.appendingPathComponent("source.html"), encoding: .utf8)
        let expectedHTML = try String(contentsOf: directory.appendingPathComponent("expected.html"), encoding: .utf8)
        let expectedData = try Data(contentsOf: directory.appendingPathComponent("expected-metadata.json"))
        let expectedMetadata = try JSONDecoder().decode(MozillaExpectedMetadata.self, from: expectedData)
        return MozillaTestCase(
            name: directory.lastPathComponent,
            sourceHTML: sourceHTML,
            expectedHTML: expectedHTML,
            expectedMetadata: expectedMetadata
        )
    }
}

private func evaluate(_ testCase: MozillaTestCase) -> CaseEvaluation {
    let article = try? Readability(testCase.sourceHTML).parse()
    var coreMismatches: [String] = []
    var extendedMismatches: [String] = []

    if testCase.expectedMetadata.readerable && article == nil {
        let mismatch = "expected readerable content but extraction returned no article"
        coreMismatches.append(mismatch)
        extendedMismatches.append(mismatch)
    }

    if let article {
        compare("title", actual: article.title, expected: testCase.expectedMetadata.title, mismatches: &coreMismatches)
        compare("byline", actual: article.byline, expected: testCase.expectedMetadata.byline, mismatches: &coreMismatches)
        compare("excerpt", actual: article.excerpt, expected: testCase.expectedMetadata.excerpt, mismatches: &coreMismatches)
        compare("siteName", actual: article.siteName, expected: testCase.expectedMetadata.siteName, mismatches: &coreMismatches)

        extendedMismatches = coreMismatches
        compare("dir", actual: article.dir, expected: testCase.expectedMetadata.dir, mismatches: &extendedMismatches)
        compare("lang", actual: article.lang, expected: testCase.expectedMetadata.lang, mismatches: &extendedMismatches)
        compare("publishedTime", actual: article.publishedTime, expected: testCase.expectedMetadata.publishedTime, mismatches: &extendedMismatches)
    }

    return CaseEvaluation(
        name: testCase.name,
        expectedReaderable: testCase.expectedMetadata.readerable,
        coreMetadataMismatches: coreMismatches,
        extendedMetadataMismatches: extendedMismatches,
        contentFailure: contentFailure(article: article, expectedHTML: testCase.expectedHTML),
        extractedArticle: article != nil
    )
}

private func compare(
    _ field: String,
    actual: String?,
    expected: String?,
    mismatches: inout [String]
) {
    guard normalized(actual) != normalized(expected) else { return }
    mismatches.append("\(field): expected \(String(describing: expected)), got \(String(describing: actual))")
}

private func contentFailure(article: Article?, expectedHTML: String) -> String? {
    guard let article, let content = article.content else {
        return "expected article content but extraction returned none"
    }
    let actualLength = normalizedTextLength(content)
    let expectedLength = normalizedTextLength(expectedHTML)
    guard actualLength > 0 else {
        return "extracted content is empty (expected approximately \(expectedLength) characters)"
    }
    let lowerBound = expectedLength / 2
    let upperBound = expectedLength * 2
    guard actualLength < lowerBound || actualLength > upperBound else { return nil }
    return "content length \(actualLength) is outside [\(lowerBound), \(upperBound)] (expected approximately \(expectedLength))"
}

private func normalizedTextLength(_ html: String) -> Int {
    guard let document = try? DOMUtils.parse(html), let body = document.body() else { return 0 }
    return DOMUtils.textContent(body).split(whereSeparator: \.isWhitespace).joined(separator: " ").count
}

private func normalized(_ value: String?) -> String? {
    value?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

private func metadataFailureDescription(_ evaluation: CaseEvaluation) -> String? {
    guard !evaluation.coreMetadataMismatches.isEmpty else { return nil }
    return "\(evaluation.name): \(evaluation.coreMetadataMismatches.joined(separator: "; "))"
}

private func contentFailureDescription(_ evaluation: CaseEvaluation) -> String? {
    evaluation.contentFailure.map { "\(evaluation.name): \($0)" }
}

private func extendedMetadataFailureDescription(_ evaluation: CaseEvaluation) -> String? {
    guard !evaluation.extendedMetadataMismatches.isEmpty else { return nil }
    return "\(evaluation.name): \(evaluation.extendedMetadataMismatches.joined(separator: "; "))"
}

private func printCompatibilitySummary(
    total: Int,
    coreMetadataMatches: Int,
    extendedMetadataMatches: Int,
    readerableTotal: Int,
    extractedReaderable: Int,
    contentMatches: Int
) {
    print("""

    Mozilla Readability compatibility
    =================================
    Core metadata:      \(coreMetadataMatches)/\(total) (\(percentage(coreMetadataMatches, total))%)
    Extended metadata:  \(extendedMetadataMatches)/\(total) (\(percentage(extendedMetadataMatches, total))%)
    Article extraction: \(extractedReaderable)/\(readerableTotal) (\(percentage(extractedReaderable, readerableTotal))%)
    Content length band:\(contentMatches)/\(readerableTotal) (\(percentage(contentMatches, readerableTotal))%)
    """)
}

private func printFailures(_ heading: String, _ failures: [String]) {
    guard !failures.isEmpty else { return }
    print("\n\(heading) (\(failures.count))")
    failures.forEach { print("- \($0)") }
}

private func percentage(_ numerator: Int, _ denominator: Int) -> String {
    guard denominator > 0 else { return "0.0" }
    return String(format: "%.1f", Double(numerator) / Double(denominator) * 100)
}
