import Foundation
import Testing
@testable import ReadabilitySwift

@Test func allMozillaPagesMarkdownQualityAudit() throws {
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
    #expect(directories.count == 130)

    var failures: [String] = []
    for directory in directories {
        let name = directory.lastPathComponent
        let html = try String(contentsOf: directory.appendingPathComponent("expected.html"), encoding: .utf8)
        let markdown = Markdown.convert(html: html)
        failures += markdownQualityFailures(markdown, caseName: name)
    }

    if !failures.isEmpty {
        print("\nMarkdown quality differences (\(failures.count))")
        failures.forEach { print("- \($0)") }
    }
    #expect(failures.isEmpty)
}

private func markdownQualityFailures(_ markdown: String, caseName: String) -> [String] {
    var failures: [String] = []
    let lines = markdown.components(separatedBy: "\n")

    if markdown.contains("\n\n\n") {
        failures.append("\(caseName): triple newlines")
    }
    if let line = lines.firstIndex(where: { $0.last == " " || $0.last == "\t" }) {
        failures.append("\(caseName): trailing whitespace on line \(line + 1)")
    }
    if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        failures.append("\(caseName): empty output")
    }
    if let line = firstGarbledBlockquote(in: lines) {
        failures.append("\(caseName): garbled blockquote on line \(line + 1)")
    }
    if let line = firstBareBullet(in: lines) {
        failures.append("\(caseName): bare bullet on line \(line + 1)")
    }
    if let line = firstDoubleEmptyBlockquote(in: lines) {
        failures.append("\(caseName): consecutive empty blockquotes on line \(line + 1)")
    }
    if let scalar = markdown.unicodeScalars.first(where: { $0.value < 32 && ![9, 10, 13].contains($0.value) }) {
        failures.append("\(caseName): control character U+\(String(format: "%04X", scalar.value))")
    }
    if markdown.contains("]()") {
        failures.append("\(caseName): empty URL")
    }
    if markdown.contains("|---"), tableRowsAreMisaligned(lines) {
        failures.append("\(caseName): table columns are misaligned")
    }
    if let line = firstEscapedCharacterInsideCodeBlock(in: lines) {
        failures.append("\(caseName): escaped Markdown inside code block on line \(line + 1)")
    }
    return failures
}

private func firstGarbledBlockquote(in lines: [String]) -> Int? {
    guard lines.count >= 3 else { return nil }
    return (0...(lines.count - 3)).first { index in
        lines[index...index + 2].allSatisfy(isOnlyBlockquoteMarkers)
    }
}

private func firstBareBullet(in lines: [String]) -> Int? {
    guard lines.count >= 2 else { return nil }
    return (0..<(lines.count - 1)).first { index in
        ["-", "+", "*"].contains(lines[index].trimmingCharacters(in: .whitespaces))
            && lines[index + 1].trimmingCharacters(in: .whitespaces).isEmpty
    }
}

private func firstDoubleEmptyBlockquote(in lines: [String]) -> Int? {
    guard lines.count >= 2 else { return nil }
    return (0..<(lines.count - 1)).first { index in
        isOnlyBlockquoteMarkers(lines[index]) && isOnlyBlockquoteMarkers(lines[index + 1])
    }
}

private func isOnlyBlockquoteMarkers(_ line: String) -> Bool {
    let value = line.trimmingCharacters(in: .whitespaces)
    return !value.isEmpty && value.allSatisfy { $0 == ">" }
}

private func tableRowsAreMisaligned(_ lines: [String]) -> Bool {
    let tableLines = lines.filter {
        let value = $0.trimmingCharacters(in: .whitespaces)
        return value.hasPrefix("|") && value.hasSuffix("|")
    }
    guard let first = tableLines.first, tableLines.count >= 2 else { return false }
    let expectedPipes = first.filter { $0 == "|" }.count
    return tableLines.dropFirst().contains { $0.filter { $0 == "|" }.count != expectedPipes }
}

private func firstEscapedCharacterInsideCodeBlock(in lines: [String]) -> Int? {
    var inCodeBlock = false
    for (index, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~~") {
            inCodeBlock.toggle()
            continue
        }
        if inCodeBlock && ["\\*", "\\_", "\\["].contains(where: line.contains) {
            return index
        }
    }
    return nil
}
