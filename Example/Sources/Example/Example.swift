import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ReadabilitySwift

@main
struct Example {
    static func main() async {
        do {
            let configuration = try CLIConfiguration(arguments: Array(CommandLine.arguments.dropFirst()))
            if configuration.showHelp {
                print(CLIConfiguration.usage)
                return
            }

            let document = try await readInput(from: configuration.input)
            let options = ReadabilityOptions(
                markdown: configuration.format == .markdown ? MarkdownOptions() : nil
            )
            let baseURLString = configuration.url ?? document.baseURL
            let baseURL: URL?
            if let baseURLString {
                guard let parsedURL = URL(string: baseURLString), parsedURL.scheme?.isEmpty == false else {
                    throw CLIError.invalidWebURL(baseURLString)
                }
                baseURL = parsedURL
            } else {
                baseURL = nil
            }
            let parser = try Readability(
                document.html,
                baseURL: baseURL,
                options: options
            )

            let article = try parser.parse()

            try writeOutput(render(article, format: configuration.format))
        } catch let error as CLIError {
            writeError(error.localizedDescription)
            exit(2)
        } catch {
            writeError(error.localizedDescription)
            exit(1)
        }
    }

    private static func readInput(from input: String?) async throws -> (html: String, baseURL: String?) {
        guard let input, input != "-" else {
            return (
                String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self),
                nil
            )
        }

        if let url = try webURL(from: input) {
            return (try await readRemoteHTML(from: url), url.absoluteString)
        }

        do {
            return (try String(contentsOfFile: input, encoding: .utf8), nil)
        } catch {
            throw CLIError.cannotReadInput(input)
        }
    }

    private static func webURL(from input: String) throws -> URL? {
        guard let url = URL(string: input), let scheme = url.scheme?.lowercased() else {
            return nil
        }

        guard scheme == "http" || scheme == "https" else {
            throw CLIError.unsupportedInput(input)
        }
        guard url.host != nil else {
            throw CLIError.invalidWebURL(input)
        }
        return url
    }

    private static func readRemoteHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("ReadabilitySwiftExample/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw CLIError.invalidHTTPResponse(url.absoluteString)
            }
            guard (200..<300).contains(response.statusCode) else {
                throw CLIError.httpFailure(url.absoluteString, response.statusCode)
            }
            guard let html = String(data: data, encoding: .utf8) else {
                throw CLIError.invalidUTF8(url.absoluteString)
            }
            return html
        } catch let error as CLIError {
            throw error
        } catch {
            throw CLIError.cannotFetchURL(url.absoluteString)
        }
    }

    private static func render(_ article: Article, format: OutputFormat) -> String {
        switch format {
        case .text:
            return article.textContent
        case .markdown:
            return article.markdownContent ?? ""
        }
    }

    private static func writeOutput(_ output: String) throws {
        var data = Data(output.utf8)
        if !output.hasSuffix("\n") {
            data.append(0x0A)
        }
        try FileHandle.standardOutput.write(contentsOf: data)
    }

    private static func writeError(_ message: String) {
        let data = Data("error: \(message)\n\n\(CLIConfiguration.usage)".utf8)
        try? FileHandle.standardError.write(contentsOf: data)
    }
}

enum OutputFormat: String {
    case text
    case markdown
}

struct CLIConfiguration {
    let input: String?
    let format: OutputFormat
    let url: String?
    let showHelp: Bool

    init(arguments: [String]) throws {
        var input: String?
        var format = OutputFormat.text
        var url: String?
        var showHelp = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "-h", "--help":
                showHelp = true
            case "-f", "--format":
                index += 1
                guard index < arguments.count else { throw CLIError.missingValue(argument) }
                guard let parsedFormat = OutputFormat(rawValue: arguments[index].lowercased()) else {
                    throw CLIError.invalidFormat(arguments[index])
                }
                format = parsedFormat
            case "--url":
                index += 1
                guard index < arguments.count else { throw CLIError.missingValue(argument) }
                url = arguments[index]
            case "--":
                input = try Self.parseInput(arguments[(index + 1)...], current: input)
                index = arguments.count
                continue
            default:
                if argument.hasPrefix("-") {
                    throw CLIError.unknownOption(argument)
                }
                input = try Self.parseInput([argument], current: input)
            }
            index += 1
        }

        self.input = input
        self.format = format
        self.url = url
        self.showHelp = showHelp
    }

    static let usage = """
    Usage: swift run Example [options] [input.html|URL]

    Extract a readable article from a local HTML file, a web URL, or standard input.

    Options:
      -f, --format <format>  Output format: text or markdown (default: text)
          --url <url>        Base URL for resolving relative links and media
      -h, --help             Show this help message

    Examples:
      swift run Example article.html
      swift run Example https://example.com/article --format markdown
      cat article.html | swift run Example --format markdown
    """

    private static func parseInput<S: Collection>(_ values: S, current: String?) throws -> String?
    where S.Element == String {
        guard let value = values.first else { return current }
        guard values.count == 1, current == nil else { throw CLIError.multipleInputs }
        return value
    }
}

enum CLIError: LocalizedError, Equatable {
    case cannotReadInput(String)
    case cannotFetchURL(String)
    case httpFailure(String, Int)
    case invalidHTTPResponse(String)
    case invalidUTF8(String)
    case invalidWebURL(String)
    case invalidFormat(String)
    case missingValue(String)
    case multipleInputs
    case unsupportedInput(String)
    case unknownOption(String)

    var errorDescription: String? {
        switch self {
        case let .cannotReadInput(path): "Could not read input file: \(path)"
        case let .cannotFetchURL(url): "Could not fetch URL: \(url)"
        case let .httpFailure(url, statusCode): "HTTP request failed for \(url) with status code \(statusCode)"
        case let .invalidHTTPResponse(url): "Invalid HTTP response from URL: \(url)"
        case let .invalidUTF8(url): "Response was not valid UTF-8: \(url)"
        case let .invalidWebURL(url): "Invalid web URL: \(url)"
        case let .invalidFormat(format): "Unsupported output format: \(format)"
        case let .missingValue(option): "Missing value for \(option)"
        case .multipleInputs: "Only one input file may be specified"
        case let .unsupportedInput(input): "Unsupported input scheme: \(input)"
        case let .unknownOption(option): "Unknown option: \(option)"
        }
    }
}
