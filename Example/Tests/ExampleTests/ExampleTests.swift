import Testing
@testable import Example

@Test func parsesCLIOptions() throws {
    let configuration = try CLIConfiguration(arguments: [
        "article.html",
        "--format", "markdown",
        "--url", "https://example.com/article",
    ])

    #expect(configuration.input == "article.html")
    #expect(configuration.format == .markdown)
    #expect(configuration.url == "https://example.com/article")
    #expect(!configuration.showHelp)
}

@Test func defaultsToTextAndStandardInput() throws {
    let configuration = try CLIConfiguration(arguments: [])

    #expect(configuration.input == nil)
    #expect(configuration.format == .text)
}

@Test func acceptsWebURLAsInput() throws {
    let configuration = try CLIConfiguration(arguments: [
        "https://example.com/article",
        "--format", "markdown",
    ])

    #expect(configuration.input == "https://example.com/article")
    #expect(configuration.format == .markdown)
}

@Test func rejectsInvalidArguments() {
    #expect(throws: CLIError.invalidFormat("xml")) {
        _ = try CLIConfiguration(arguments: ["--format", "xml"])
    }
    #expect(throws: CLIError.multipleInputs) {
        _ = try CLIConfiguration(arguments: ["one.html", "two.html"])
    }
    #expect(throws: CLIError.invalidFormat("json")) {
        _ = try CLIConfiguration(arguments: ["--format", "json"])
    }
}
