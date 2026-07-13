import Foundation
import Testing
@testable import ReadabilitySwift

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

@Test func mozillaFixtureMetadataParityWhenFixturesAreAvailable() throws {
    guard let fixtureRoot = ProcessInfo.processInfo.environment["READABILITYRS_FIXTURES"] else { return }
    let root = URL(fileURLWithPath: fixtureRoot, isDirectory: true)
    let selectedCases = ProcessInfo.processInfo.environment["READABILITYRS_CASES"]?.split(separator: ",").map(String.init)
    let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var failures: [String] = []
    for directory in directories {
        if let selectedCases, !selectedCases.contains(directory.lastPathComponent) { continue }
        let sourceURL = directory.appendingPathComponent("source.html")
        let expectedURL = directory.appendingPathComponent("expected-metadata.json")
        guard let source = try? String(contentsOf: sourceURL, encoding: .utf8),
              let expectedData = try? Data(contentsOf: expectedURL),
              let expected = try? JSONDecoder().decode(MozillaExpectedMetadata.self, from: expectedData) else { continue }
        let article: Article
        do {
            article = try Readability(source).parse()
        } catch ReadabilityError.noContentFound {
            if expected.readerable {
                failures.append("\(directory.lastPathComponent): expected readerable content")
            }
            continue
        }
        let actual: [(String, String?, String?)] = [
            ("title", article.title, expected.title),
            ("byline", article.byline, expected.byline),
            ("dir", article.dir, expected.dir),
            ("lang", article.lang, expected.lang),
            ("excerpt", article.excerpt, expected.excerpt),
            ("siteName", article.siteName, expected.siteName),
            ("publishedTime", article.publishedTime, expected.publishedTime)
        ]
        for (field, actualValue, expectedValue) in actual where normalized(actualValue) != normalized(expectedValue) {
            failures.append("\(directory.lastPathComponent).\(field): expected \(String(describing: expectedValue)), got \(String(describing: actualValue))")
        }
    }
    if !failures.isEmpty { print(failures.prefix(30).joined(separator: "\n")) }
    #expect(failures.isEmpty)
}

private func normalized(_ value: String?) -> String? {
    value?.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}
