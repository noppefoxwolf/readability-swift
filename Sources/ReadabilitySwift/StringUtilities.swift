import Synchronization

extension StringProtocol {
    func trimmed(where shouldTrim: (Character) -> Bool = { $0.isWhitespace }) -> String {
        guard let first = firstIndex(where: { !shouldTrim($0) }) else { return "" }
        let last = lastIndex(where: { !shouldTrim($0) }) ?? first
        return String(self[first...last])
    }

    func lines() -> [SubSequence] {
        split(separator: "\n", omittingEmptySubsequences: false)
    }
}

extension String {
    func collapsingRepeatedWhitespace() -> String {
        var result = ""
        var whitespace = ""
        for character in self {
            guard character.isWhitespace else {
                if whitespace.count == 1 { result += whitespace }
                else if !whitespace.isEmpty { result.append(" ") }
                whitespace.removeAll(keepingCapacity: true)
                result.append(character)
                continue
            }
            whitespace.append(character)
        }
        if whitespace.count == 1 { result += whitespace }
        else if !whitespace.isEmpty { result.append(" ") }
        return result
    }

    func firstRange(
        of needle: String,
        caseInsensitive: Bool = false,
        in bounds: Range<Index>? = nil
    ) -> Range<Index>? {
        guard !needle.isEmpty else {
            let start = bounds?.lowerBound ?? startIndex
            return start..<start
        }
        let bounds = bounds ?? startIndex..<endIndex
        guard bounds.lowerBound < bounds.upperBound else { return nil }
        if !caseInsensitive {
            return self[bounds].firstRange(of: needle)
        }

        if needle.utf8.allSatisfy({ $0 < 128 }) {
            let needleBytes = needle.utf8.map(asciiFold)
            var start = bounds.lowerBound
            let upperBound = bounds.upperBound
            while let end = index(start, offsetBy: needleBytes.count, limitedBy: upperBound) {
                let candidate = self[start..<end].utf8
                if candidate.elementsEqual(needleBytes, by: { asciiFold($0) == $1 }) {
                    return start..<end
                }
                guard start < upperBound else { break }
                formIndex(after: &start)
            }
            return nil
        }

        let foldedNeedle = needle.lowercased()
        var start = bounds.lowerBound
        while start < bounds.upperBound {
            guard let end = index(start, offsetBy: needle.count, limitedBy: bounds.upperBound) else {
                return nil
            }
            if self[start..<end].lowercased() == foldedNeedle {
                return start..<end
            }
            formIndex(after: &start)
        }
        return nil
    }

    private func asciiFold(_ byte: UInt8) -> UInt8 {
        (65...90).contains(byte) ? byte + 32 : byte
    }

    func lastRange(of needle: String, caseInsensitive: Bool = false) -> Range<Index>? {
        guard !needle.isEmpty else { return endIndex..<endIndex }
        var result: Range<Index>?
        var lowerBound = startIndex
        while let range = firstRange(
            of: needle,
            caseInsensitive: caseInsensitive,
            in: lowerBound..<endIndex
        ) {
            result = range
            lowerBound = index(after: range.lowerBound)
        }
        return result
    }

    func replacingLiteral(
        _ target: String,
        with replacement: String,
        caseInsensitive: Bool = false
    ) -> String {
        guard !target.isEmpty else { return self }
        guard caseInsensitive else { return replacing(target, with: replacement) }
        var result = self
        var searchStart = result.startIndex
        while let range = result.firstRange(
            of: target,
            caseInsensitive: true,
            in: searchStart..<result.endIndex
        ) {
            result.replaceSubrange(range, with: replacement)
            searchStart = result.index(range.lowerBound, offsetBy: replacement.count)
        }
        return result
    }
}

enum SwiftRegex {
    private static let cache = Mutex<[String: Regex<AnyRegexOutput>]>([:])

    struct Match {
        let range: Range<String.Index>
        let captures: [Substring?]
    }

    static func contains(_ value: String, pattern: String, caseInsensitive: Bool = false) -> Bool {
        guard let regex = compile(pattern, caseInsensitive: caseInsensitive) else { return false }
        return value.firstMatch(of: regex) != nil
    }

