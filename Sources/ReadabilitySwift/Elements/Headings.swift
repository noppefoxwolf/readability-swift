import Foundation

enum ElementHeadings {
    static func standardize(_ html: String, title: String?) -> String {
        var result = html
        if let title, !title.isEmpty {
            let normalizedTitle = normalize(title)
            let pattern = "(?is)<h1\\b[^>]*>(.*?)</h1>"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
               let innerRange = Range(match.range(at: 1), in: result),
               normalize(String(result[innerRange])) == normalizedTitle,
               let fullRange = Range(match.range, in: result) {
                result.removeSubrange(fullRange)
            }
        }
        result = result.replacingOccurrences(of: "(?i)<h1\\b[^>]*>", with: "<h2>", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?i)</h1>", with: "</h2>", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?is)(<h[1-6]\\b[^>]*>)\\s*<a\\b[^>]*href=[\"']#[^\"']*[\"'][^>]*>([#¶§🔗\\s]*)</a>", with: "$1", options: .regularExpression)
        return result
    }

    private static func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
    }
}
