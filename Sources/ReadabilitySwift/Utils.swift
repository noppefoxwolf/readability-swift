import Foundation

enum Utils {
    static func isDangerousURL(_ value: String) -> Bool {
        let trimmed = value.drop(while: { $0.isWhitespace || $0.isASCII && $0.asciiValue.map({ $0 < 32 }) == true })
        guard let colon = trimmed.firstIndex(of: ":") else { return false }
        let rawScheme = trimmed[..<colon]
        guard !rawScheme.contains(where: { "/?#".contains($0) }) else { return false }
        let scheme = rawScheme.filter { !$0.isWhitespace && !($0.isASCII && $0.asciiValue.map({ $0 < 32 }) == true) }
        if scheme.caseInsensitiveCompare("javascript") == .orderedSame || scheme.caseInsensitiveCompare("vbscript") == .orderedSame {
            return true
        }
        if scheme.caseInsensitiveCompare("data") == .orderedSame {
            let rest = trimmed[trimmed.index(after: colon)...]
            return !rest.lowercased().hasPrefix("image/")
        }
        return false
    }

    static func unescapeHTMLEntities(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")

        // Rust's html_entities decoder handles both decimal and hexadecimal
        // numeric references. Replacing from the end keeps ranges valid.
        guard let regex = try? NSRegularExpression(pattern: "&#(?:x([0-9a-fA-F]+)|([0-9]+));", options: []) else {
            return result
        }
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        for match in regex.matches(in: result, range: range).reversed() {
            let hex = Range(match.range(at: 1), in: result).map { String(result[$0]) }
            let decimal = Range(match.range(at: 2), in: result).map { String(result[$0]) }
            let scalar = (hex.flatMap { UInt32($0, radix: 16) } ?? decimal.flatMap { UInt32($0, radix: 10) })
                .flatMap(Unicode.Scalar.init)
            guard let scalar else { continue }
            let replacement = String(Character(scalar))
            guard let replacementRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(replacementRange, with: replacement)
        }
        return result
    }