    static func containsLiteralAlternative(
        _ value: String,
        pattern: String,
        caseInsensitive: Bool = false
    ) -> Bool {
        let value = caseInsensitive ? value.lowercased() : value
        return pattern.split(separator: "|").contains { rawAlternative in
            var alternative = String(rawAlternative)
            let anchoredAtStart = alternative.first == "^"
            let anchoredAtEnd = alternative.last == "$"
            if anchoredAtStart { alternative.removeFirst() }
            if anchoredAtEnd { alternative.removeLast() }
            if caseInsensitive { alternative = alternative.lowercased() }
            if anchoredAtStart && anchoredAtEnd { return value == alternative }
            if anchoredAtStart { return value.hasPrefix(alternative) }
            if anchoredAtEnd { return value.hasSuffix(alternative) }
            return value.contains(alternative)
        }
    }

    static func firstRange(
        in value: String,
        pattern: String,
        caseInsensitive: Bool = false
    ) -> Range<String.Index>? {
        guard let regex = compile(pattern, caseInsensitive: caseInsensitive) else { return nil }
        return value.firstMatch(of: regex)?.range
    }

    static func ranges(
        in value: String,
        pattern: String,
        caseInsensitive: Bool = false
    ) -> [Range<String.Index>] {
        guard let regex = compile(pattern, caseInsensitive: caseInsensitive) else { return [] }
        return value.matches(of: regex).map(\.range)
    }

    static func captures(
        in value: String,
        pattern: String,
        caseInsensitive: Bool = false
    ) -> [Substring?]? {
        guard let regex = compile(pattern, caseInsensitive: caseInsensitive),
              let match = value.firstMatch(of: regex) else { return nil }
        return match.output.map(\.substring)
    }

    static func firstMatch(
        in value: String,
        pattern: String,
        caseInsensitive: Bool = false
    ) -> Match? {
        guard let regex = compile(pattern, caseInsensitive: caseInsensitive),
              let match = value.firstMatch(of: regex) else { return nil }
        return Match(range: match.range, captures: match.output.map(\.substring))
    }

    static func replacing(
        in value: String,
        pattern: String,
        with replacementTemplate: String,
        caseInsensitive: Bool = false
    ) -> String {
        guard let regex = compile(pattern, caseInsensitive: caseInsensitive) else { return value }
        var result = value
        for match in value.matches(of: regex).reversed() {
            let replacement = expanded(replacementTemplate, captures: match.output.map(\.substring))
            result.replaceSubrange(match.range, with: replacement)
        }
        return result
    }

    static func replacingMatches(
        in value: String,
        pattern: String,
        transform: ([Substring?]) -> String?
    ) -> String {
        guard let regex = compile(pattern, caseInsensitive: false) else { return value }
        var result = value
        for match in value.matches(of: regex).reversed() {
            guard let replacement = transform(match.output.map(\.substring)) else { continue }
            result.replaceSubrange(match.range, with: replacement)
        }
        return result
    }

    static func split(
        _ value: String,
        pattern: String,
        caseInsensitive: Bool = false
    ) -> [String] {
        guard let regex = compile(pattern, caseInsensitive: caseInsensitive) else { return [value] }
        var pieces: [String] = []
        var start = value.startIndex
        for match in value.matches(of: regex) {
            pieces.append(String(value[start..<match.range.lowerBound]))
            start = match.range.upperBound
        }
        pieces.append(String(value[start...]))
        return pieces
    }

    static func escaped(_ value: String) -> String {
        let metacharacters = #"\.^$|?*+()[]{}"#
        return value.reduce(into: "") { result, character in
            if metacharacters.contains(character) { result.append("\\") }
            result.append(character)
        }
    }

    private static func compile(
        _ pattern: String,
        caseInsensitive: Bool
    ) -> Regex<AnyRegexOutput>? {
        let source = caseInsensitive ? "(?i:\(pattern))" : pattern
        return cache.withLock { cache in
            if let regex = cache[source] { return regex }
            guard let regex = try? Regex(source) else { return nil }
            cache[source] = regex
            return regex
        }
    }

    private static func expanded(_ template: String, captures: [Substring?]) -> String {
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            guard template[index] == "$" else {
                result.append(template[index])
                template.formIndex(after: &index)
                continue
            }
            let dollar = index
            template.formIndex(after: &index)
            let digitsStart = index
            while index < template.endIndex, template[index].isNumber {
                template.formIndex(after: &index)
            }
            guard digitsStart < index,
                  let captureIndex = Int(template[digitsStart..<index]),
                  captures.indices.contains(captureIndex) else {
                result.append(template[dollar])
                continue
            }
            if let capture = captures[captureIndex] { result += capture }
        }
        return result
    }
}
