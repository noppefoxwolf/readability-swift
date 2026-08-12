import Foundation

public enum ReadabilityError: Error, Equatable, LocalizedError, Sendable {
    case parsingFailed(String)
    case invalidURL(String)
    case maxElementsExceeded(Int)
    case noContentFound

    public var errorDescription: String? {
        switch self {
        case let .parsingFailed(value): "Failed to parse HTML: \(value)"
        case let .invalidURL(value): "Invalid URL: \(value)"
        case let .maxElementsExceeded(value): "Maximum element limit exceeded: \(value)"
        case .noContentFound: "No article content found in document"
        }
    }
}