    static func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
    }

    static func isURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme, !scheme.isEmpty else { return false }
        return scheme.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil
    }

    static func looksLikeByline(_ text: String) -> Bool {
        let value = normalizeWhitespace(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: "^(by|par)[\\s,:\\-–—]+", options: [.regularExpression, .caseInsensitive]) != nil else { return false }
        let remainder = value.replacingOccurrences(of: "^(by|par)[\\s,:\\-–—]+", with: "", options: [.regularExpression, .caseInsensitive])
        return remainder.first?.isUppercase == true
    }

    static func looksLikeAuthorName(_ text: String) -> Bool {
        let value = normalizeWhitespace(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 80, value.contains(where: { $0.isWhitespace }), value.allSatisfy({ !$0.isNumber }) else { return false }
        let lower = value.lowercased()
        guard !lower.contains("@"), !lower.hasPrefix("follow ") else { return false }
        let disqualifiers = ["reporter", "editor", "writer", "staff", "senior", "team", "desk", "anchor", "producer", "analyst", "correspondent", "contributor", "technologist", "developer", "developers", "news", "press", "service", "bureau", "foreign", "android", "buzzfeed", "telegraph", "view"]
        return value.filter { $0.isLetter }.count >= 3 && !lower.split(whereSeparator: { $0.isWhitespace }).contains { disqualifiers.contains(String($0)) }
    }

    static func looksLikeBracketMenu(_ text: String) -> Bool {
        var remainder = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard remainder.first == "[" else { return false }
        var matched = 0
        while remainder.first == "[" {
            guard let end = remainder.firstIndex(of: "]") else { break }
            let token = remainder[remainder.index(after: remainder.startIndex)..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return false }
            matched += 1
            remainder = String(remainder[remainder.index(after: end)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard matched >= 2 else { return false }
        return remainder.isEmpty || remainder.hasPrefix("Versions") || remainder.allSatisfy { $0.isNumber || $0.isWhitespace }
    }

    enum CleanBylineOutcome: Equatable {
        case accepted(String)
        case droppedOrganization
        case dropped
    }

    static func cleanBylineTextWithReason(_ text: String) -> CleanBylineOutcome {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{00a0}\u{200B}\u{FEFF}")))
        guard !value.isEmpty else { return .dropped }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "-–—|•:;,. "))
        value = value.replacingOccurrences(of: "\r\n", with: "\n")
        value = collapseBlankLinesPreserveIndent(value)
        guard !value.isEmpty else { return .dropped }
        let hasAuthorSegment = containsAuthorLikeSegment(value)
        if hasAuthorSegment {
            value = stripTrailingDateClause(value)
            value = value.components(separatedBy: .newlines).filter { !looksLikeLiveTimestamp($0) }.joined(separator: "\n")
        }
        value = value.components(separatedBy: .newlines).filter { !looksLikeSocialHandle($0) }.joined(separator: "\n")
        if value.lowercased().hasPrefix("posted by") || value.lowercased().hasPrefix("promoted by") { return .droppedOrganization }
        if value.contains("@") || value.lowercased().contains("follow @") { return .dropped }
        if looksLikeBracketMenu(value) { return .dropped }
        if !value.contains(where: { $0.isLetter }) { return .dropped }
        if isBylineOrganizationCredit(value) || looksLikeNavigationMenu(value) { return .droppedOrganization }
        return .accepted(value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{00a0}\u{200B}\u{FEFF}"))))
    }

    private static func containsAuthorLikeSegment(_ text: String) -> Bool {
        if looksLikeAuthorName(text) { return true }
        for line in text.components(separatedBy: .newlines) {
            let pieces = line.split(whereSeparator: { "|/•·".contains($0) })
            if pieces.contains(where: { looksLikeAuthorName(String($0)) }) { return true }
            for separator in [" - ", " – ", " — "] where line.contains(separator) {
                if line.components(separatedBy: separator).contains(where: looksLikeAuthorName) { return true }
            }
        }
        return false
    }

    private static func collapseBlankLinesPreserveIndent(_ text: String) -> String {
        var result = ""
        var pendingIndent: String?
        var wroteLine = false
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if pendingIndent == nil && !line.isEmpty { pendingIndent = line }
                continue
            }
            if wroteLine { result += "\n" }
            if let pendingIndent { result += pendingIndent }
            result += line
            pendingIndent = nil
            wroteLine = true
        }
        return result
    }

    static func isBylineOrganizationCredit(_ text: String) -> Bool {
        if containsAuthorLikeSegment(text) { return false }
        let normalized = normalizeWhitespace(text).lowercased()
        let exactAgencies = ["afp", "ap", "associated press", "reuters", "bloomberg", "press association", "kyodo", "ansa", "dpa", "upi"]
        if exactAgencies.contains(normalized) { return true }
        let keywords = ["staff", "news", "newsroom", "desk", "team", "press", "service", "bureau", "foreign", "reporter", "reporters", "developers", "android", "buzzfeed", "wire", "agency", "agencies", "telegraph", "our", "editors", "view"]
        let tokens = normalized.split(whereSeparator: { $0.isWhitespace || ",.;:|".contains($0) })
        return tokens.filter { keywords.contains(String($0)) }.count >= 2
    }

    private static func looksLikeNavigationMenu(_ text: String) -> Bool {
        if text.filter({ $0 == "|" }).count >= 2 { return true }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard lines.count >= 2 else { return false }
        return lines.allSatisfy { line in
            let words = line.split(whereSeparator: { $0.isWhitespace })
            guard !words.isEmpty, words.count <= 3, line.count >= 3, line.count <= 30 else { return false }
            return words.allSatisfy { word in
                let letters = word.filter(\.isLetter)
                return !letters.isEmpty && letters.allSatisfy(\.isUppercase)
            }
        }
    }

    private static func looksLikeSocialHandle(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty { return false }
        if value.hasPrefix("@") || value.contains(" @") || value.contains("twitter.com/") || value.contains("facebook.com/") { return true }
        if value.hasPrefix("follow ") && value.contains("@") { return true }
        if value.contains(" follow @") { return true }
        if value.contains(" follow us") && value.contains("twitter") { return true }
        return value.contains(" follow on") && value.contains("twitter")
    }

    private static func stripTrailingDateClause(_ text: String) -> String {
        let lower = text.lowercased()
        for separator in [" | ", " - ", " – ", " — ", " · "] {
            guard let index = lower.range(of: separator, options: .backwards) else { continue }
            let suffix = lower[index.upperBound...]
            if looksLikeDateOrTime(String(suffix)) { return String(text[..<index.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return text
    }

    private static func looksLikeDateOrTime(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasDigit = value.contains(where: { $0.isNumber })
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec", "january", "february", "march", "april", "june", "july", "august", "september", "october", "november", "december"]
        let mentionsMonth = months.contains(where: value.contains)
        if value.contains("ago") || value.contains("updated") || value.contains("yesterday") || value.contains("today") { return true }
        if hasDigit && (value.contains("am") || value.contains("pm") || value.contains("utc") || value.contains("gmt") || value.contains("est") || value.contains("pst") || value.contains("cet")) { return true }
        if hasDigit && mentionsMonth { return true }
        return hasDigit && value.contains(":")
    }

    private static func looksLikeLiveTimestamp(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.contains("ago") || value.contains("updated") || value.contains("update") || value.contains("yesterday") || value.contains("today") { return true }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec", "january", "february", "march", "april", "june", "july", "august", "september", "october", "november", "december"]
        if months.contains(where: value.contains) { return false }
        let hasDigit = value.contains(where: { $0.isNumber })
        if hasDigit && value.contains(":") { return true }
        return hasDigit && ["am", "pm", "a.m", "p.m", "utc", "gmt", "est", "pst", "cet"].contains(where: value.contains)
    }

    static func cleanBylineText(_ text: String) -> String? {
        if case let .accepted(value) = cleanBylineTextWithReason(text) { return value }
        return nil
    }

    static func isBylineRedundantWithSiteName(_ byline: String, siteName: String) -> Bool {
        let author = normalizeWhitespace(byline).lowercased()
        let site = normalizeWhitespace(siteName).lowercased()
        guard author.count >= 3, let range = site.range(of: author) else { return false }
        let prefix = site[..<range.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: ":-–—|• "))
        let suffix = site[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: ":-–—|• "))
        return prefix.hasSuffix("by") || suffix.hasPrefix("by")
    }

    static func stripSiteName(_ title: String, siteName: String?) -> String {
        guard let siteName, !siteName.isEmpty else { return title }
        let separators = [" | ", " - ", " — ", " – ", " :: "]
        for separator in separators {
            let parts = title.components(separatedBy: separator)
            if parts.count > 1, parts.last?.localizedCaseInsensitiveCompare(siteName) == .orderedSame {
                return parts.dropLast().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return title
    }
}
