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
