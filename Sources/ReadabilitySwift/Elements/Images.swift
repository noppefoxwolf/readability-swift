import Foundation

enum ElementImages {
    static func standardize(_ html: String) -> String {
        let pattern = "(?is)<img\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        var result = html
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed()
        for match in matches {
            guard let range = Range(match.range, in: html) else { continue }
            let original = String(html[range])
            guard let replacement = standardizeTag(original) else { continue }
            if let resultRange = Range(NSRange(location: match.range.location, length: match.range.length), in: result) {
                result.replaceSubrange(resultRange, with: replacement)
            }
        }
        return result
    }

    static func pickBestSrcset(_ srcset: String) -> String? {
        var best: (url: String, value: Double)?
        for rawEntry in srcset.split(separator: ",") {
            let entry = rawEntry.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if src.isEmpty { result = result.replacingOccurrences(of: "<img", with: "<img src=\"\(escape(dataSrc))\"", options: [.caseInsensitive]) }
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
        guard source.range(of: "^data:image/(gif|png|jpeg|svg);base64,[A-Za-z0-9+/=]{0,200}$", options: [.regularExpression, .caseInsensitive]) != nil else { return false }
        return true
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "(?i)\\b\(name)=([\"'])(.*?)\\1"
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)), let range = Range(match.range(at: 2), in: tag) else { return nil }
        return String(tag[range])
    }

    private static func replaceAttribute(_ name: String, old: String, new: String, in tag: String) -> String {
        guard !old.isEmpty else { return tag }
        let pattern = "(?i)(\\b\(name)=)([\"'])" + NSRegularExpression.escapedPattern(for: old) + "([\"'])"
        return tag.replacingOccurrences(of: pattern, with: "$1$2\(escape(new))$3", options: .regularExpression)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
