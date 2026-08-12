import Foundation
import Testing
@testable import ReadabilitySwift

private struct MarkdownGoldenCase: Decodable {
    let html: String
    let markdown: String
}

private struct MarkdownGoldenDifference {
    let index: Int
    let html: String
    let expected: String
    let actual: String
}

private let knownMarkdownGoldenDivergences: Set<Int> = []

@Test func readabilityrsMarkdownGoldenCompatibility() throws {
    let cases = try loadMarkdownGoldenCases()
    #expect(cases.count == 105)

    let differences = cases.enumerated().compactMap { offset, testCase -> MarkdownGoldenDifference? in
        let actual = Markdown.convert(html: testCase.html)
        guard actual != testCase.markdown else { return nil }
        return MarkdownGoldenDifference(
            index: offset + 1,
            html: testCase.html,
            expected: testCase.markdown,
            actual: actual
        )
    }
    let unexpected = differences.filter { !knownMarkdownGoldenDivergences.contains($0.index) }

    print("\nMarkdown golden compatibility: \(cases.count - differences.count)/\(cases.count) (\(goldenPercentage(cases.count - differences.count, cases.count))%)")
    if !differences.isEmpty {
        print("Markdown golden differences (\(differences.count))")
        differences.forEach { difference in
            print("- #\(difference.index) input: \(singleLinePreview(difference.html))")
            print("  expected: \(singleLinePreview(difference.expected))")
            print("  actual:   \(singleLinePreview(difference.actual))")
        }
    }

    #expect(unexpected.isEmpty)
}

private func loadMarkdownGoldenCases() throws -> [MarkdownGoldenCase] {
    let url = try #require(
        Bundle.module.resourceURL?
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("MarkdownGolden.jsonl")
    )
    let source = try String(contentsOf: url, encoding: .utf8)
    return try source.split(separator: "\n").map { line in
        try JSONDecoder().decode(MarkdownGoldenCase.self, from: Data(line.utf8))
    }
}

private func singleLinePreview(_ value: String) -> String {
    let line = value.replacingOccurrences(of: "\n", with: "\\n")
    guard line.count > 240 else { return line }
    return String(line.prefix(240)) + "…"
}

private func goldenPercentage(_ numerator: Int, _ denominator: Int) -> String {
    guard denominator > 0 else { return "0.0" }
    return String(format: "%.1f", Double(numerator) / Double(denominator) * 100)
}
