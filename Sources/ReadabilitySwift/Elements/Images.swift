enum ElementImages {
    static func standardize(_ html: String) -> String {
        // Keep this as a source-text rewrite like readabilityrs. Parsing and
        // reserializing an img through SwiftSoup can change quote style,
        // attribute order, and void-tag spelling before the Markdown pipeline.
        let pattern = "(?is)<img\\b[^>]*>"
        return SwiftRegex.replacingMatches(in: html, pattern: pattern) { captures in
            guard let original = captures.first.flatMap({ $0 }) else { return nil }
            return standardizeTag(String(original))
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
        return SwiftRegex.contains(source, pattern: "^data:image/(gif|png|jpeg|svg);base64,[A-Za-z0-9+/=]{0,200}$", caseInsensitive: true)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "(?i)(?:^|\\s)\(name)=([\"'])(.*?)\\1"
        guard let captures = SwiftRegex.captures(in: tag, pattern: pattern),
              captures.indices.contains(2), let value = captures[2] else { return nil }
        return String(value)
    }

    private static func replaceAttribute(_ name: String, old: String, new: String, in tag: String) -> String {
        guard !old.isEmpty else { return tag }
        let pattern = "(\\s\(name)=)([\"'])" + SwiftRegex.escaped(old) + "([\"'])"
        return SwiftRegex.replacing(in: tag, pattern: pattern, with: "$1$2\(escape(new))$3", caseInsensitive: true)
    }

    private static func escape(_ value: String) -> String {
        value.replacing("&", with: "&amp;")
            .replacing("\"", with: "&quot;")
            .replacing("<", with: "&lt;")
            .replacing(">", with: "&gt;")
    }
}
