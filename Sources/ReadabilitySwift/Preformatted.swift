enum Preformatted {
    private static let tagNames = ["pre", "code"]

    static func mapOutside(_ html: String, transform: (String) -> String) -> String {
        var output = ""
        output.reserveCapacity(html.count)
        var plainStart = html.startIndex
        var cursor = html.startIndex

        while let opening = html[cursor...].firstIndex(of: "<") {
            var opaqueEnd = commentEnd(in: html, at: opening)
            if opaqueEnd == nil,
               let tagName = tagNames.first(where: { startsTag(in: html, at: opening, name: $0, closing: false) }) {
                opaqueEnd = blockEnd(in: html, at: opening, name: tagName) ?? html.endIndex
            }

            guard let opaqueEnd else {
                cursor = html.index(after: opening)
                continue
            }

            output += transform(String(html[plainStart..<opening]))
            output += html[opening..<opaqueEnd]
            plainStart = opaqueEnd
            cursor = opaqueEnd
        }

        output += transform(String(html[plainStart...]))
        return output
    }

    private static func blockEnd(in html: String, at opening: String.Index, name: String) -> String.Index? {
        guard let openingEnd = html[opening...].firstIndex(of: ">") else { return nil }
        var depth = 1
        var cursor = html.index(after: openingEnd)

        while let candidate = html[cursor...].firstIndex(of: "<") {
            if let commentEnd = commentEnd(in: html, at: candidate) {
                cursor = commentEnd
                continue
            }
            if startsTag(in: html, at: candidate, name: name, closing: true) {
                guard let closingEnd = html[candidate...].firstIndex(of: ">") else { return nil }
                depth -= 1
                let end = html.index(after: closingEnd)
                if depth == 0 { return end }
                cursor = end
                continue
            }
            if startsTag(in: html, at: candidate, name: name, closing: false) {
                depth += 1
            }
            cursor = html.index(after: candidate)
        }
        return nil
    }

    private static func commentEnd(in html: String, at opening: String.Index) -> String.Index? {
        guard html[opening...].hasPrefix("<!--"),
              let closing = html.range(of: "-->", range: opening..<html.endIndex) else { return nil }
        return closing.upperBound
    }

    private static func startsTag(
        in html: String,
        at opening: String.Index,
        name: String,
        closing: Bool
    ) -> Bool {
        var nameStart = html.index(after: opening)
        if closing {
            guard nameStart < html.endIndex, html[nameStart] == "/" else { return false }
            nameStart = html.index(after: nameStart)
        } else if nameStart < html.endIndex, ["/", "!", "?"].contains(html[nameStart]) {
            return false
        }

        guard let nameEnd = html.index(nameStart, offsetBy: name.count, limitedBy: html.endIndex),
              html[nameStart..<nameEnd].caseInsensitiveCompare(name) == .orderedSame,
              nameEnd < html.endIndex else { return false }
        return [" ", "\t", "\n", "\r", "\u{000C}", ">"].contains(html[nameEnd])
    }
}
