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
        in bounds: Range<Index>? = nil
    ) -> Range<Index>? {
        guard !needle.isEmpty else {
            let start = bounds?.lowerBound ?? startIndex
            return start..<start
        }
        let bounds = bounds ?? startIndex..<endIndex
        guard bounds.lowerBound < bounds.upperBound else { return nil }
        return self[bounds].firstRange(of: needle)
    }

    func firstASCIICaseInsensitiveRange(
        of needle: String,
        in bounds: Range<Index>? = nil
    ) -> Range<Index>? {
        guard needle.utf8.allSatisfy({ $0 < 128 }) else {
            assertionFailure("ASCII case-insensitive search requires an ASCII needle")
            return nil
        }
        guard !needle.isEmpty else {
            let start = bounds?.lowerBound ?? startIndex
            return start..<start
        }
        let bounds = bounds ?? startIndex..<endIndex
        guard bounds.lowerBound < bounds.upperBound else { return nil }

        let needleBytes = needle.utf8.map(asciiFold)
        var start = bounds.lowerBound
        while let end = index(start, offsetBy: needleBytes.count, limitedBy: bounds.upperBound) {
            let candidate = self[start..<end].utf8
            if candidate.elementsEqual(needleBytes, by: { asciiFold($0) == $1 }) {
                return start..<end
            }
            guard start < bounds.upperBound else { break }
            formIndex(after: &start)
        }
        return nil
    }

    private func asciiFold(_ byte: UInt8) -> UInt8 {
        (65...90).contains(byte) ? byte + 32 : byte
    }

    func lastRange(of needle: String) -> Range<Index>? {
        guard !needle.isEmpty else { return endIndex..<endIndex }
        var result: Range<Index>?
        var lowerBound = startIndex
        while let range = firstRange(of: needle, in: lowerBound..<endIndex) {
            result = range
            lowerBound = index(after: range.lowerBound)
        }
        return result
    }

    func lastASCIICaseInsensitiveRange(of needle: String) -> Range<Index>? {
        guard !needle.isEmpty else { return endIndex..<endIndex }
        var result: Range<Index>?
        var lowerBound = startIndex
        while let range = firstASCIICaseInsensitiveRange(of: needle, in: lowerBound..<endIndex) {
            result = range
            lowerBound = index(after: range.lowerBound)
        }
        return result
    }

    func replacingASCIICaseInsensitive(_ target: String, with replacement: String) -> String {
        guard !target.isEmpty else { return self }
        var result = self
        var searchStart = result.startIndex
        while let range = result.firstASCIICaseInsensitiveRange(
            of: target,
            in: searchStart..<result.endIndex
        ) {
            result.replaceSubrange(range, with: replacement)
            searchStart = result.index(range.lowerBound, offsetBy: replacement.count)
        }
        return result
    }
}
