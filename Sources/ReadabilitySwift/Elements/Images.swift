enum ElementImages {
    private struct AttributeValue {
        let value: String
        let range: Range<String.Index>
    }

    static func standardize(_ html: String) -> String {
        // Keep this as a source-text rewrite like readabilityrs. Parsing and
        // reserializing an img through SwiftSoup can change quote style,
        // attribute order, and void-tag spelling before the Markdown pipeline.
        html.replacing(#/(?is)<img\b[^>]*>/#) { match in
            standardizeTag(String(match.0)) ?? String(match.0)
        }
    }

    static func pickBestSrcset(_ srcset: String) -> String? {
        var best: (url: String, value: Double)?
        for rawEntry in srcset.split(separator: ",") {
            let entry = rawEntry.trimmed()
            let parts = entry.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let url = parts.first, !url.isEmpty else { continue }
            let descriptor = parts.dropFirst().first.map(String.init) ?? ""
            let value = Double(descriptor.dropLast()) ?? 0
            if !descriptor.isEmpty, value > (best?.value ?? 0) {
                best = (String(url), value)
            } else if best == nil {
                best = (String(url), 0)
            }
        }
        return best?.url
    }

    private static func standardizeTag(_ tag: String) -> String? {
        let width = attribute("width", in: tag).flatMap(Int.init)
        let height = attribute("height", in: tag).flatMap(Int.init)
        if let width, let height, width < 100, height < 100 { return "" }
        var result = tag
        let src = attribute("src", in: result) ?? ""
        let dataSrc = attribute("data-src", in: result) ?? attribute("data-lazy-src", in: result) ?? ""
        if (src.isEmpty || isPlaceholder(src)) && !dataSrc.isEmpty {
            if src.isEmpty { result = result.replacingLiteral("<img", with: "<img src=\"\(escape(dataSrc))\"", caseInsensitive: true) }
            else { result = replaceAttribute("src", old: src, new: dataSrc, in: result) }
        }
        let srcset = attribute("srcset", in: result) ?? ""
        let dataSrcset = attribute("data-srcset", in: result) ?? ""
        let effectiveSrcset = srcset.isEmpty ? dataSrcset : srcset
        if !effectiveSrcset.isEmpty, let best = pickBestSrcset(effectiveSrcset) {
            result = replaceAttribute("src", old: attribute("src", in: result) ?? "", new: best, in: result)
        }
        return result
    }

    private static func isPlaceholder(_ source: String) -> Bool {
        if source.contains("placeholder") || source.contains("blank.gif") || source.contains("spacer.gif") { return true }
        return source.wholeMatch(of: #/(?i)data:image/(?:gif|png|jpeg|svg);base64,[A-Za-z0-9+/=]{0,200}/#) != nil
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        attributeValue(name, in: tag)?.value
    }

    private static func replaceAttribute(_ name: String, old: String, new: String, in tag: String) -> String {
        guard !old.isEmpty,
              let attribute = attributeValue(name, in: tag),
              attribute.value == old else { return tag }
        var result = tag
        result.replaceSubrange(attribute.range, with: escape(new))
        return result
    }

    private static func attributeValue(_ name: String, in tag: String) -> AttributeValue? {
        var searchStart = tag.startIndex
        while let nameRange = tag.firstRange(
            of: name,
            caseInsensitive: true,
            in: searchStart..<tag.endIndex
        ) {
            let hasAttributeBoundary = nameRange.lowerBound == tag.startIndex
                || tag[tag.index(before: nameRange.lowerBound)].isWhitespace
            let equals = nameRange.upperBound
            guard hasAttributeBoundary,
                  equals < tag.endIndex,
                  tag[equals] == "=" else {
                searchStart = tag.index(after: nameRange.lowerBound)
                continue
            }
            let quoteIndex = tag.index(after: equals)
            guard quoteIndex < tag.endIndex,
                  tag[quoteIndex] == "\"" || tag[quoteIndex] == "'" else {
                searchStart = tag.index(after: nameRange.lowerBound)
                continue
            }
            let valueStart = tag.index(after: quoteIndex)
            guard let valueEnd = tag[valueStart...].firstIndex(of: tag[quoteIndex]) else { return nil }
            let range = valueStart..<valueEnd
            return AttributeValue(value: String(tag[range]), range: range)
        }
        return nil
    }

    private static func escape(_ value: String) -> String {
        value.replacing("&", with: "&amp;")
            .replacing("\"", with: "&quot;")
            .replacing("<", with: "&lt;")
            .replacing(">", with: "&gt;")
    }
}
